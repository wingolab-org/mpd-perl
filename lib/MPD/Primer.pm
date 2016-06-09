package MPD::Primer;

# ABSTRACT: This package manipulates MPD-designed primers.

use 5.10.0;

use Moose 2;
use namespace::autoclean;

use Carp qw/ croak /;
use Excel::Writer::XLSX;
use JSON;
use Path::Tiny;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Scalar::Util qw/ looks_like_number reftype /;
use List::Util qw/ shuffle /;
use Time::localtime;

use Data::Dump qw/ dump /; # for debugging

use MPD::Bed;
use MPD::Bed::Covered;
use MPD::Covered;
use MPD::Primer::Raw;
use MPD::Seq;

our $VERSION = '0.001';
my @plates = ( 1 .. 48 );
my @cols   = ( 1 .. 12 );
my @rows   = qw(A B C D E F G H);

has Primers => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => 'ArrayRef[MPD::Primer::Raw]',
  handles => {
    all_primers   => 'elements',
    no_primers    => 'is_empty',
    count_primers => 'count',
    add_primer    => 'push',
  },
  default => sub { [] },
);

sub as_aref {
  my $self = shift;

  my @array;

  for my $p ( $self->all_primers ) {
    push @array, $p->as_aref;
  }
  return \@array;
}

sub as_bed_obj {
  my $self = shift;

  my @array;

  for my $p ( $self->all_primers ) {
    my ( $chr, $start, $stop ) = $p->Covered();
    my $b = MPD::Bed::Raw->new(
      {
        Chr   => $chr,
        Start => $start,
        End   => $stop,
        Name  => $p->Name(),
      }
    );
    push @array, $b;
  }
  return MPD::Bed->new( \@array );
}

sub WriteBedFileLetter {
  state $check = compile( Object, Str );
  my ( $self, $file ) = $check->(@_);

  my $bedObj = $self->as_bed_obj();
  my $fh     = path($file)->filehandle(">");

  say {$fh} $bedObj->Entries_as_BedFileLetter;
}

sub WriteBedFile {
  state $check = compile( Object, Str );
  my ( $self, $file ) = $check->(@_);

  my $bedObj = $self->as_bed_obj();
  my $fh     = path($file)->filehandle(">");

  say {$fh} $bedObj->Entries_as_BedFile;
}

sub WriteOrderFile {
  state $check = compile( Object, Str, Optional [HashRef] );
  my ( $self, $file, $optHref ) = $check->(@_);

  if ( $self->no_primers ) {
    my $msg = "Error - no primers to write to order file: $file";
    say $msg;
    return;
  }

  my @header      = ( "WellPosition", "Name", "Sequence", "Notes" );
  my $orderHref   = $self->OrderAsHref($optHref);
  my $time_now    = ( exists $optHref->{time} ) ? $optHref->{time} : ctime();
  my $primerCount = 0;

  my $workbook = Excel::Writer::XLSX->new($file);
  $workbook->set_properties(
    title    => "Multiplex Primers",
    author   => 'The MPD package',
    comments => $time_now,
  );

  for my $plate ( sort keys %$orderHref ) {
    my $worksheet = $workbook->add_worksheet($plate);
    my ( $row, $col ) = ( 0, 0 );

    # write header
    $worksheet->write( $row, $col, \@header );
    $row++;

    # write primer data
    for my $primerAref ( @{ $orderHref->{$plate} } ) {
      $worksheet->write( $row, $col, $primerAref );
      $row++;
      $primerCount++;
    }
  }
  # I want to return the primer pairs written so divide the individual primers by 2
  $primerCount /= 2;
  return $primerCount;
}

# OrderAsHref returns a hashref with keys that correspond to plates and values
# containing arrayrefs of primer pairs; forward primers are placed on plates
# with "a" designation and reverse primers are on "b" designation. An optional
# hash can be supplied with keys: 'randomize' => print out primers in a random
# order, 'fwd_adapter' => adapter appended to 5' end of fwd primers,
# 'rev_adapter' => adapater appended to 5' end of the rev primers, 'prj_name'
# => a name for the project, and 'offset' => don't start at plate 1, row A
# (i.e., 0) but shift the plating forward to say plate 3, row A (i.e., 24).
# NOTE: primer pools are arrayed on the plate like so:
# ---
#   1   2   3  ... 12
# A <Pool 1 primers go here ...>
# B <Pool 2 primers go here ...>
# C
# D
# E
# F
# G
# H
# ---
sub OrderAsHref {
  state $check = compile( Object, Optional [HashRef] );
  my ( $self, $optHref ) = $check->(@_);

  if ( $self->no_primers ) {
    my $msg = "no primers to order";
    say $msg;
    return;
  }

  # Determine number of pools for the primer set
  my $poolCountHref = $self->PoolCount();
  my @poolNumbers = sort { $a <=> $b } keys %$poolCountHref;

  # get options
  my ( $bedObj, $prjName, $offset, $fwdAdapter, $revAdapter, $plateMax );
  if ( exists $optHref->{Bed} ) {
    $self->_UpdatePrimerCoveredNames( $optHref->{Bed} );
  }
  if ( exists $optHref->{Randomize} ) {
    @poolNumbers = shuffle(@poolNumbers);
  }
  if ( exists $optHref->{FwdAdapter} ) {
    $fwdAdapter = $optHref->{FwdAdapter};
  }
  else {
    $fwdAdapter = '';
  }
  if ( exists $optHref->{RevAdapter} ) {
    $revAdapter = $optHref->{RevAdapter};
  }
  else {
    $revAdapter = '';
  }
  if ( exists $optHref->{ProjectName} ) {
    $prjName = $optHref->{ProjectName};
  }
  else {
    $prjName = 'MPD';
  }
  if ( exists $optHref->{MaxPlates} ) {
    $plateMax = $optHref->{MaxPlates} - 1;
  }
  else {
    $plateMax = 48 - 1;
  }
  if ( exists $optHref->{PrnOffset} ) {
    $offset = $optHref->{PrnOffset};
  }
  else {
    $offset = 0;
  }
  if ( $offset < 0 ) {
    my $msg = "Printing Offset (PrnOffset) expected to be >=0.";
    croak($msg);
  }

  # organize the data we need
  my %hash;
  for my $p ( $self->all_primers ) {
    push @{ $hash{ $p->Pool } },
      [
      $p->Name,                   $p->CoveredName,
      $p->FwdPrimer($fwdAdapter), $p->RevPrimer($revAdapter)
      ];
  }

  my %prnHash;
  my $poolStartsAref = $self->_poolStart();
  my $pairCount      = 0;
  my $primerCount    = 0;

  for my $poolNumber (@poolNumbers) {

    # are we beyond the max number of plates
    if ( !exists $poolStartsAref->[ $pairCount + $offset ] ) {
      my $msg = "Asked to plate across >48 plates";
      warn $msg;
      last;
    }

    # did we reach the maximum number of plates specified
    my ( $plate, $row ) = @{ $poolStartsAref->[ $pairCount + $offset ] };
    if ( $plate > $plateMax ) {
      my $msg = sprintf(
        "Stopped writing primers after %d plates, %d primer pools, %d primer count",
        $plateMax + 1,
        $pairCount, $primerCount
      );
      say STDERR $msg;
      return \%prnHash;
    }

    my $colCount = 0;
    for my $primerPairAref ( @{ $hash{$poolNumber} } ) {
      my $well = $row . $cols[$colCount];
      my ( $primerName, $regionName, $fwdSeq, $revSeq ) = @$primerPairAref;
      my $prnPlate     = $plate + 1;
      my $fwdPlateName = join "_", $prjName, join( "", $prnPlate, "a" );
      my $revPlateName = join "_", $prjName, join( "", $prnPlate, "b" );
      push @{ $prnHash{$fwdPlateName} }, [ $well, $primerName, $fwdSeq, $regionName ];
      push @{ $prnHash{$revPlateName} }, [ $well, $primerName, $revSeq, $regionName ];
      $colCount++;
      $primerCount++;
    }
    $pairCount++;
  }
  return \%prnHash;
}

sub AddPrimers {
  state $check = compile( Object, Object );
  my ( $self, $primerObj ) = $check->(@_);

  for my $p ( $primerObj->all_primers ) {
    $self->add_primer($p);
  }
}

sub PoolCount {
  my $self = shift;

  my %poolCount;

  if ( $self->no_primers ) {
    return;
  }

  for my $p ( $self->all_primers ) {
    $poolCount{ $p->Pool }++;
  }
  return \%poolCount;
}

sub FilterPoolBelowThreshold {
  state $check = compile( Object, Num );
  my ( $self, $poolCountThreshold ) = $check->(@_);

  my @array;

  my $poolCountHref = $self->PoolCount();
  if ( !defined $poolCountHref ) {
    return;
  }

  #  my @debug = qw/ Pool Primer_number Chr Forward_primer Reverse_primer/;
  #  my $dat   = $self->PrimerList( \@debug );
  #  say "printing primer data before filter";
  #  for my $row (@$dat) {
  #    say join "\t", @$row;
  #  }

  my $newPoolCount = -1;
  for my $p ( $self->all_primers ) {
    if ( $poolCountHref->{ $p->Pool } >= $poolCountThreshold ) {
      if ( $p->Primer_number == 0 ) {
        $newPoolCount++;
      }
      my $pHref = $p->as_href();
      $pHref->{Pool} = $newPoolCount;
      push @array, MPD::Primer::Raw->new($pHref);
    }
  }
  my $newObj = MPD::Primer->new( \@array );
  #  $dat = $newObj->PrimerList( \@debug );
  #  say "printing primer data after filter";
  #  for my $row (@$dat) {
  #    say join "\t", @$row;
  #  }
  #
  #  $self->_saveJsonData(
  #    "$$.filterPrimer.tmp",
  #    {
  #      old => $self->as_aref,
  #      new => $newObj->as_aref,
  #    }
  #  );
  return $newObj;
}

sub PrimerList {
  state $check = compile( Object, ArrayRef );
  my ( $self, $attrsAref ) = $check->(@_);

  # TODO: use reftype here
  if ( scalar @$attrsAref == 0 ) {
    my $msg = "Attributes should be a list";
    croak $msg;
  }

  my @array;

  for my $p ( $self->all_primers ) {
    my @dat = map { $p->$_ } @$attrsAref;
    push @array, \@dat;
  }
  return \@array;
}

sub BaseFileCoverage {
  state $check = compile( Object, Str, Optional [Num], Optional [Num] );

  my ( $self, $baseFile, $probThresh, $coverageThresh ) = $check->(@_);
  if ( !defined $probThresh )     { $probThresh     = 0.8; }
  if ( !defined $coverageThresh ) { $coverageThresh = 0.8; }

  my $baseObj = MPD::Seq->new(
    {
      BaseFile          => $baseFile,
      CallProb          => $probThresh,
      CoverageThreshold => $coverageThresh
    }
  );
  $self->_SeqCoverage($baseObj);
}

sub _SeqCoverage {
  state $check = compile( Object, Object );
  my ( $self, $baseObj ) = $check->(@_);

  my @array;

  my $primerForSiteHref = $self->_primersForSites();

  for my $entry ( $baseObj->all_covered, $baseObj->all_uncovered ) {
    my $count = 0;
    my %primersForRegion;
    for ( my $i = $entry->Start; $i <= $entry->End; $i++ ) {
      my $site = sprintf( "%s:%s", $entry->Chr, $i );
      if ( exists $primerForSiteHref->{$site} ) {
        my @primers = keys %{ $primerForSiteHref->{$site} };
        $primersForRegion{$_} = 1 for @primers;
        if ( $entry->Name eq 'covered' ) {
          $count++;
        }
      }
    }
    my $primersCoveredStr;
    if (%primersForRegion) {
      $primersCoveredStr = join ";", sort keys %primersForRegion;
    }
    else {
      $primersCoveredStr = 'NA';
    }

    my $c = MPD::Bed::Covered->new(
      {
        Chr          => $entry->Chr,
        Start        => $entry->Start,
        End          => $entry->End,
        Name         => $entry->Name,
        CoveredCount => $count,
        Primer       => $primersCoveredStr,
      }
    );
    push @array, $c;
  }
  return MPD::Covered->new( \@array );
}

sub BedFileCoverage {
  state $check = compile( Object, Str );
  my ( $self, $bedFile ) = $check->(@_);

  my $bedObj = MPD::Bed->new($bedFile);
  return $self->BedCoverage($bedObj);
}

sub BedFileUncovered {
  state $check = compile( Object, Str );
  my ( $self, $bedFile ) = $check->(@_);

  my $bedObj = MPD::Bed->new($bedFile);
  return $self->BedUncovered($bedObj);
}

sub BedUncovered {
  state $check = compile( Object, Object );
  my ( $self, $bedObj ) = $check->(@_);

  my @array;

  my $primerForSiteHref = $self->_primersForSites();
  #say dump( $primerForSiteHref );

  for my $entry ( $bedObj->all_entries ) {
    my %uncoveredSites;
    for ( my $i = $entry->Start; $i <= $entry->End; $i++ ) {
      my $site = sprintf( "%s:%s", $entry->Chr, $i );
      if ( !exists $primerForSiteHref->{$site} ) {
        $uncoveredSites{$i}++;
      }
    }
    if (%uncoveredSites) {
      my @sortedSites = map { $_ } sort { $a <=> $b } keys %uncoveredSites;
      my $b = MPD::Bed::Raw->new(
        {
          Chr   => $entry->Chr,
          Start => $sortedSites[0],
          End   => $sortedSites[-1],
          Name  => $entry->Name,
        }
      );
      # say dump ( { entry => $entry, sortedSites => \@sortedSites, bed => $b } );
      push @array, $b;
    }
    # say dump ( { entry => $entry, sortedSites => 'NA' , bed => 'NA' } );
  }
  # no uncovered poriton
  if ( !@array ) {
    return;
  }
  return MPD::Bed->new( \@array );
}

sub _UpdatePrimerCoveredNames {
  state $check = compile( Object, Object );
  my ( $self, $bedObj ) = $check->(@_);

  my $bedNamesHref = $bedObj->SiteNames;

  for my $p ( $self->all_primers ) {
    my ( $chr, $start, $end ) = @{ $p->Covered };
    for ( my $i = $start; $i < $end; $i++ ) {
      my $site = join ":", $chr, $i;
      if ( exists $bedNamesHref->{$site} ) {
        $p->CoveredName( $bedNamesHref->{$site} );
        last;
      }
    }
  }
}

sub BedCoverage {
  state $check = compile( Object, Object );
  my ( $self, $bedObj ) = $check->(@_);

  my @array;

  my $primerForSiteHref = $self->_primersForSites();

  for my $entry ( $bedObj->all_entries ) {
    my $count = 0;
    my %primersForRegion;
    for ( my $i = $entry->Start; $i <= $entry->End; $i++ ) {
      my $site = sprintf( "%s:%s", $entry->Chr, $i );
      if ( exists $primerForSiteHref->{$site} ) {
        my @primers = keys %{ $primerForSiteHref->{$site} };
        $primersForRegion{$_} = 1 for @primers;
        $count++;
      }
    }
    my $primersCoveredStr;
    if (%primersForRegion) {
      $primersCoveredStr = join ";", sort keys %primersForRegion;
    }
    else {
      $primersCoveredStr = 'NA';
    }

    my $c = MPD::Bed::Covered->new(
      {
        Chr          => $entry->Chr,
        Start        => $entry->Start,
        End          => $entry->End,
        Name         => $entry->Name,
        CoveredCount => $count,
        Primer       => $primersCoveredStr,
      }
    );
    push @array, $c;
  }
  return MPD::Covered->new( \@array );
}

# DuplicatePrimers returns a list of duplicate primer names
sub DuplicatePrimers {
  my $self = shift;

  my ( @duplicates, %uniqPrimers );

  for my $p ( $self->all_primers ) {
    push @{ $uniqPrimers{ $p->Product } }, $p->Name;
  }

  for my $prod ( keys %uniqPrimers ) {
    my $primerNamesAref = $uniqPrimers{$prod};
    if ( scalar @$primerNamesAref > 1 ) {
      push @duplicates, @{$primerNamesAref}[ 1 .. $#{$primerNamesAref} ];
      #say dump( { DuplicatePrimers => \@duplicates } );
    }
  }
  return \@duplicates;
}

# RemovePrimers takes a list of primer names and removes them from the primer
# object and re-writes the primers into a new object with the correct order
# of primer pools and correct order of the primers within the pools
sub RemovePrimers {
  state $check = compile( Object, ArrayRef );
  my ( $self, $PrimerNamesAref ) = $check->(@_);

  # the idea is to make a hash of array of primer pairs; the key of the hash
  # is the primer pool and the array contains the individaul primer pairs of
  # primers that did not match the names of the primers to remove;
  # with the newly made hash of arrays of primers we will sort the pools in
  # order and re-label the pools and sort the primers in order and relabel
  # their Primer_number; this will eliminate any pools that were entirely
  # filtered away or when the '0' primer pair is removed, which normally
  # signals the start of a new pool, is removed.

  my ( @array, %newPoolCount );
  my %NamesOfPrimers = map { $_ => 1 } @$PrimerNamesAref;

  for my $p ( $self->all_primers ) {
    # print $p->Name;
    if ( !exists $NamesOfPrimers{ $p->Name } ) {
      #say " is ok";
      push @{ $newPoolCount{ $p->Pool } }, [ $p->Primer_number, $p->as_href ];
    }
    #else {
    #  say " is removed";
    #}
  }

  my $newPool = 0;
  for my $pool ( sort { $a <=> $b } keys %newPoolCount ) {
    my $primerNumber = 0;
    my @primers = map { $_->[1] } sort { $a->[0] <=> $b->[0] } @{ $newPoolCount{$pool} };
    for my $pHref (@primers) {
      $pHref->{Primer_number} = $primerNumber;
      $pHref->{Pool}          = $newPool;
      $primerNumber++;
      push @array, MPD::Primer::Raw->new($pHref);
    }
    $newPool++;
  }

  # if we filter all primers away
  if ( !@array ) {
    return;
  }

  return MPD::Primer->new( \@array );
}

sub WriteCoveredFile {
  state $check = compile( Object, Str, Object );
  my ( $self, $fileName, $bedObj ) = $check->(@_);

  if ( $self->no_primers ) {
    my $msg = "Error - no primers to write to coverage file: $fileName";
    say $msg;
    return;
  }

  my $fh         = path($fileName)->filehandle(">");
  my $coveredObj = $self->BedCoverage($bedObj);
  say {$fh} $coveredObj->Entries_as_str();
}

sub WriteUncoveredFile {
  state $check = compile( Object, Str, Object );
  my ( $self, $fileName, $bedObj ) = $check->(@_);

  if ( $self->no_primers ) {
    my $msg = "Error - no primers to write to uncovered file: $fileName";
    say $msg;
    return;
  }

  my $fh              = path($fileName)->filehandle(">");
  my $uncoveredBedObj = $self->BedUncovered($bedObj);

  say {$fh} $uncoveredBedObj->Entries_as_BedFile();
}

sub WritePrimerFile {
  state $check = compile( Object, Str, Optional [Num] );
  my ( $self, $fileName, $primerMax ) = $check->(@_);

  my $primerCount = 0;
  if ( !defined $primerMax ) {
    $primerMax = 999;
  }

  if ( $self->no_primers ) {
    my $msg = "Error - no primers to write to primer file: $fileName";
    say $msg;
    return;
  }

  my $fh = path($fileName)->filehandle(">");
  my @header;

  for my $p ( $self->all_primers ) {
    if ( $primerCount > $primerMax ) {
      last;
    }
    if ( !@header ) {
      @header = @{ $p->Header() };
      say {$fh} join "\t", @header;
    }
    my @data = map { $p->$_ } @header;
    say {$fh} join "\t", @data;
    $primerCount++;
  }
  return $primerCount;
}

sub WriteIsPcrFile {
  state $check = compile( Object, Str, Optional [Num] );
  my ( $self, $fileName, $primerMax ) = $check->(@_);

  my $primerCount = 0;
  if ( !defined $primerMax ) {
    $primerMax = 999;
  }

  if ( $self->no_primers ) {
    my $msg = "Error - no primers to write to isPcr file: $fileName";
    say $msg;
    return;
  }

  my $fh = path($fileName)->filehandle(">");

  for my $p ( $self->all_primers ) {
    if ( $primerCount > $primerMax ) {
      last;
    }
    say {$fh} join "\t", $p->Name, $p->Forward_primer, $p->Reverse_primer;
    $primerCount++;
  }
  return $primerCount;
}

sub Sumarize_as_aref {
  my $self = shift;

  my @array;

  if ( $self->no_primers ) {
    my $msg = "no primers to summarize";
    say $msg;
    return;
  }

  # header
  push @array, [qw/ Pool Primers_in_pool /];

  # data
  my $href = $self->PoolCount();
  for my $pool ( sort { $a <=> $b } keys %$href ) {
    push @array, [ $pool, $href->{$pool} ];
  }
  return \@array;
}

sub Summarize_as_str {
  my $self = shift;

  my $summaryAref = $self->Sumarize_as_aref();
  my @array;

  for my $row (@$summaryAref) {
    push @array, join "\t", @$row;
  }

  return join "\n", @array;
}

# BUILDARGS takes either a hash reference or string, which is a primer file
sub BUILDARGS {
  my $class = shift;

  if ( scalar @_ == 1 ) {
    if ( !reftype( $_[0] ) ) {
      # assumption is that you passed a file be read and used to create
      # recall, reftype returns undef for string values

      my $file        = $_[0];
      my $primersAref = $class->_ReadPrimerFile($file);
      return $class->SUPER::BUILDARGS( { Primers => $primersAref } );
    }
    elsif ( reftype( $_[0] ) eq "ARRAY" ) {
      return $class->SUPER::BUILDARGS( { Primers => $_[0] } );
    }
    elsif ( reftype( $_[0] ) eq "HASH" ) {
      return $class->SUPER::BUILDARGS( $_[0] );
    }
    else {
      my $msg =
        "Error: Construct MPD::Primer object with either a hashref, arrayref of hashrefs, or primer file";
      croak($msg);
    }
  }
  else {
    my $msg =
      "Error: Construct MPD::Primer object with either a hashref, arrayref of hashrefs, or primer file";
    croak($msg);
  }
}

sub _ReadPrimerFile {
  my ( $class, $file ) = @_;

  my @primers;

  # NOTE:
  # - older files might not have this header
  # - will use it to check header
  my @expHeader = qw/Primer_number Forward_primer Forward_Tm Forward_GC
    Reverse_primer Reverse_Tm Reverse_GC Chr Forward_start_position
    Forward_stop_position Reverse_start_position Reverse_stop_position
    Product_length Product_GC Product_tm Product/;
  my ( %header, @NotFoundFields );
  my $poolCount = -1;

  my @lines = path($file)->lines( { chomp => 1 } );
  for my $lineCount ( 0 .. $#lines ) {
    my $line         = $lines[$lineCount];
    my @fields       = split /\t/, $line;
    my %fieldPresent = map { $_ => 1 } @fields;
    if ( !%header ) {
      for my $eField (@expHeader) {
        if ( !exists $fieldPresent{$eField} ) {
          push @NotFoundFields, $eField;
        }
      }
      # legacy files don't have a header but start with the Primer_number
      if ( $fields[0] =~ m/\A\d+/ ) {
        %header = map { $expHeader[$_] => $_ } ( 0 .. $#expHeader );
        say dump( \%header );
      }
      # newer format has a header so skip to the next line after grabbing the header
      elsif ( !@NotFoundFields ) {
        %header = map { $fields[$_] => $_ } ( 0 .. $#fields );
        next;
      }
      else {
        my $msg = "Cannot find fields: ";
        $msg .= "'" . join( "', '", @NotFoundFields ) . "'";
        croak $msg;
      }
    }
    my %data = map { $_ => $fields[ $header{$_} ] } ( keys %header );
    my $primerNumber = $data{Primer_number};
    if ( !looks_like_number($primerNumber) ) {
      my $msg =
        sprintf( "Error: no value for expected header Primer_number at line: %d\n\n==> %s",
        ( $lineCount + 1 ), $line );
      croak $msg;
    }

    if ( $primerNumber == 0 ) {
      $poolCount++;
    }
    $data{Pool} = $poolCount;
    my $p = MPD::Primer::Raw->new( \%data );
    push @primers, $p;
  }
  return \@primers;
}

# _primersForSites returns a hashref of sites covered by the Primers
sub _primersForSites {
  my $self = shift;

  my %primerSites;

  for my $p ( $self->all_primers ) {
    my ( $chr, $start, $end ) = $p->Covered();
    for ( my $i = $start; $i <= $end; $i++ ) {
      my $site = join ":", $chr, $i;
      $primerSites{$site}{ $p->Name } = 1;
    }
  }
  return \%primerSites;
}

# _PlateRowPoolNumber returns an arrayRef of starting plates and row
# coordinates for each pool.
# NOTE: primer pools are arrayed on the plate like so:
# ---
#   1   2   3  ... 12
# A <Pool 1 primers go here ...>
# B <Pool 2 primers go here ...>
# C
# D
# E
# F
# G
# H
# ---
# Of course, you don't have to place pool 1 primers in the first slot, and,
# it's recommended to randomize so large pools are not adjacent to small pools
#
sub _poolStart {
  my $self = shift;

  my @poolStarts;

  foreach my $i ( 0 .. $#plates ) {
    foreach my $j ( 0 .. $#rows ) {
      push @poolStarts, [ $i, $rows[$j] ];
    }
  }
  return \@poolStarts;
}

sub _saveJsonData {
  my ( $self, $file, $data ) = @_;
  my $fh = path($file)->filehandle(">");
  print {$fh} encode_json($data);
  close $fh;
}

__PACKAGE__->meta->make_immutable;

1;
