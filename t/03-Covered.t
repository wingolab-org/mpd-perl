#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;

use Data::Dump qw/ dump /;

use MPD::Bed;
use MPD::Primer;

plan tests => 5;

my $package = 'MPD::Covered';

use_ok($package) || print "Bail out!\n";

my $bedFile   = 't/01-mpd.bed';
my $bedObj    = MPD::Bed->new($bedFile);
my $PrimerObj = MPD::Primer->new("t/mpp.primer.txt");

{
  # TODO: covered test is redundant with the test in Primer.t
  my $CoveredObj = $PrimerObj->BedCoverage($bedObj);
  #SaveJsonData( "t/03-covered.txt", $CoveredObj->Entries_as_aref() );
  is_deeply(
    $CoveredObj->Entries_as_aref(),
    LoadJsonData("t/03-covered.txt"),
    'Entries_as_aref()'
  );
  my $percentCovered = sprintf( "%0.2f", $CoveredObj->PercentCovered(0) );
  is( '0.61', $percentCovered, 'PercentCovered( 0 )' );
  $percentCovered = sprintf( "%0.2f", $CoveredObj->PercentCovered(0.9) );
  is( '0.61', $percentCovered, 'PercentCovered( 0.61 )' );
}

{
  my $UncoveredObj = $PrimerObj->BedUncovered($bedObj);
  #SaveJsonData( "t/03-uncovered.bed", $UncoveredObj->Entries_as_aref()  );
  is_deeply(
    $UncoveredObj->Entries_as_aref(),
    LoadJsonData("t/03-uncovered.bed"),
    'BedUncovered()'
  );
}

sub SortMatches {
  my $href = shift;
  my %hash;

  for my $pep ( keys %$href ) {
    my $matchesAref = $href->{$pep};
    my @sMatches = sort { $a cmp $b } @$matchesAref;
    $hash{$pep} = \@sMatches;
  }
  return \%hash;
}

sub SaveJsonData {
  my ( $file, $data ) = @_;
  my $fh = path($file)->filehandle(">");
  print {$fh} encode_json($data);
  close $fh;
}

sub LoadJsonData {
  my $file     = shift;
  my $json_txt = path($file)->slurp;
  return decode_json($json_txt);
}

