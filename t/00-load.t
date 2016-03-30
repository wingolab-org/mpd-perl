#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;

plan tests => 12;

BEGIN {
  use_ok('MPD::Bed::Covered') || print "Bail out!\n";
  use_ok('MPD::Bed::Raw')     || print "Bail out!\n";
  use_ok('MPD::Bed')          || print "Bail out!\n";
  use_ok('MPD::Covered')      || print "Bail out!\n";
  use_ok('MPD::isPcr')        || print "Bail out!\n";
  use_ok('MPD::PrimerDesign') || print "Bail out!\n";
  use_ok('MPD::Primer::Raw')  || print "Bail out!\n";
  use_ok('MPD::Primer')       || print "Bail out!\n";
  use_ok('MPD::Psl::Raw')     || print "Bail out!\n";
  use_ok('MPD::Psl')          || print "Bail out!\n";
  use_ok('MPD::Seq')          || print "Bail out!\n";
  use_ok('MPD')               || print "Bail out!\n";
}
diag("Testing Seq, Perl $], $^X");
