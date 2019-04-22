#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;

use Data::Dump qw/ dump /;

plan tests => 7;

my $package = 'MPD::Bed';

#Test 1
use_ok($package) || print "Bail out!\n";

my $bed = $package->new("t/01-mpd.bed");

{
  #Test 2
  ok( $bed, "create $package from bed file" );
}

{
  my $bedRawObjAref = $bed->Entries;
  my $newBedObj     = MPD::Bed->new($bedRawObjAref);
  #Test 3
  ok( $newBedObj, 'create MPD::Bed with Aref of MPD::Bed::Raw' );
}

{
    #Count number of lines for now
    #This should test for an error in the future
    my $badBed = $package->new("t/01-mpd-bad.bed");
    my $badBedEntrys = $badBed->Entries;
    #Test 4
    is( 27, scalar @$badBedEntrys, "MPD::Bed bad bedfile" );
}

{
  my $file           = "t/bedEntries.json";
  my $expEntriesAref = $bed->Entries_as_aref;
  #SaveJsonData( $file, $expEntriesAref );
  my $obsEntriesAref = LoadJsonData($file);
  #Test 5
  is_deeply( $expEntriesAref, $obsEntriesAref, 'Entries_as_aref()' );
}

{
  my $file        = "t/bedSite.json";
  my $expSiteHref = $bed->CoveredSite;
  #SaveJsonData( $file, $expSiteHref );
  my $obsSiteHref = LoadJsonData($file);
  #Test 6
  is_deeply( $expSiteHref, $obsSiteHref, 'Site()' );
}

{
  my $file       = "t/bedChr.json";
  my $expChrHref = $bed->CoveredChr;
  #SaveJsonData( $file, $expChrHref );
  my $obsChrHref = LoadJsonData($file);
  #Test 7
  is_deeply( $expChrHref, $obsChrHref, 'Chr()' );
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
  my $jsonHref = decode_json($json_txt);
  return $jsonHref;
}

