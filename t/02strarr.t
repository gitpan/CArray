# CStringArray

# currently fails: 17:54 03.12.99
# 11 with DEBUGGING only

use CArray;
use strict;
local $^W = 1;
print "1..19\n";
my $n = 10; my @s = map { sprintf "%d", $_ } (0..$n-1);

my $S = new CStringArray($n);
print $S ? '' : 'not ' , "ok 1\n";
print ref($S) eq 'CStringArray' ? '' : 'not ', "ok 2\n";

undef $S;
print $S ? 'not ': '' , "ok 3\n"; # still alive

$S = CStringArray::new($n,\@s);
print $S ? '' : 'not ' , "ok 4\n";
unless ($S) {
  $S = new CStringArray($n);
  map { $S->set($_,$s[$_]) } (0..$n-1);
}

my $failed = 0;
for my $j (0 .. $n-1) {
    my $val = $S->get($j);
    ($failed = 1, last) unless (($val == $s[$j]) && (ref $val eq ref $s[$j]));
}
print $failed ? 'not ': '' , "ok 5\n";

# should we check range check errors?
eval { $S->set($n,0) };
print ((index ($@, "index out of range") > -1) ? '' : 'not ' , "ok 6\n");
eval { $S->set(-1,0) };
print ((index ($@, "index out of range") > -1) ? '' : 'not ' , "ok 7\n");

# acceptable type coercion
eval { $S->set(1,5.0) };
print (($S->get(1) eq '5') ? '' : 'not ' , "ok 8\n");
eval { $S->set(2,5.0001) };
print (($S->get(2) eq '5.0001') ? '' : 'not ' , "ok 9\n");
eval { $S->set(2,6) };
print (($S->get(2) eq '6') ? '' : 'not ' , "ok 10\n");

# other accepted type coercions (but should NOT be used)
# some refs
eval { $S->set(0,[0]) };
print $S->get(0) ? '' : 'not ' , "ok 11\n";      # rv->av as int
eval { $S->set(0,{0,0}) };
print $S->get(0) ? '' : 'not ' , "ok 12\n";      # rv->hv as int
eval { $S->set(0,(0)) };
print $S->get(0) == 0 ? '' : 'not ' , "ok 13\n"; # hmm.
{ no strict 'subs';
  open (FILE, '>-'); # STDOUT FileHandle
  eval { $S->set(0,\FILE) };
  print $@ ? 'not ' : '' , "ok 14\n";
  close FILE;
  opendir (DIR, '.'); # DirHandle
  eval { $S->set(0,\DIR) };
  print $@ ? 'not ' : '' , "ok 15\n";
  closedir DIR;
}

# correctly rejected types: hmm, this cannot be caught by eval...
#eval { $S->set(0,<*>) };
# this should be catched by CArray->set, not by Ptr->set
#print ((index ($@, "Argument") > -1) ? '' : 'not ' , "ok 17\n");

map { $S->set($_,$s[$_]) } (0..$n-1);
# print join ", ", map { $S->get($_) } (0..19)

# indirect sort
my @sorted = $S->isort($n);  # must be (0..$n-1)
$failed = 0;
for my $j (0 .. $n-1) {
    ($failed = 1, last) unless $sorted[$j] == $j; }
print $failed ? 'not ': '' , "ok 16\n";

# grouping
# this should search the ISA, inherited from CArray::CPtr
my @s2 = $S->get_grouped_by(2,1);
$failed = ($s2[0] != $s[2] or
           $s2[1] != $s[3] or
           $#s2 != 1);
print $failed  ? 'not ' : '' , "ok 17\n";

$S->nreverse();
my $s = join ',', map {$S->get($_)} (0..$n-1);
print (($s eq join(',', reverse @s)) ? '': 'not ' , "ok 18\n");

undef $S;
print $S ? 'not ': '' , "ok 19\n"; # still alive