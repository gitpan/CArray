# IntArray conversions

use CArray;
use strict;
use vars qw( $n $failed @i $I $I2 $I3 $I4 @rev @i @i2 );
local $^W = 1;
print "1..21\n";
my $n = 20; my @i = (0..$n-1); my $failed;

my @rev = reverse @i;
my $I = new CIntArray($n,\@rev);

# convert to Int2
my $I2 = $I->ToInt2 (CIntArray->new($n,\@i), $n);
print "not " unless $I2;                  print "ok 1\n";
print ((ref ($I2) eq 'CInt2Array') ? "" : "not ", "ok 2\n");

$failed = 0;
for my $j (0 .. $n-1) {
    @i2 = $I2->get($j);
    ($failed = 1, last)
        unless ($#i2 == 1 and
                $i2[0] == $rev[$j] and
                $i2[1] == $i[$j]);
}
print $failed ? "not ": "" , "ok 3\n";

$I2->set(3,[1,2]);
print ((join(',', $I2->get(3)) eq '1,2') ? "": "not " , "ok 4\n");

$I2 = CInt2Array->new($n);
print "not " unless $I2;                print "ok 5\n";
print  ref $I2 eq 'CInt2Array' ? "" : "not ", "ok 6\n";

for my $j (0 .. $n-1) {
    $I2->set($j,[$n-$j,$j]);
    my @i2 = $I2->get($j);
    ($failed = 1, last)
        unless ($#i2 == 1 and
                $i2[0] == $n-$j and
                $i2[1] == $j);
}
print $failed ? "not ": "" , "ok 7\n";

# convert to Int3
my $I3 = $I->ToInt3 (CIntArray->new($n,\@i),
                     CIntArray->new($n,\@i),
                     $n);
print "not " unless $I3;                       print "ok 8\n";
print  ref($I3) eq 'CInt3Array' ? "" : "not ", "ok 9\n";

$failed = 0;
for my $j (0 .. $n-1) {
    my @i3 = $I3->get($j);
    unless ($#i3 == 2 and
            $i3[0] == $rev[$j] and
            $i3[1] == $i[$j]   and
            $i3[2] == $i[$j])
    { $failed=1; last; }
}
print $failed ? "not ": "" , "ok 10\n";

$I3->set(0,[1,2,3]);
print ((join(',', $I3->get(0)) eq '1,2,3') ? "": "not " , "ok 11\n");

$I3 = new CInt3Array($n);
print "not " unless $I3;                print "ok 12\n";
print  ref $I3 eq 'CInt3Array' ? "" : "not ", "ok 13\n";

for my $j (0 .. $n-1) {
    $I3->set($j,[$n-$j,0,$j]);
    my @i3 = $I3->get($j);
    ($failed = 1, last)
        unless ($#i3 == 2 and
                $i3[0] == $n-$j and
                $i3[1] == 0 and
                $i3[2] == $j);
}
print $failed ? "not " : "" , "ok 14\n";

# convert to Int4
my $I4 = $I->ToInt4 (CIntArray->new($n,\@i),
                     CIntArray->new($n,\@i),
                     CIntArray->new($n,\@i),
                     $n);
print "not " unless $I4;                       print "ok 15\n";
print  ref($I4) eq 'CInt4Array' ? "" : "not ", "ok 16\n";
$failed = 0;
for my $j (0 .. $n-1) {
    my @i4 = $I4->get($j);
    unless ($#i4 == 3 and
            $i4[0] == $rev[$j] and
            $i4[1] == $i[$j] and
            $i4[2] == $i[$j] and
            $i4[3] == $i[$j])
    { $failed=1; last; }
}
print $failed ? "not ": "" , "ok 17\n";

$I4->set(0,[1,2,3,4]);
print ((join (',', $I4->get(0)) eq '1,2,3,4') ? "" : "not ", "ok 18\n");

$I4 = new CInt4Array($n);
print "not " unless $I4;                print "ok 19\n";
print  ref $I4 eq 'CInt4Array' ? "" : "not ", "ok 20\n";


for my $j (0 .. $n-1) {
    $I4->set($j,[$n-$j,0,$j,1]);
    my @i4 = $I4->get($j);
    unless ($#i4 == 3 and
            $i4[0] == $n-$j and
            $i4[1] == 0 and
            $i4[2] == $j and
            $i4[3] == 1)
    { $failed=1; last; }
}
print $failed ? "not ": "" , "ok 21\n";