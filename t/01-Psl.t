#perl -T

use 5.10.0;
use strict;
use warnings;
use JSON;
use Test::More;
use Path::Tiny;

use Data::Dump qw/ dump /;

plan tests => 3;

my $package = 'MPD::Psl';

use_ok($package) || print "Bail out!\n";

my $p = $package->new("t/isPcr.psl");
ok( $p, "$package construction" );

my $obsDegenAref = $p->DegenerateMatches();
my $expDegenAref = [
  "pool_10_00", "pool_10_00", "pool_10_00", "pool_24_02",
  "pool_38_04", "pool_38_04", "pool_4_00",  "pool_4_00",
];
is_deeply( [ sort @$obsDegenAref ], [ sort @$expDegenAref ], 'DegenerateMatches()' );

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

