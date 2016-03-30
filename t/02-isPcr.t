#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;

use Data::Dump qw/ dump /;

plan tests => 3;

my $package = 'MPD::isPcr';
use_ok( $package, "use $package" ) || print "Bail out!\n";

my $tempFile = Path::Tiny->new("t/02-tmp.dat");
my $i        = $package->new(
  {
    PrimerFile       => 't/mpp.primer.txt',
    PrimerFileFormat => 'mpp',
    isPcrBinary      => '/Users/twingo/local/bin/isPcr',
    TwoBitFile       => '/Users/twingo/data/hg38.2bit',
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

