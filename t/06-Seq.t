#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;

use Data::Dump qw/ dump /;

plan tests => 7;

my $package = 'MPD::Seq';

use_ok($package) || print "Bail out!\n";

my %reqFile = ( BaseFile => "sandbox/test.base.gz", );
my %foundFile = map { $_ => path( $reqFile{$_} )->is_file() } ( keys %reqFile );

SKIP: {
  # build object
  my @neededFiles  = qw/ BaseFile /;
  my @missingFiles = MissingFiles( \@neededFiles );
  skip SayMissingFiles( \@neededFiles ), 6 unless scalar @missingFiles == 0;
  my $seq = $package->new( $reqFile{BaseFile} );
  ok( $seq, "create $package from base file" );

  # covered
  my $file           = "t/06-covered.json";
  my $expEntriesAref = $seq->Entries_as_aref('covered');
  #SaveJsonData( $file, $expEntriesAref );
  my $obsEntriesAref = LoadJsonData($file);
  is_deeply( $expEntriesAref, $obsEntriesAref, 'Entries_as_aref()' );

  # uncovered
  $file           = "t/06-uncovered.json";
  $expEntriesAref = $seq->Entries_as_aref('uncovered');
  #SaveJsonData( $file, $expEntriesAref );
  $obsEntriesAref = LoadJsonData($file);
  is_deeply( $expEntriesAref, $obsEntriesAref, 'Entries_as_aref()' );

  # covered
  $file = "t/06-covered.bed";
  my $tempfile = Path::Tiny->new($file);
  my $fh       = $tempfile->filehandle(">");
  my $str      = $seq->Entries_as_BedFile('covered');
  say {$fh} $str;
  close $fh;
  my $digest = path($file)->digest;
  is_deeply(
    $digest,
    'a1c02e4b88aaae0db2fcafcfbaf5e5a823d53653ff3058aedd1fd288bc4e779f',
    "Entries_as_BedFile( 'covered' )"
  );
  path($file)->remove;

  # uncovered
  $file     = "t/06-uncovered.bed";
  $tempfile = Path::Tiny->new($file);
  $fh       = $tempfile->filehandle(">");
  $str      = $seq->Entries_as_BedFile('uncovered');
  say {$fh} $str;
  close $fh;
  $digest = path($file)->digest;
  is_deeply(
    $digest,
    '214fac7ea5a91e1f4e835cbd41240d3828bbf8f2139720cd2dc75370e198596e',
    "Entries_as_BedFile( 'uncovered' )"
  );
  path($file)->remove;

  # alt build
  $seq = $package->new(
    {
      BaseFile          => "sandbox/test.base.gz",
      CallProb          => 1,
      CoverageThreshold => 1,
    }
  );
  ok( $seq, "create $package from base file" );
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
  return $jsonHref;
}

