#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;

use Data::Dump qw/ dump /;

plan tests => 7;

my $package = 'MPD::Primer';

use_ok($package) || print "Bail out!\n";

my ( $primerObj, $covObj );

my %reqFile = (
  primer        => "sandbox/07-primers.txt",
  base          => "sandbox/ex.base.gz",
  covered       => "sandbox/07-covered.txt",
  expSeqCovered => "sandbox/07-PrimerSeqCovered.txt",
  bed           => "sandbox/07-test.bed",
  covSummary    => "sandbox/07-covered.txt",
);
my %foundFile = map { $_ => path( $reqFile{$_} )->is_file() } ( keys %reqFile );
my %msg =
  map { $_ => sprintf( "requires file: '%s'", $reqFile{$_} ) } ( keys %reqFile );

SKIP: {
  skip $msg{primer}, 1 unless $foundFile{primer};
  $primerObj = $package->new( $reqFile{primer} );
  ok( $primerObj, "create $package" );
}

SKIP: {
  skip $msg{primer}, 1 unless defined $primerObj;
  skip $msg{base},   1 unless $foundFile{base};

  $covObj = $primerObj->BaseFileCoverage( $reqFile{base} );
  ok( $covObj, "create coverage object" );
}

SKIP: {
  skip $msg{primer}, 1 unless defined $primerObj;
  skip $msg{bed},    1 unless $foundFile{bed};
  skip $msg{base},   1 unless defined $covObj;

  # Coverage, Entries_as_aref()
  my $expEntriesAref = $covObj->Entries_as_aref('covered');
  #SaveJsonData( $reqFile{expSeqCovered}, $expEntriesAref );
  my $obsEntriesAref = LoadJsonData( $reqFile{expSeqCovered} );
  is_deeply( $obsEntriesAref, $expEntriesAref, 'Entries_as_aref()' );
}

SKIP: {
  skip $msg{primer}, 1 unless defined $primerObj;
  skip $msg{bed},    1 unless $foundFile{bed};
  skip $msg{base},   1 unless defined $covObj;

  # PercentBasesCovered()
  my $percentCovered = sprintf( "%0.2f", $covObj->PercentBasesCovered() );
  is( $percentCovered, '0.93', "PercentBasesCovered" );

}

SKIP: {
  skip $msg{primer}, 1 unless defined $primerObj;
  skip $msg{bed},    1 unless $foundFile{bed};
  skip $msg{base},   1 unless defined $covObj;

  # Percent Covered
  my $bedObj = MPD::Bed->new( $reqFile{bed} );
  my $percentCovered = sprintf( "%0.2f", $covObj->PercentBasesCovered($bedObj) );
  is( $percentCovered, '0.96', "PercentBasesCovered" );
}

SKIP: {
  # Summarize Coverage
  skip $msg{primer}, 1 unless defined $primerObj;
  skip $msg{bed},    1 unless $foundFile{bed};
  skip $msg{base},   1 unless defined $covObj;

  my $tempfile = Path::Tiny->new( $reqFile{covSummary} );
  my $fh       = $tempfile->filehandle(">");
  my $str      = $covObj->Entries_as_str('covered');
  say {$fh} $str;
  close $fh;
  $tempfile = undef;
  my $digest = path( $reqFile{covSummary} )->digest;
  is_deeply(
    $digest,
    '1c42ae865f587909ecc7b1a7c47c9f9d820e833f524727f61864098c78e4304b',
    "Entries_as_BedFile( 'covered' )"
  );
  path( $reqFile{covSummary} )->remove;
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

