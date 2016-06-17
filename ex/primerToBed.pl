#!/usr/bin/env perl
# Name:           primerToBed.pl
# Date Created:   Fri May 20 15:33:41 2016
# Date Modified:  Fri May 20 15:33:41 2016
# By:             TS Wingo
#
# Description:

use 5.10.0;
use warnings;
use strict;

use Getopt::Long;
use Path::Tiny;
use Data::Dump qw/ dump /;

use MPD::Primer;

# variables
my ( $verbose, $act, $file_name, $out_ext );

# get options
die "Usage: $0 [-v] [-a] -f <file_name> -o <out_ext>\n"
  unless GetOptions(
  'v|verbose' => \$verbose,
  'a|act'     => \$act,
  'f|file=s'  => \$file_name,
  'o|out=s'   => \$out_ext,
  ) and $file_name;
$verbose++ unless $act;

my $primer = MPD::Primer->new($file_name);
$primer->WriteBedFile("$out_ext.bed");

