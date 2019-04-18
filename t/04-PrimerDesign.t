#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;

use Data::Dump qw/ dump /;

plan tests => 5;

my $package = 'MPD::PrimerDesign';

#Test 1
use_ok($package) || print "Bail out!\n";

my %reqFile = (
  #mpd perl required files
  bedFile    => 't/01-mpd.bed',
  MpdBinary  => 'mpd',
  MpdIdx     => 'hg38.d14.sdx',
  dbSnpIdx   => 'ds_flat.sdx',
  isPcrBinary => "$ENV{HOME}/local/bin/isPcr",
  TwoBitFile  => "$ENV{HOME}/data/hg38.2bit",
);

my %missingFiles = map { not( path( $reqFile{$_} )->is_file ) ? ($_ => $reqFile{$_}) : () } ( keys %reqFile );

diag('Number of missing files: ' . scalar keys %missingFiles);

my ( $m, $bedObj );

SKIP: {
  skip SayMissingFiles(\%missingFiles), 4 if ( %missingFiles and scalar keys %missingFiles > 0);
  $bedObj = MPD::Bed->new( $reqFile{bedFile} );
  my $m = $package->new(
    {
      Bed         => $bedObj,
      MpdBinary   => $reqFile{MpdBinary},
      MpdIdx      => $reqFile{MpdIdx},
      dbSnpIdx    => $reqFile{dbSnpIdx},
      isPcrBinary => $reqFile{isPcrBinary},
      TwoBitFile  => $reqFile{TwoBitFile},
      OutExt      => 't/04-test',
      timeout     => 7200,
    },
  );

  # Test 2
  ok( $m, "create $package" );

  my $testFile       = Path::Tiny->tempfile();
  my $PrimerObj      = $m->UniqPrimers();
  my $CoveredObj     = $PrimerObj->BedCoverage($bedObj);
  my $percentCovered = sprintf( "%0.2f", $CoveredObj->PercentCovered(0) );
  # Test 3
  is( $percentCovered, '0.64', 'PercentCovered() 1' );
  $percentCovered = sprintf( "%0.2f", $CoveredObj->PercentCovered(0.9) );
  # Test 4
  is( $percentCovered, '0.64', 'PercentCovered() 2' );

  my $m2 = $package->new(
      {
        Bed         => $bedObj,
        MpdBinary   => $reqFile{MpdBinary},
        MpdIdx      => $reqFile{MpdIdx},
        dbSnpIdx    => $reqFile{dbSnpIdx},
        isPcrBinary => $reqFile{isPcrBinary},
        TwoBitFile  => $reqFile{TwoBitFile},
        OutExt      => 't/04-test',
        timeout     => 1,
      },
    );

  my $timeoutBool = 1;
  eval{
    $m2->RunMpp( $testFile->stringify,$m2->timeout);
    #Should timeout here
    $timeoutBool = 0;
  };
  #Test 5
  ok($timeoutBool, 'RunMpp() timeout');
}

# SayMissingFiles takes an array reference and returns a list of files; however,
# if the list is blank it returns a list of all required files
sub SayMissingFiles {
  my $missingFilesRef = shift;
  my %missingFiles = %$missingFilesRef;

  my $msg = 'Required File(s) missing: ';

  foreach my $key (keys %missingFiles){
    $msg .= $missingFiles{$key} . " ";
  }
}

