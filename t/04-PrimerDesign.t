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

use_ok($package) || print "Bail out!\n";

my %reqFile = (
  bedFile     => 't/01-mpd.bed',
  MpdBinary   => './mpd',
  MpdIdx      => 'hg38.d14.sdx',
  dbSnpIdx    => 'ds_flat.sdx',
  isPcrBinary => '/Users/twingo/local/bin/isPcr',
  TwoBitFile  => '/Users/twingo/data/hg38.2bit',
);
my %foundFile = map { $_ => path( $reqFile{$_} )->is_file() } ( keys %reqFile );

my ( $m, $bedObj );

SKIP: {
  my @neededFiles  = qw/ bedFile MpdBinary MpdIdx dbSnpIdx isPcrBinary TwoBitFile /;
  my @missingFiles = MissingFiles( \@neededFiles );
  skip SayMissingFiles( \@neededFiles ), 4 unless scalar @missingFiles == 0;
  $bedObj = MPD::Bed->new( $reqFile{bedFile} ),
    my $m = $package->new(
    {
      Bed         => $bedObj,
      MpdBinary   => $reqFile{MpdBinary},
      MpdIdx      => $reqFile{MpdIdx},
      dbSnpIdx    => $reqFile{dbSnpIdx},
      isPcrBinary => $reqFile{isPcrBinary},
      TwoBitFile  => $reqFile{TwoBitFile},
      OutExt      => 't/04-test',
    },
    );
  ok( $m, "create $package" );

  my $testFile       = Path::Tiny->tempfile();
  my $PrimerObj      = $m->UniqPrimers();
  my $CoveredObj     = $PrimerObj->BedCoverage($bedObj);
  my $percentCovered = sprintf( "%0.2f", $CoveredObj->PercentCovered(0) );
  is( $percentCovered, '0.64', 'PercentCovered()' );
  $percentCovered = sprintf( "%0.2f", $CoveredObj->PercentCovered(0.9) );
  is( $percentCovered, '0.64', 'PercentCovered()' );

  # test running mpd
  $testFile = Path::Tiny->tempfile();
  $m->RunMpp( $testFile->stringify );
  my @lines = $testFile->lines( { chomp => 1 } );
  my $fh = path("test")->filehandle(">");
  say {$fh} dump( \@lines );
  is( $testFile->digest(),
    'cec9054f8831ba398a98e206734aab6e3ed3377becb8958c86b8413ad4a07a1e', 'RunMpp()' );
}

# SayMissingFiles takes an array reference and returns a list of files; however,
# if the list is blank it returns a list of all required files
sub SayMissingFiles {
  my $fileListAref = shift;

  my @array;

  if ( !defined $fileListAref ) {
    for my $f ( sort keys %reqFile ) {
      push @array, $reqFile{$f};
    }
    my $missingCount = scalar @array;
    my $msg = "Required File(s) missing: '" . join( "' ,'", @array ) . "'";
  }
  elsif ( ref $fileListAref eq "ARRAY" ) {
    my @files = MissingFiles($fileListAref);
    my $msg = "Required File(s) missing: '" . join( "' ,'", @files ) . "'";
  }
  else {
    my $reqFile =
      "SayMissingFiles() expects either no argument or an array ref of files to list";
    die $reqFile;
  }
}

sub MissingFiles {
  my $fileListAref = shift;

  my @array;

  for my $f (@$fileListAref) {
    if ( !defined $foundFile{$f} ) {
      push @array, $reqFile{$f};
      # if we are asked about the config file then load the config file
      # and check that we have those files
    }
    elsif ( $f eq "configfile" ) {
      my $href = LoadFile( $reqFile{$f} );
      for my $file ( sort keys %reqFile ) {
        if ( !defined $href->{$file} ) {
          push @array, $reqFile{$file};
        }
        elsif ( !path( $href->{$file} )->is_file() ) {
          push @array, $reqFile{$file};
        }
      }
    }
  }
  if (wantarray) {
    return @array;
  }
  elsif ( defined wantarray ) {
    return \@array;
  }
  else {
    die "MissingFiles() should be called in list or scalar context";
  }
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
  if ( !%$jsonHref ) {
    say "Bail out - no data for $file";
    exit(1);
  }
  else {
    return $jsonHref;
  }
}

