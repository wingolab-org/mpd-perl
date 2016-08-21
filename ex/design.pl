#!/usr/bin/env perl
# Name:           ex/design.pl
# Date Created:   Wed Mar  9 15:36:28 2016
# Date Modified:  Wed Mar  9 15:36:28 2016
# By:             TS Wingo
#
# Description:

use lib '/Users/twingo/software/mpd-perl/lib/';
use 5.10.0;
use warnings;
use strict;
use Getopt::Long;
use Path::Tiny;

use lib '../lib';

use MPD;

# variables
my ( $verbose, $act, $dir, $prn, $poolMin, $bed_file, $config_file, $out_ext );

# get options
die
  "Usage: $0 [-v] [-a] -b <bed file> -c <config file> -d <output Dir> -o <out_ext>\n"
  unless GetOptions(
  'v|verbose'  => \$verbose,
  'a|act'      => \$act,
  'b|bed=s'    => \$bed_file,
  'c|config=s' => \$config_file,
  'o|out=s'    => \$out_ext,
  'd|dir=s'    => \$dir,
  'min_pool=n' => \$poolMin,
  )
  and $bed_file
  and $config_file
  and $out_ext;
$verbose++ unless $act;

$poolMin = 1 unless defined $poolMin;

$dir = path($dir);

if ( !$dir->is_dir ) { $dir->mkpath(); }

my $m = MPD->new_with_config(
  {
    configfile  => $config_file,
    BedFile     => $bed_file,
    OutExt      => $out_ext,
    OutDir      => $dir,
    InitTmMin   => 58,
    InitTmMax   => 61,
    PoolMin     => $poolMin,
    Debug       => $verbose,
    IterMax     => 2,
    RunIsPcr    => 0,
    Act         => $act,
    ProjectName => $out_ext,
    FwdAdapter  => 'ACACTGACGACATGGTTCTACA',
    RevAdapter  => 'TACGGTAGCAGAGACTTGGTCT',
    Offset      => 0,
    Randomize   => 1,
  }
);
$m->RunAll();
