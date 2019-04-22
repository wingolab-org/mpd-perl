#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;

use Data::Dump qw/ dump /;

plan tests => 16;

my $package     = 'MPD::Primer';
my $adapter_fwd = "ACACTGACGACATGGTTCTACA";
my $adapter_rev = "TACGGTAGCAGAGACTTGGTCT";

use_ok($package) || print "Bail out!\n";

my $p = $package->new("t/mpp.primer.txt");
ok( $p, "create $package" );

my $testFile = Path::Tiny->tempfile();
$p->WriteIsPcrFile( $testFile->stringify );

is( $testFile->digest(),
  'ea2d090e75a370439813fe68cbe310d514b0e5625f26c6fd53bd6a8138ccf0d5',
  'WriteIsPcrFile()' );

{
  my $bedFile    = 't/01-mpd.bed';
  my $testFile   = 't/PrimerCoverage.json';
  my $obsCovObj  = $p->BedFileCoverage($bedFile);
  my $obsCovAref = $obsCovObj->Entries_as_aref();
  #SaveJsonData( $testFile, $obsCovAref );
  my $expCovAref = LoadJsonData($testFile);
  is_deeply( $obsCovAref, $expCovAref, 'BedFileCoverage()' );
}

{
  my $testFile       = 't/PrimersAref.json';
  my $obsPrimersAref = $p->as_aref;
  #SaveJsonData($testFile, $obsPrimersAref);
  my $expPrimersAref = LoadJsonData($testFile);
  is_deeply( $obsPrimersAref, $expPrimersAref, 'as_aref()' );
}

{
  # write primer file
  my $testFile = 't/01-WritePrimerFile.txt';
  my $obsFile  = 't/tmp.txt';
  $p->WritePrimerFile($obsFile);
  #$p->WritePrimerFile( $testFile );
  my $obsTxt = path($obsFile)->slurp;
  my $expTxt = path($testFile)->slurp;
  is( $obsTxt, $expTxt, 'WritePrimerFile()' );
  path($obsFile)->remove;
}

{
  # write isPcr file
  my $testFile = 't/isPcr.txt';
  my $obsFile  = 't/tmp.txt';
  $p->WriteIsPcrFile($obsFile);
  #$p->WriteIsPcrFile( $testFile );
  my $obsTxt = path($obsFile)->slurp;
  my $expTxt = path($testFile)->slurp;
  is( $obsTxt, $expTxt, 'WriteIsPcrFile()' );
  path($obsFile)->remove;
}

{
  # write covered file
  my $bedObj          = MPD::Bed->new('t/markers.txt.bed');
  my $coveredTestFile = 't/covered.txt';
  my $obsFile         = 't/cov.tmp';
  $p->WriteCoveredFile( $obsFile, $bedObj );
  #$p->WriteCoveredFile( $coveredTestFile, $bedObj );
  my $obsTxt = path($obsFile)->slurp;
  my $expTxt = path($coveredTestFile)->slurp;
  is( $obsTxt, $expTxt, 'WriteIsPcrFile()' );
  path($obsFile)->remove;

  my $uncoveredTestFile = 't/uncovered.txt';
  $p->WriteUncoveredFile( $obsFile, $bedObj );
  #$p->WriteUncoveredFile( $uncoveredTestFile, $bedObj );
  $obsTxt = path($obsFile)->slurp;
  $expTxt = path($uncoveredTestFile)->slurp;
  is( $obsTxt, $expTxt, 'WriteUncoveredFile()' );
  path($obsFile)->remove;
}

{
  my $testFile = 't/PrimersListAref.json';
  my $obsPrimersListAref =
    $p->PrimerList( [ 'Name', 'Forward_primer', 'Reverse_primer' ] );
  #SaveJsonData($testFile, $obsPrimersListAref);
  my $expPrimersListAref = LoadJsonData($testFile);
  is_deeply( $obsPrimersListAref, $expPrimersListAref, 'PrimerList()' );
}

{
  my $testFile     = 't/filteredPrimerListAref.json';
  my $filteredPObj = $p->FilterPoolBelowThreshold(5);
  #SaveJsonData($testFile, $filteredPObj->as_aref());
  is_deeply( $filteredPObj->as_aref(),
    LoadJsonData($testFile), 'FilterPoolBelowThreshold()' );
}

{
  my $testFile = 't/forOrder.json';
  #SaveJsonData( $testFile, $p->OrderAsHref() );
  is_deeply( $p->OrderAsHref(), LoadJsonData($testFile),'OrderAsHref() - no options' );
}

{
  my $testFile = 't/forOrderOpt1.json';
  my $optHref  = {
    ProjectName => 'test',
    FwdAdapter  => 'ACACTGACGACATGGTTCTACA',
    RevAdapter  => 'TACGGTAGCAGAGACTTGGTCT',
  };
  #SaveJsonData( $testFile, $p->OrderAsHref($optHref) );
  is_deeply( $p->OrderAsHref($optHref),
    LoadJsonData($testFile), 'OrderAsHref() - add adapters and prj name' );
}

{
  # Update Names of primers
  my $testFile = 't/forOrderOpt2.json';
  my $bedFile  = 't/markers.txt.bed';
  my $bedObj   = MPD::Bed->new($bedFile);
  my $optHref  = {
    Bed         => $bedObj,
    ProjectName => 'test',
    FwdAdapter  => 'ACACTGACGACATGGTTCTACA',
    RevAdapter  => 'TACGGTAGCAGAGACTTGGTCT',
  };
  #say dump( $p->OrderAsHref($optHref) );
  #SaveJsonData( $testFile, $p->OrderAsHref($optHref) );
  is_deeply( $p->OrderAsHref($optHref),
    LoadJsonData($testFile), 'OrderAsHref() - add adapters and prj name' );
}

{
  local $TODO = "Write Excel for Ordering";
  my $testFile = 't/forOrder.xlsx';
  my $bedFile  = 't/markers.txt.bed';
  my $bedObj   = MPD::Bed->new($bedFile);
  my $optHref  = {
    Bed         => $bedObj,
    ProjectName => 'test',
    time        => 'Now',
    FwdAdapter  => 'ACACTGACGACATGGTTCTACA',
    RevAdapter  => 'TACGGTAGCAGAGACTTGGTCT',
  };
  $p->WriteOrderFile( $testFile, $optHref );
  ok( path($testFile)->is_file(), 'WriteExcel' );
  path($testFile)->remove;
}

{
  local $TODO = "Randomize test should fail";
  my $testFile = 't/forOrderOpt3.json';
  my $optHref = { randomize => 1 };
  #SaveJsonData( $testFile, $p->OrderAsHref($optHref) );
  is_deeply( $p->OrderAsHref($optHref),
    LoadJsonData($testFile), 'OrderAsHref() - randomize' );
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

