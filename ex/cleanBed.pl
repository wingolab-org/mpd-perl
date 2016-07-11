#!/usr/bin/env perl
# Name:           cleanBed.pl
# Date Created:   Fri Jun 17 09:33:06 2016
# Date Modified:  Fri Jun 17 09:33:06 2016
# By:             TS Wingo
#
# Description:

use 5.10.0;
use warnings;
use strict;

use Getopt::Long;
use Path::Tiny;
use MPD::Bed;

# variables
my ( $file_name, $out_ext, $useLetterChr );

# get options
die "Usage: $0 -f <file_name> -o <out_ext> [--l|etter]\n"
  unless GetOptions(
  'f|file=s' => \$file_name,
  'o|out=s'  => \$out_ext,
  'l|letter' => \$useLetterChr,
  )
  and $file_name
  and $out_ext;

my $b     = MPD::Bed->new($file_name);
my $outFh = path("$out_ext.bed")->filehandle(">");

if ($useLetterChr) {
  say {$outFh} $b->Entries_as_BedFileLetter();
}
else {
  say {$outFh} $b->Entries_as_BedFile();
}

