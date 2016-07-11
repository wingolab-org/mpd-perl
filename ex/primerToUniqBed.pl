#!/usr/bin/env perl
# Name:           primerToUniqBed.pl
# Date Created:   Mon May 23 10:52:00 2016
# Date Modified:  Mon May 23 10:52:00 2016
# By:             TS Wingo
#
# Description:

use lib '/home/twingo/software/mpd-perl/lib';
use 5.10.0;
use warnings;
use strict;

use Getopt::Long;
use Path::Tiny;
use Data::Dump qw/ dump /;
use MPD::Primer;
use MPD::isPcr;
use MPD::Psl;

# variables
my ( $TwoBitFile, $isPcrBin, $file_name, $out_ext );

# get options
die
  "Usage: $0 -f <primerFile> -o <outExt> --isPcr <path/to/isPcr> --twoBit <path/to/2bit>\n"
  unless GetOptions(
  'f|file=s' => \$file_name,
  'isPcr=s'  => \$isPcrBin,
  'twoBit=s' => \$TwoBitFile,
  'o|out=s'  => \$out_ext,
  )
  and $isPcrBin
  and $TwoBitFile
  and $file_name;

my $primer = UniqPrimers($file_name);
if ( !defined $primer ) {
  say "All duplicate primers.";
  exit(1);
}
$primer->WriteBedFileLetter("$out_ext.bed");

# UniqPrimers calls isPcr to filter away primers that amplify >1 thing in the
# genome based on isPcr's rules and any duplicates from the MPD program
# stolen from MPD::PrimerDesign
sub UniqPrimers {
  my $primerFile = shift;

  my $primerPath = path($primerFile);
  my $tempFile   = Path::Tiny->tempfile();
  my $isPcr      = MPD::isPcr->new(
    {
      PrimerFile       => $primerPath->stringify,
      PrimerFileFormat => 'mpp',
      isPcrBinary      => $isPcrBin,
      TwoBitFile       => $TwoBitFile,
      OutFile          => $tempFile,
    }
  );

  if ( !$isPcr->Run() ) {
    return;
  }

  my %badPrimers;

  # Remove Degenerate primers
  my $psl     = MPD::Psl->new( $tempFile->stringify() );
  my $dupAref = $psl->DegenerateMatches();
  $badPrimers{$_}++ for @$dupAref;

  # remove duplicates sometimes introduced by the design process
  my $primerObj = MPD::Primer->new( $primerPath->stringify() );
  $dupAref = $primerObj->DuplicatePrimers();
  $badPrimers{$_}++ for @$dupAref;

  if ( !%badPrimers ) {
    return $primerObj;
  }
  return $primerObj->RemovePrimers( [ sort keys %badPrimers ] );
}
