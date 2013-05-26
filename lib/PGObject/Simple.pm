package PGObject::Simple;

use 5.006;
use strict;
use warnings;
use Carp;
use PGObject;

=head1 NAME

PGObject::Simple - Minimalist stored procedure mapper based on LedgerSMB's DBObject

=head1 VERSION

Version 1.0

=cut

our $VERSION = '1.0';


=head1 SYNOPSIS

  use PGObject::Simple;
  my $obj = PGObject::Simple->new(%myhash);
  $obj->set_dbh($dbh); # Database connection

To call a stored procedure with enumerated arguments.

  my @results = $obj->call_procedure(
      funcname     => $funcname,
      funcschema   => $funcname,
      args         => [$arg1, $arg2, $arg3],
  );

You can add something like a running total as well:

  my @results = $obj->call_procedure(
      funcname      => $funcname,
      funcschema    => $funcname,
      args          => [$arg1, $arg2, $arg3],
      running_funcs => [{agg => 'sum(amount)', alias => 'total'}],
  );

To call a stored procedure with named arguments from a hashref.  This is 
typically done when mapping object properties in to stored procedure arguments.

  my @results = $obj->call_dbmethod(
      funcname      => $funcname,
      funcschema    => $funcname,
      running_funcs => [{agg => 'sum(amount)', alias => 'total'}],
  );

To call a stored procedure with named arguments from a hashref with overrides.

  my @results = $obj->call_dbmethod(
      funcname      => 'customer_save',
      funcschema    => 'public',
      running_funcs => [{agg => 'sum(amount)', alias => 'total'}],
      args          => { id => undef }, # force to create new!
  );

=head1 DESCRIPTION

PGObject::Simple a top-half object system for PGObject which is simple and
inspired by (and a subset functionally speaking of) the simple stored procedure
object method system of LedgerSMB 1.3. The framework discovers stored procedure
APIs and dispatches to them and can therefore be a base for application-specific
object models and much more.

PGObject::Simple is designed to be light-weight and yet robust glue between your
object model and the RDBMS's stored procedures. It works by looking up the
stored procedure arguments, stripping them of the conventional prefix 'in_', and
mapping what is left to object property names. Properties can be
overridden by passing in a hashrefs in the args named argument. Named arguments
there will be used in place of object properties.

This system is quite flexible, perhaps too much so, and it relies on the
database encapsulating its own logic behind self-documenting stored procedures
using consistent conventions. No function which is expected to be discovered can
be overloaded, and all arguments must be named for their object properties. For
this reason the use of this module fundamentally changes the contract of the
stored procedure from that of a fixed number of arguments in fixed types
contract to one where the name must be unique and the stored procedures must be
coded to the application's interface. This inverts the way we typically think
about stored procedures and makes them much more application friendly.

=head1 SUBROUTINES/METHODS

=head2 new

This constructs a new object.  Basically it copies the incoming hash (one level
deep) and then blesses it.  It does not set the dbh or anything.

=cut

sub new {
    my ($self) = shift @_;
    my %args = @_;
    my $ref = {};
    $ref->{$_} = $args{$_} for keys %args;
    bless ($ref, $self);
    $ref->set_dbh($ref->{dbh}) if $ref->{dbh};
    return $ref;
}

=head2 set_dbh

=cut

sub set_dbh {
    my ($self, $dbh) = @_;
    $self->{_DBH} = $dbh;
}

=head2 call_dbmethod

=cut

sub call_dbmethod {
    my ($self) = shift @_;
    my %args = @_;
    $args{dbh} = $self->{_DBH} if $self->{_DBH} and !$args{dbh};
    croak 'No function name provided' unless $args{funcname};
    croak 'No DB handle provided' unless $args{dbh};

    my $info = PGObject->function_info(%args);

    my $dbargs = [];
    for my $arg (@{$info->{args}}){
        $arg->{name} =~ s/^in_//;
        my $db_arg = $self->{$arg->{name}};
        if ($args{args}->{$arg->{name}}){
           $db_arg = $args{args}->{$arg->{name}};
        }
        if (eval {$db_arg->can('to_db')}){
           $db_arg = $db_arg->to_db;
        }
        if ($arg->{type} eq 'bytea'){
           $db_arg = { type => 'bytea', value => $db_arg};
        }
        push @$dbargs, $db_arg;
    }
    $args{args} = $dbargs;
    return $self->call_procedure(%args);
}

=head2 call_procedure 

This is a lightweight wrapper around PGObject->call_procedure which merely
passes the currently attached db connection in.

=cut

sub call_procedure {
    my ($self) = shift @_;
    my %args = @_;

    $args{dbh} = $self->{_DBH} if $self->{_DBH} and !$args{dbh};

    croak 'No DB handle provided' unless $args{dbh};
    PGObject->call_procedure(%args);
}

=head1 WRITING CLASSES WITH PGObject::Simple

Unlike PGObject, which is only loosely tied to the functionality in question
and presumes that relevant information will be passed over a functional 
interface, PGObject is a specific framework for object-oriented coding in Perl.
It can therefore be used alone or with other modules to provide quite a bit of
functionality.

A PGObject::Simple object is a blessed hashref with no gettors or setters.  This
is thus ideal for cases where you are starting and just need some quick mappings
of stored procedures to hashrefs.  You reference properties simply with the
$object->{property} syntax.  There is very little encapsulation in objects, and 
very little abstraction except when it comes to the actual stored procedure 
interfaces.   In essence, PGObject::Simple generally assumes that the actual
data structure is essentially a public interface between the database and 
whatever else is going on with the application.

The general methods can then wrap call_procedure and call_dbmethod calls,
mapping out to stored procedures in the database.

Stored procedures must be written to relatively exacting specifications.  
Arguments must be named, with names prefixed optionally with 'in_' (if the 
property name starts with 'in_' properly one must also prefix it).

An example of a simple stored procedure might be:

   CREATE OR REPLACE FUNCTION customer_get(in_id int) returns customer 
   RETURNS setof customer language sql as $$

   select * from customer where id = $1;

   $$;

This stored procedure could then be called with any of:

   $obj->call_dbmethod(
      funcname => 'customer_get', 
   ); # retrieve the customer with the $obj->{id} id

   $obj->call_dbmethod(
      funcname => 'customer_get',
      args     => {id => 3 },
   ); # retrieve the customer with the id of 3 regardless of $obj->{id}

   $obj->call_procedure(
      funcname => 'customer_get',
      args     => [3],
   );

=head1 AUTHOR

Chris Travers, C<< <chris.travers at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-pgobject-simple at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=PGObject-Simple>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PGObject::Simple


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=PGObject-Simple>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/PGObject-Simple>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/PGObject-Simple>

=item * Search CPAN

L<http://search.cpan.org/dist/PGObject-Simple/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Chris Travers.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of PGObject::Simple
