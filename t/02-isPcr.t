#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;

use Data::Dump qw/ dump /;

plan tests => 3;

my %reqFile = (
  bedFile     => 't/01-mpd.bed',
  MpdBinary   => './mpd',
  MpdIdx      => 'hg38.d14.sdx',
  dbSnpIdx    => 'ds_flat.sdx',
  isPcrBinary => "$ENV{HOME}/local/bin/isPcr",
  TwoBitFile  => "$ENV{HOME}/data/hg38.2bit",
);
my %foundFile = map { $_ => path( $reqFile{$_} )->is_file() } ( keys %reqFile );

my $package = 'MPD::isPcr';
use_ok( $package, "use $package" ) || print "Bail out!\n";

SKIP: {
  my @neededFiles  = qw/ isPcrBinary TwoBitFile /;
  my @missingFiles = MissingFiles( \@neededFiles );
  skip SayMissingFiles( \@neededFiles ), 2 unless scalar @missingFiles == 0;

  my $tempFile = Path::Tiny->new("t/02-tmp.dat");
  my $i        = $package->new(
    {
      PrimerFile       => 't/mpp.primer.txt',
      PrimerFileFormat => 'mpp',
      isPcrBinary      => $reqFile{isPcrBinary},
      TwoBitFile       => $reqFile{TwoBitFile},
      OutFile          => $tempFile,
    }
  );
  ok( $i, "$package creation" );

  my $ok = $i->Run;
  if ($ok) {
    is( $i->OutFile->digest,
      'b3b2ff776701c315fc90377923829c79bdee6fda4c9b8d41b900767d74465e29', "Run()" );
    #my @lines = $i->OutFile->lines( { chomp => 1 } );
    #say dump( \@lines );
    $i->OutFile->remove();
  }
  else {
    die "Error: Run()";
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

