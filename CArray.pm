package CArray;
#
#   "Better to do it in Perl than C."  - from C::Dynalib.pm
#
#   "Better do it in C than in Perl."  - CArray.pm
#
use strict;
local $^W = 1;
use Carp;
use vars qw($VERSION @ISA);
require DynaLoader;
#use Autoloader;    # while testing remove this
$VERSION = '0.11';
@ISA = qw(DynaLoader);

=head1 NAME

CArray - External C Arrays for Perl (Alpha)

=head1 SYNOPSIS

    use CArray;
    $dblarr = new CDoubleArray(1000);

    @values = (0..1000);
    $dblarr = new CIntArray(1000,\@values);
    ref $dblarr eq 'CIntArray' and
      $dblarr->set(0,1) and
      $dblarr->get(0) == 1;

    tie (@array, 'CDoubleArray', 1000, \@values);
    print $array[0], join ', ', @dbl[1..20];

=head1 DESCRIPTION

Several XS classes and methods to deal with unstructured continuous
C arrays are provided, for the three basic C-types array of I<INT>, I<DOUBLE>
and I<STRING> and some aggregate types int[2][], int[3][], int[4][],
double[2][], double[3][] as range checked, tieable arrays.

This roughly reflects to:

    CArray
        CIntArray               int[]
            CInt2Array          int[][2]
            CInt3Array          int[][3]
            CInt4Array          int[][4]
        CDoubleArray            double[]
            CDouble2Array       double[][2]
            CDouble3Array       double[][3]
        CStringArray            *char[]

External C arrays limit communication overhead with large simple data 
structures, where size or time constraints become serious, optionally 
manipulated by external XS modules. 
Such as various computional geometry modules dealing with 10.000 - 200.000
double[3]. Modification is done in-place and preferably in bulk.

It might also be easier to write XSUBs by converting the data to CArray's
before, pass this pointer to the C func, and handle the results in Perl
then.

The Fetch/Store operations with tied arrays copy the scalars to perl
and back, so it shouldn't be abused for BIG data.

Perl's safemalloc/safefree is used.

=cut
bootstrap CArray $VERSION;

# Preloaded methods go here.
package CArray;

use Tie::Array;
use strict;
use vars qw(@ISA);
use Carp;
@ISA = qw(Tie::Array);

# mandatory methods defined only for the abstract class CArray,
# in terms of the autoloaded spezialized methods
=pod

=head1 CLASS METHODS

=over 4

=item new ( SIZE, [ ARRAYREF ] )

The new method is provided for all classes, the optional arrayref arg
applies only to the base C<Array> classes, not the aggregate.

The constructor creates a new C<CArray> object. For the C<Array>
classes the second optional argument is used to initialize it with an
array. If the provided arrayref is shorter that the allocated size, the
rest will stay uninitialized.

    $D = new CDoubleArray(1000,[0..999]);

=cut

# the whole rawclass issue is gone.
# only needed for CArray and the aggregate classes
sub new {
  no strict 'refs';
  my $class = shift;
  # CArray::new as virtual baseclass needs an additional second type arg.
  $class = shift if $class eq 'CArray';
  my $size  = shift;
  # the CArray arg initializer not, we have copy instead
  confess "usage: new $class (size, [ARRAYREF])"
      if $size =~ /\D/;
  my $initval = shift;
  $class =~ /(.*)(\d)(.*)/;
  if ($2) {
    $initval
        ? bless( &{$1 . $3 . '::new'}($size * $2, $initval), $class)
        : bless( &{$1 . $3 . '::new'}($size * $2), $class);
  } else {
    $initval
        ? bless( &{$class . '::new'}($size, $initval), $class)
        : bless( &{$class . '::new'}($size), $class);
  }
}

=pod

=item init ( values )

A seperate init method for bulk definitions. (fill)

This is the same as the second new argument.
If the provided values arrayref is shorter that the allocated size,
the rest will stay uninitialized.

  $I = CIntArray::new(100) ;
  $I->init( [0..99] );

=item len ()

The len method returns the length of the array, 1+ the index of the
last element. To enlarge the array grow() should be used.

    $D  = new CDoubleArray(5000);
    for my $j (0 .. $D->len-1) { $D->set($_, 0.0)); }
    $D->len; # => 5000

=item get ( index )

get returns the value at the given index, which will be scalar or a list.
Croaks with "index out of range" on wrong index.

    $I = new CIntArray(2,[0,1]);
    print $I->get(1); # => 1
    print $I->get(2);
      => croak "index out of range"

    $I2 = new CInt2Array(2,[[0,1]]);
    print $I->get(0); # => (0 1)

=item set ( index, value )

The set method is provided for all classes.
It changes the value at the given index.
The value should be either a scalar or an arrayref.
Croaks with "index out of range" on wrong index.
Returns nothing.

    $I = new CIntArray(100);
    map { $I->set($_,$i[$_]) } (0..99);
    $I->set(99,-1);
    $I->set(100);
      => "index out of range"

    $I2 = CInt2Array->new(2);
    $I2->set(0, [1,0]);
    $I2->set(1, [0,1]);

=item list ()

Returns the content of the flat array representation as arrayref.

=item grow ( n )

Adds room for n elements to the array. These elements must be initialized
extra with set.
To support faster grow() a certain number of already pre-allocated items
at the end of the array will be used. (see free)
Returns nothing.

=item delete ( index )

Deletes the item at the given index. free is incremented and the remaining
array items are shifted. Returns nothing.

=item get_grouped_by ( size, index )

Returns a list of subsequent values.
It returns a list of size indices starting at size * index.
This is useful to abuse the unstructured array as typed array of the
same type, such as *double[3] or *int[2].

But this is normally not used since fast get methods are provided for the
sequential classes, and those methods can be used on flat arrays as well.
(Internally all sequential arrays are flat).

  CInt3Array::get($I,0) == $I->get_grouped_by(3,0)

$ptr->get_grouped_by(2,4) returns the 4-th pair if the array is seen
as list of pairs.

  $ptr->get_grouped_by(3,$i) => (ptr[i*3] ptr[i*3+1] ptr[i*3+2] )

=cut

# support for structured data, such as typedef int[3] Triangle
# returns the i-th slice of length by
sub get_grouped_by ($$$) {     #22.11.99 13:14
  my $self = shift;
  my $by   = shift;
  my $i    = shift;
  $i *= $by;
  map { $self->get($i++) } (1 .. $by);
}

# c++ like slice operator: start, size, stride
# => list of size items with stride interim offsets, matrix rows and cols
sub slice ($$$;$) {
  my $self  = shift;
  my $start = shift;
  my $size  = shift;
  my $stride = shift || 1;
  # absolute offsets
  map { $self->get($_) }
      map { $start + ($_ * $stride) }
          (0 .. $size-1);
}

=pod

=item slice ( start, size, [ stride=1 ] )

C++ like slice operator on a flat array. - In contrast to get_grouped_by()
which semantics are as on a grouped array.

Returns a list of size items, starting at start,
with interim offsets of stride which defaults to 1.
This is useful to return columns or rows of a flat matrix.

  $I = new CIntArray (9, [0..8]);
  $I->slice ( 0, 3, 3 ); # 1st column
    => (0 3 6)
  $I->slice ( 0, 3, 1 ); # 1st row
    => (0 1 2)
  $I->get_grouped_by(3, 0);
    => (0 1 2)

=item isort ()

"Indirect sort", numerically ascending only.
Returns a fresh sorted index list of integers (0 .. len-1)

=cut

sub isort ($) {      #03.12.99 12:00
  sort {$_[0]->get($a) <=> $_[0]->get($b)} (0 .. $_[0]->len() -1);
}

=pod

=item nreverse ()

"Reverse in place". (The name comes from lisp, where n denotes the
destructive version).
Destructively swaps all array items. Returns nothing.

=back

=head1 SEQUENTIAL CLASSES and CONVERSION

=over 4

To mix and change parallel and sequential data structures, the aggregate
(ie sequential) types are derived from their base classes with fast
get and set methods to return and accept lists instead of scalars.

The Arrays for Int2, Int3, Int4, Double2 and Double3
can also be converted from and to their base objects with fast XS methods.

  # three parallel CIntArray's
  $X = new CIntArray(1000);
  $Y = new CIntArray(1000);
  $Z = new CIntArray(1000);

  # copy to one sequential *int[3], new memory
  $I = $X->ToInt3($Y,$Z);

  # or to an existing array
  $I = new CIntArray(3000);
  $I = $X->ToInt3($Y,$Z,$I);

  # copies back with allocating new memory
  ($X, $Y, $Z) = $I->ToPar();

  # copies back with reusing some existing memory (not checked!)
  ($X, $Y, $Z) = $I->ToPar($X,$Z);  # Note: I3 will be fresh.

=item ToPar ( SeqArray, [ CArray,... ] )

This returns a list of CArray objects, copied from the sequential object to
plain parallel CArray objects. This is a fast slice.

  *int[2] => (*int, *int)

  CInt2Array::ToPar
  CInt3Array::ToPar
  CInt4Array::ToPar
  CDouble2Array::ToPar
  CDouble3Array::ToPar

If the optional CArray args are given the memory for the returned objects are
not new allocated, the space from the given objects is used instead.

=item To$Type$Num ( CArray, ..., [ CArray ] )

This returns a sequential CArray object copied from the parallel objects
given as arguments to one sequential CArray. This is a fast map.

  *int, *int => *int[2]

  CIntArray::ToInt2
  CIntArray::ToInt3
  CIntArray::ToInt4
  CDoubleArray::ToDouble2
  CDoubleArray::ToDouble3

If the last optional CArray arg is defined the memory for the returned
object is not new allocated, the space from the given object is used instead.

=back

=head1 INTERNAL METHODS

=over 4

=item DESTROY ()

This used to crash on certain DEBUGGING perl's, but seems
to be okay now.
Returns nothing.

=item CArray::itemsize ( )

=item CStringArray::itemsize ( [index] )

Returns the size in bytes per item stored in the array. This is only
used internally to optimize memory allocation and the free list.

A CStringArray object accepts the optional index argument, which returns the
string length at the given index. Without argument it returns the size in
bytes of a char * pointer (which is 4 on 32 bit systems).

=item copy ()

Returns a freshly allocated copy of the array with the same contents.

=item free ()

Internal only.
Returns the number of free elements at the end of the array.
If grow() needs less or equal than free elements to be added,
no new room will be allocated.

This is primarly for performance measures.

=back

=cut

# the specialized Array classes go here
# the Ptr classes are defined in the XS
package CIntArray;
use strict;
use integer;
use vars qw(@ISA);
use Carp;
@ISA = qw( CArray );

package CDoubleArray;
use strict;
no integer;
use vars qw(@ISA);
use Carp;
@ISA = qw( CArray );

package CStringArray;
use strict;
use vars qw(@ISA);
use Carp;
@ISA = qw( CArray );

# These will be autoloaded after testing.
# Autoload methods go after __END__, and are processed by the autosplit program.

# Base aggregate class, purely virtual.
# get and set via get_grouped_by was 24 times slower than the XS version
# now. This is for the not so time-critical functions.
package CArray::CSeqBase;
use vars qw(@ISA);
@ISA = qw(CArray);
use Carp;

sub by   {  $_[0] =~ /(\d)/;
            return $1; }
sub base {  $_[0] =~ /(.*)\d(.*)/;
            return $1 . $2; }

# size of item in bytes. this should be exported by the XS
# last resort, normally not needed
sub itemsize {
    my $class = ref($_[0]) || $_[0];
    $class =~ /(.*)\d/;
    if ($1 eq 'CInt')       { $class->by * 4; }
    elsif ($1 eq 'CDouble') { $class->by * 8; }
    else                    { 0 }
}

sub len ()  { $_[0]->SUPER::len / $_[0]->by };
sub free () { $_[0]->SUPER::free / $_[0]->by };

sub new ($$;$) {
    my $class = shift;
    my $n     = shift;
    my $init  = shift;
    croak "cannot call new CArray::CSeqBase"
        if $class =~ /CArray::CSeqBase/;
    warn "cannot initialize CArray::CSeqBase: ignored" if $init;
    bless ($class->base->new($n * $class->by), $class);
}

# 24 times faster XSUB versions provided
#sub get ($$){
#    my ($self,$i, $class) = @_;
#    $class = ref $self;
#    my $by = $self->by();
#    bless ($self,$self->base);  # downgrade to flat
#    my @array = $self->get_grouped_by( $by, $i );
#    bless ($self,$class);       # upgrade it back
#    return @array;
#}
#sub set ($$$){
#    my ($self,$i,$val,$class) = @_;
#    $class = ref $self;
#    my $by = $self->by; $i *= $by;
#    $self = bless ($self,$self->base);
#    my @array = map { $self->set( $i++, $val->[$_] ) } (0 .. $by);
#    $self = bless ($self,$class);
#    return @array;
#}

# the aggregate classes: just override the base methods
package CInt2Array;
use vars qw(@ISA);
@ISA = qw( CArray::CSeqBase CIntArray );

package CInt3Array;
use vars qw(@ISA);
@ISA = qw( CArray::CSeqBase CIntArray );

package CInt4Array;
use vars qw(@ISA);
@ISA = qw( CArray::CSeqBase CIntArray );

package CDouble2Array;
use vars qw(@ISA);
@ISA = qw( CArray::CSeqBase CDoubleArray );

package CDouble3Array;
use vars qw(@ISA);
@ISA = qw( CArray::CSeqBase CDoubleArray );

#
############################################################################
=pod

=head1 TIEARRAY METHODS

B<Not tested yet!>

=over 4

=item tie (var, type, size)

After tying a array variable to an C<CArray> class the variable can
be used just as any normal perl array.

  tie (@array, 'CDoubleArray', 200);
  print $array[200];
    => croak "index out of range"

=back

=cut
# The TIEARRAY stuff should be autoloaded (after testing)

package CArray;

sub TIEARRAY  { $_[0]->new(@_) }
sub FETCH     { $_[0]->get(@_) }
sub FETCHSIZE { $_[0]->len()  }
sub STORE     { $_[0]->set(@_) }

# mandatory if elements can be added/deleted
# Note: we have a fast grow and delete method now
#sub STORESIZE {
#  no strict 'refs';
#  my $self = shift;
#  my $newsize  = shift;
#  my $size     = $self->len();
#  my $rawclass = $self->rawclass();
#  # or $self->PTR->set()
#  my $setfunc  = \&{"${rawclass}\:\:set"}();
#  my $arrayptr = $self->PTR();
#  if ($newsize > $size) {
#    my $new      = $self->new($size);
#    my $newarray = $new->PTR();
#    my $getfunc  = \&{"${rawclass}\:\:get"}();
#    # or $self->PTR->get()
#    for my $i (0 .. $size-1) {
#      &$setfunc($newarray, $i, &$getfunc($arrayptr,$i));
#    }
#    # or $self->PTR->DESTROY()
#    $self->DESTROY();
#    return $new;
#  } else {
#    for my $j ($newsize .. $size-1) { &$setfunc($arrayptr, $j, 0); }
#    $self->len($newsize);
#    return $self;
#  }
#}

1;

__END__
=pod

=head1 SEE ALSO

http://xarch.tu-graz.ac.at/home/rurban/software/perl or
ftp://xarch.tu-graz.ac.at/pub/autocad/urban/perl

L<perlxs(1)>, L<perlfunc/tie>, Tie::Array, Geometry::Points,
C::Dynalib::Poke

=head1 AUTHOR

Reini Urban <rurban@x-ray.at>

=head1 COPYRIGHT

Copyright (c) 1999 Reini Urban.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 WARNING

These classes may be easily abused and may lead to system crashes or worse.

Old: CPtr objects do no range checking at all, so may unintentionally access or
overwrite foreign memory. This might only crash the system in the best case.

Bad malloc'd perls or systems might also lead to destruction.

The author makes B<NO WARRANTY>, implied or otherwise, about the
suitability of this software for safety or security purposes.

The author shall not in any case be liable for special, incidental,
consequential, indirect or other similar damages arising from the use
of this software.

Your mileage will vary. If in any doubt B<DO NOT USE IT>. You've been warned.

=head1 BUGS

There are certainly some. Not fully tested yet.
Tests for copy, grow, delete, tie are pending.
Also some more conversion tests, esp. with double and degenerate
(grow, cut) cases.

=over

=item 1

realloc() in string_set() with DEBUGGING perl fails sometimes.

=item 2

An implicit DESTROY invocation sometimes asserts a DEBUGGING perl,
regardless if PERL_MALLOC or the WinNT msvcrt.dll malloc is used.
(5.00502 - 5.00558)
Esp. on perl shutdown, when freeing the extra objects at the second GC.

This became much better in 0.08 than in previous versions.

=back

This is alpha, not fully tested yet!

=head1 Last Changed

1999/12/05

=cut