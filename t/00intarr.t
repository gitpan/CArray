# CIntArray's with function and OO method syntax,

# currently fails: 06:28 05.12.99
# none

use CArray;
use strict;
local $^W = 1;
print "1..25\n";
my $n = 200; my @i = (0..$n-1);

my $I = new CIntArray($n,\@i);
print $I ? "" : "not " , "ok 1\n";
print ref($I) eq 'CIntArray' ? "" : "not ", "ok 2\n";

print "not "
  unless ($I->itemsize > 0 and $I->itemsize == $CIntArray::itemsize);
print "ok 3\n";

my $failed = 0;
for my $j (0 .. $n-1) {
    my $val = $I->get($j);
    ($failed = 1, last) unless (($val == $i[$j]) && (ref $val eq ref $i[$j]));
}
print $failed ? "not ": "" , "ok 4\n";

undef $I;
print $I ? "not ": "" , "ok 5\n"; # still alive

$I = CIntArray->new($n);
print $I ? "" : "not " , "ok 6\n";

map { $I->set($_, $i[$_]) } (0.. $n-1);
$failed = 0;
for my $j (0 .. $n-1) {
    my $val = $I->get($j);
    ($failed = 1, last) unless (($val == $i[$j]) && (ref $val eq ref $i[$j]));
}
print $failed ? "not ": "" , "ok 7\n";

# should we check range check errors?
eval { $I->set($n,0) };
print ((index ($@, "index out of range") > -1) ? "" : "not " , "ok 8\n");
eval { $I->set(-1,0) };
print ((index ($@, "index out of range") > -1) ? "" : "not " , "ok 9\n");

# acceptable type coercion
eval { $I->set(0,5.0) };
print $I->get(0) == 5 ? "" : "not " , "ok 10\n";
eval { $I->set(0,"6") };
print $I->get(0) == 6 ? "" : "not " , "ok 11\n";

# other accepted type coercions (but should NOT be used)
# some refs
eval { $I->set(0,[0]) };
print $I->get(0) ? "" : "not " , "ok 12\n";      # rv->av as int
eval { $I->set(0,{0,0}) };
print $I->get(0) ? "" : "not " , "ok 13\n";      # rv->hv as int
eval { $I->set(0,(0)) };
print $I->get(0) == 0 ? "" : "not " , "ok 14\n"; # hmm.
{ no strict 'subs';
  open (FILE, '>-'); # STDOUT FileHandle
  eval { $I->set(0,\FILE) };
  print $@ ? "not " : "" , "ok 15\n";
  close FILE;
  opendir (DIR, '.'); # DirHandle
  eval { $I->set(0,\DIR) };
  print $@ ? "not " : "" , "ok 16\n";
  closedir DIR;
}

# correctly rejected types: hmm, this cannot be caught by eval...
#eval { $I->set(0,<*>) };
# this should be catched by CArray->set, not by Ptr->set
#print ((index ($@, "Argument") > -1) ? "" : "not " , "ok 17\n");

# fastest way to fill it, besides passing a reference at new?
my $j = 0;
map { $I->set($j++,$_) } @i;
#print join ',', map { $I->get($_) } (0..$n-1);
my $s = join ',', map { $I->get($_) } (0..$n-1);
print $s eq (join ',', @i) ? "": "not " , "ok 17\n";

# indirect sort
my @sorted = $I->isort($n);  # must be (0..$n-1)
$failed = 0;
for my $j (0 .. $n-1) {
    ($failed = 1, last) unless $sorted[$j] == $j; }
print $failed ? "not ": "" , "ok 18\n";

# grouping
my @i2 = $I->get_grouped_by(2,1);
$failed = ($i2[0] != $i[2] or
           $i2[1] != $i[3] or
           $#i2 != 1);
print $failed  ? "not " : "" , "ok 19\n";

print join(',', $I->slice(1,3)) eq '1,2,3' ? "" : "not " , "ok 20\n";
print join(',', $I->slice(2,4)) eq '2,3,4,5' ? "" : "not " , "ok 21\n";
print join(',', $I->slice(1,3,3)) eq '1,4,7' ? "" : "not " , "ok 22\n";
print join(',', $I->slice(1,0)) eq '' ? "" : "not " , "ok 23\n";

# since 0.08, still fails at index 0
$I->nreverse();
$s = join ',', map {$I->get($_)} (0..$n-1);
print (($s eq join ',', reverse @i) ? "": "not " , "ok 24\n");

undef $I;
print $I ? "not ": "" , "ok 25\n"; # still alive