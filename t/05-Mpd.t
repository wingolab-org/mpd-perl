#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;
use YAML qw/ LoadFile/;

use Data::Dump qw/ dump /;

plan tests => 4;

my $package = 'MPD';

use_ok($package) || print "Bail out!\n";

my %reqFile = (
  BedFile     => 't/01-mpd.bed',
  MpdBinary   => '/Users/twingo/software/mpd-perl/mpd',
  MpdIdx      => 'hg38.d14.sdx',
  dbSnpIdx    => 'ds_flat.sdx',
  isPcrBinary => 'isPcr',
  TwoBitFile  => 'hg38.2bit',
  configfile  => 'ex/config.yaml'
);
my %foundFile = map { $_ => path( $reqFile{$_} )->is_file() } ( keys %reqFile );

SKIP: {
  my @neededFiles  = qw/ BedFile MpdBinary MpdIdx dbSnpIdx isPcrBinary TwoBitFile /;
  my @missingFiles = MissingFiles( \@neededFiles );
  skip SayMissingFiles( \@neededFiles ), 1 unless scalar @missingFiles == 0;

  my $m = $package->new(
    {
      BedFile     => 't/01-mpd.bed',
      MpdBinary   => '/Users/twingo/software/mpd-perl/mpd',
      MpdIdx      => 'hg38.d14.sdx',
      dbSnpIdx    => 'ds_flat.sdx',
      isPcrBinary => 'isPcr',
      TwoBitFile  => 'hg38.2bit',
      OutExt      => '05-test',
      OutDir      => 't'
    }
  );
  ok( $m, "create $package with new()" );
}

SKIP: {
  my @neededFiles  = qw/ configfile /;
  my @missingFiles = MissingFiles( \@neededFiles );
  skip SayMissingFiles( \@neededFiles ), 2 unless scalar @missingFiles == 0;

  my $m = $package->new_with_config(
    { configfile => 'ex/config.yaml', OutDir => 't', OutExt => '05-test', } );
  ok( $m, "create $package with new_with_config()" );

  $m = $package->new_with_config(
    { configfile => 'ex/config.yaml', GcMin => 0.5, OutDir => 't', OutExt => '05-test' }
  );
  ok( $m, "create $package with new_with_config()" );
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
  return decode_json($json_txt);
}

