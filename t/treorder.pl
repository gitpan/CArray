#!/usr/bin/perl -w

=head1 NAME

treorder - Reorders "ok " numbers in Test::Harness scripts

=head1 SYNOPSIS

  treorder t\*.t

=head1 DESCRIPTION

Automatically reorders C<"ok (\d+)\n"> in Test::Harness scripts,
e.g. after inserting or deleting tests.

Prints some noise if changes are made, otherwise stays quiet.
Changes are destructive.

Fails on '' style strings.

=head1 COPYRIGHT

Copyright (c) 1999 by Reini Urban.
This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut

sub reorder {
  my $i = 1;
  my $changed;
  open IN, "<$file";
  open OUT, ">$file.tmp";
  while (<IN>) {
    # not commented
    if (/["']ok (\d+)\\n["']/ and !/#.*ok/) {
      if ($i != $1) {
        s/["']ok (\d+)\\n["']/\"ok $i\\n\"/;
        print STDERR "$file: ok $1 => ok $i\n";
        $changed = 1;
      }
      $i++;
    }
    print OUT;
  }
  $i--;
  print STDERR "$file: 1..$i tests\n" if $changed;
  close IN;
  close OUT;
  if ($changed) {
    my $already;
    rename $file, "$file.BAK";
    open IN, "<$file.tmp";
    open OUT, ">$file";
    while (<IN>) {
      $already or $already = s/["']1..(\d+)\\n["']/\"1..$i\\n\"/;
      print OUT;
    }
    close IN;
    close OUT;
  }
  unlink "$file.tmp";
}

for $file (@ARGV) { reorder($file); }
1;