package MPD;

# ABSTRACT: This package is used to for multiplex primer design.

use 5.10.0;

use Moose 2;
use MooseX::Types::Path::Tiny qw/ AbsPath AbsFile File /;
use namespace::autoclean;

use Excel::Writer::XLSX;
use Cpanel::JSON::XS;
use Path::Tiny;
use Scalar::Util qw/ blessed reftype /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Time::localtime;
use Try::Tiny;
use DDP output => 'stdout';
use Data::Dump qw/ dump /; # for debugging

use MPD::isPcr;
use MPD::Primer;
use MPD::Psl;
use MPD::PrimerDesign;

our $VERSION = '0.001';
my $time_now = ctime();
use Scalar::Util qw/looks_like_number/;

with 'MPD::Role::ConfigFromFile', 'MPD::Role::Message', 'MPD::Role::IO';

# attr for necessary data files
has BedFile => ( is => 'ro', isa => AbsFile, coerce => 1, required => 1, );
has Bed => ( is => 'ro', isa => 'MPD::Bed', builder => '_build_Bed', lazy => 1 );
has isPcrBinary => ( is => 'ro', isa => AbsFile, coerce => 1, required => 0, );
has TwoBitFile  => ( is => 'ro', isa => AbsFile, coerce => 1, required => 0, );
has MpdBinary   => ( is => 'ro', isa => AbsFile, coerce => 1, required => 1, );
has MpdIdx      => ( is => 'ro', isa => File,    coerce => 1, required => 1, );
has dbSnpIdx    => ( is => 'ro', isa => File,    coerce => 1, required => 1, );
has OutExt => ( is => 'ro', isa => 'Str', required => 1, );
has OutDir => ( is => 'ro', isa => AbsPath, coerce => 1, required => 1, );
has Debug    => ( is => 'ro', isa => 'Bool', default => 0 );
has RunIsPcr => ( is => 'ro', isa => 'Bool', default => 0 );
has Act      => ( is => 'ro', isa => 'Bool', default => 0 );

# attr for parameter optimization
has CoverageThreshold => ( is => 'ro', isa => 'Num', default => 0.5, required => 1 );
has IncrAmpSize       => ( is => 'ro', isa => 'Int', default => 10, required => 1 );
has IncrTm            => ( is => 'ro', isa => 'Num', default => 0.5, required => 1 );
has IncrTmStep        => ( is => 'ro', isa => 'Num', default => 0.5, required => 1 );
has IterMax           => ( is => 'ro', isa => 'Int', default => 10,  required => 1 );

# pcr attrs, mirrored in MPD::PrimerDesign
has PrimerSizeMin => ( is => 'ro', isa => 'Int', default => 17,  required => 1 );
has PrimerSizeMax => ( is => 'ro', isa => 'Int', default => 27,  required => 1 );
has AmpSizeMin    => ( is => 'rw', isa => 'Int', default => 180, required => 1 );
has AmpSizeMax    => ( is => 'rw', isa => 'Int', default => 230, required => 1 );
has GcMin         => ( is => 'rw', isa => 'Num', default => 0.3, required => 1 );
has GcMax         => ( is => 'rw', isa => 'Num', default => 0.7, required => 1 );
has TmMin         => ( is => 'rw', isa => 'Num', default => 57,  required => 1 );
has TmMax         => ( is => 'rw', isa => 'Num', default => 62,  required => 1 );
has PoolMax       => ( is => 'ro', isa => 'Int', default => 10,  required => 1 );
has PoolMin       => ( is => 'ro', isa => 'Int', default => 1,   required => 1 );
has TmStep        => ( is => 'rw', isa => 'Num', default => 0.5, required => 1 );
has PadSize       => ( is => 'ro', isa => 'Int', default => 60,  required => 1 );

# max and min allowed parameter values
my %ParmsMax = (
  PrimerSizeMin => 30,
  PrimerSizeMax => 30,
  AmpSizeMin    => 1000,
  AmpSizeMax    => 1000,
  GcMin         => 0.8,
  GcMax         => 0.8,
  TmMin         => 75,
  TmMax         => 75,
  PoolMax       => 10,
  PoolMin       => 10,
  TmStep        => 4,
  PadSize       => 200,
);

my %ParmsMin = (
  PrimerSizeMin => 17,
  PrimerSizeMax => 17,
  AmpSizeMin    => 100,
  AmpSizeMax    => 100,
  GcMin         => 0.3,
  GcMax         => 0.3,
  TmMin         => 50,
  TmMax         => 50,
  PoolMax       => 1,
  PoolMin       => 1,
  TmStep        => 0.5,
  PadSize       => 60,
);

# regions that are uncovered _after_ initial trial
has UnCovered => ( is => 'rw', isa => 'Maybe[MPD::Bed]', default => sub { } );

# printing options
has ProjectName => ( is => 'ro', isa => 'Str', default => 'MPD' );
has FwdAdapter  => ( is => 'ro', isa => 'Str', default => 'ACACTGACGACATGGTTCTACA' );
has RevAdapter  => ( is => 'ro', isa => 'Str', default => 'TACGGTAGCAGAGACTTGGTCT' );

# offset to start printing pools
has PrnOffset => ( is => 'ro', isa => 'Num', default => 0 );

# randomize printing of primer pools (avoids large and small pools clustering
# across an experiment in a non-random way)
has Randomize => ( is => 'ro', isa => 'Bool', default => 1 );

has _Iter => (
  traits  => ['Counter'],
  is      => 'ro',
  isa     => 'Num',
  handles => { _incrIter => 'inc', },
  default => 0,
);

has _poolCount => (
  traits  => ['Counter'],
  is      => 'ro',
  isa     => 'Num',
  handles => { _incrPool => 'inc', },
  default => 0,
);

# a scratch space for pools we want to keep
has KeepPools => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => 'ArrayRef[ArrayRef[MPD::Primer::Raw]]',
  handles => {
    all_pools   => 'elements',
    no_pool     => 'is_empty',
    count_pools => 'count',
    add_pool    => 'push',
    clear_pools => 'clear',
  },
  default => sub { [] },
);

# final primer design
has KeepPrimers => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => 'ArrayRef[MPD::Primer::Raw]',
  handles => {
    all_primers   => 'elements',
    no_primer     => 'is_empty',
    count_primers => 'count',
    add_primer    => 'push',
  },
  default => sub { [] },
);

has verbose => ( is => 'ro', default => 1 );

has publisher => ( is => 'ro' );

has compress => (is => 'ro', default => 0);

sub BUILDARGS {
  my ($class, $data) = @_;

  for my $d (keys %$data) {
    if(!looks_like_number($data->{$d}) && $data->{$d} eq '') {
      delete $data->{$d};
    }
  }

  return $data
}

sub BUILD {
  my $self = shift;

  if ( $self->publisher ) {
    $self->setPublisher( $self->publisher );
  }

  $self->setLogPath(
    path( $self->OutDir )->child( $self->OutExt . ".log" )->stringify );

  if ( $self->Debug ) {
    $self->setLogLevel('DEBUG');
  }

  if ( $self->verbose ) {
    $self->setVerbosity(1);
  }
}

sub RunAll {
  my $self = shift;
  my $ok   = $self->FindBestCoverage( $self->Act );
  if ( !$ok ) {
    $self->log( 'warn',
      sprintf( "Return from primer design before %d iteration", $self->IterMax ) );
  }

  # Returns json string
  my $json = $self->PrintPrimerData( $self->OutExt, 1 );

  my $compressPath;
  if($self->compress) {
    $compressPath = $self->compressPath( $self->OutDir->child($self->OutExt) );
  }

  say "compress path is " . $self->OutDir->child($self->OutExt)->stringify;
  p $compressPath;

  return ($compressPath, $json);
}

sub PrintPrimerData {
  state $check = compile( Object, Str, Bool );
  my ( $self, $OutExt, $printJson ) = $check->(@_);

  if ( $self->no_primer ) {
    $self->log( 'warn', 'No Primers written. This might be a dry run.' );
    return;
  }

  if ( $self->Debug ) {
    say "Writing final primer design.";
  }

  my $p       = MPD::Primer->new( $self->KeepPrimers );
  my $dupAref = $p->DuplicatePrimers();
  $p = $p->RemovePrimers($dupAref);

  # order file goes first so that we upate the primers with the
  # names of the regions in the bedfile, if there are any.
  my $forOrderPt = $self->OutDir->child( sprintf( "%s.forOrder.xlsx", $OutExt ) );
  $p->WriteOrderFile( $forOrderPt->stringify, $self->_prnOpt );

  my $coveredPt = $self->OutDir->child( sprintf( "%s.covered.bed", $OutExt ) );
  $p->WriteCoveredFile( $coveredPt->stringify, $self->Bed );

  my $uncoveredPt = $self->OutDir->child( sprintf( "%s.uncovered.bed", $OutExt ) );
  $p->WriteUncoveredFile( $uncoveredPt->stringify, $self->Bed );

  my $primerPt = $self->OutDir->child( sprintf( "%s.primer.txt", $OutExt ) );
  $p->WritePrimerFile( $primerPt->stringify );

  my $isPcrPt = $self->OutDir->child( sprintf( "%s.isPcr.txt", $OutExt ) );
  $p->WriteIsPcrFile( $isPcrPt->stringify );

#  my $compressPath;
#  if($self->compress) {
#    $compressPath = $self->compressPath( $self->OutDir->child($OutExt) );
#  }

#  say "compress path is " . $self->OutDir->child($OutExt)->stringify;
#  p $compressPath;
   
   if($printJson) {
     return $p->MakeCoveredJsonString( $self->Bed );
   }

   return;
}


# FindBestCoverage performs the primer design for a number of specified
# iterations. Before each primer design attempt the objects PCR parameters
# are vaildated. If the function exits before IterMax then it returns undef
# otherwise it returns 1.
sub FindBestCoverage {
  my ( $self, $act ) = @_;

  my $iterTotal = $self->IterMax + 1;

  while ( $self->_Iter < $self->IterMax ) {
    my ( $ok, $msg ) = $self->_validatePcrParams;
    if ( !$ok ) {
      $self->log( 'warn',
        sprintf( "Stopping at iteration %d because %s", $self->_Iter, $msg ) );
      return;
    }

    $self->_runPrimerDesign( $self->PoolMin );

    $self->_incrAmpSize;
    ( $ok, $msg ) = $self->_validatePcrParams;
    if ( !$ok ) {
      $self->log( 'warn',
        sprintf( "Stopping at iteration %d because %s", $self->_Iter, $msg ) );
      return;
    }

    $self->_runPrimerDesign( $self->PoolMin );

    $self->_incrTm;
    ( $ok, $msg ) = $self->_validatePcrParams;
    if ( !$ok ) {
      $self->log( 'warn',
        sprintf( "Stopping at iteration %d because %s", $self->_Iter, $msg ) );
      return;
    }

    $self->_runPrimerDesign( $self->PoolMin );

    $self->_incrTmStep;
    ( $ok, $msg ) = $self->_validatePcrParams;
    if ( !$ok ) {
      $self->log( 'warn',
        sprintf( "Stopping at iteration %d because %s", $self->_Iter, $msg ) );
      return;
    }

    $self->_runPrimerDesign( $self->PoolMin );
    $self->_incrIter;

    $self->publishProgress( $self->_Iter );
  }
  return 1;
}

# _validatePcrParams() validates the object's PCR parameters and returns an
# array with the first value as the success code and the second as the string
# of error messages, if any.
sub _validatePcrParams {
  my $self = shift;

  my @fail;

  for my $attr ( sort keys %ParmsMin ) {
    if ( $self->$attr < $ParmsMin{$attr} ) {
      push @fail,
        sprintf( "%s (%d) < minimum (%d)", $attr, $self->$attr, $ParmsMin{$attr} );
    }
    elsif ( $self->$attr > $ParmsMax{$attr} ) {
      push @fail,
        sprintf( "%s (%d) > maximum (%d)", $attr, $self->$attr, $ParmsMax{$attr} );
    }
    elsif ( $attr eq "PrimerSizeMin" ) {
      if ( $self->$attr > $self->PrimerSizeMax ) {
        push @fail,
          sprintf( "%s (%d) < PrimerSizeMax (%d)",
          $attr, $self->$attr, $self->PrimerSizeMax );
      }
    }
    elsif ( $attr eq "GcMin" ) {
      if ( $self->$attr > $self->GcMax ) {
        push @fail, sprintf( "%s (%d) > GcMax (%d)", $attr, $self->$attr, $self->GcMax );
      }
    }
    elsif ( $attr eq "TmMin" ) {
      if ( $self->$attr > $self->TmMax ) {
        push @fail, sprintf( "%s (%d) > TmMax (%d)", $attr, $self->$attr, $self->TmMax );
      }
    }
    elsif ( $attr eq "PoolMax" ) {
      if ( $self->$attr < $self->PoolMin ) {
        push @fail, sprintf( "%s (%d) < PoolMin (%d)", $attr, $self->$attr, $self->PoolMin );
      }
    }
    elsif ( $attr eq "PadSize" ) {
      if ( $self->$attr < $self->PrimerSizeMin ) {
        push @fail,
          sprintf( "%s (%d) < PrimerSizeMin (%d)",
          $attr, $self->$attr, $self->PrimerSizeMin );
      }
    }
  }
  if ( scalar @fail > 0 ) {
    # output message
    return ( undef, join "\n", @fail );
  }
  else {
    return ( 1, "" );
  }
}

sub _build_Bed {
  my $self = shift;
  return MPD::Bed->new( $self->BedFile->stringify );
}

sub _pcrParams {
  my $self = shift;

  my @attrs = qw/ AmpSizeMin AmpSizeMax GcMin GcMax GcMax TmMin TmMax TmStep
    PoolMin PoolMax PadSize OutExt RunIsPcr /;
  my @files = qw/ BedFile isPcrBinary TwoBitFile MpdBinary MpdIdx dbSnpIdx /;

  my %attrs = map { ( $self->$_ ) ? ($_ => $self->$_) : ()} (@attrs);
  my %files = map { ( $self->$_ ) ? ($_ => $self->$_->stringify) : ()} @files;

  if ( $self->Debug ) {
    say "=== PCR Parameters ===";
    say dump( { %attrs, %files } );
  }

  if ( $self->UnCovered() ) {
    $self->log( 'info', "PCR Params: using uncovered bed data" );
    $attrs{Bed} = $self->UnCovered();
  }
  else {
    $self->log( 'info', "PCR Params: using original bed data" );
    $attrs{Bed} = $self->Bed();
  }
  say "======================" if $self->Debug;

  return { %attrs, %files };
}

sub _prnOpt {
  my $self = shift;

  my @attrs = qw/ Bed ProjectName FwdAdapter RevAdapter PrnOffset Randomize /;
  my %hash = map { $_ => $self->$_ } @attrs;
  return \%hash;
}

sub _incrAmpSize {
  my $self = shift;

  my $max = $self->AmpSizeMax;
  $max += $self->IncrAmpSize;
  $self->AmpSizeMax($max);

  my $min = $self->AmpSizeMin;
  $min -= $self->IncrAmpSize;
  $self->AmpSizeMin($min);
}

sub _incrTm {
  my $self = shift;

  my $max = $self->TmMax;
  $max += $self->IncrTm;
  $self->TmMax($max);

  my $min = $self->TmMin;
  $min -= $self->IncrTm;
  $self->TmMin($min);
}

sub _incrTmStep {
  my $self   = shift;
  my $tmIncr = $self->TmStep;
  $tmIncr += $self->IncrTmStep;
  $self->TmStep($tmIncr);
}

sub _runPrimerDesign {
  state $check = compile( Object, Optional [Num] );
  my ( $self, $poolMinThreshold ) = $check->(@_);

  if ( !$self->Act ) {
    return;
  }

  if ( !$poolMinThreshold ) {
    $poolMinThreshold = $self->PoolMin;
  }

  my $primerDesignHref = $self->_pcrParams();
  my $p                = MPD::PrimerDesign->new($primerDesignHref);

  # UniqPrimers() - calls mpd then isPcr
  my $primerObj = $p->UniqPrimers();
  if ( !defined $primerObj ) {
    return;
  }

  if ( $self->Debug ) {
    $self->_printPrimerSummary( $primerObj, '_runPrimerDesign() - before filter' );
  }

  $primerObj = $primerObj->FilterPoolBelowThreshold( $self->PoolMin() );
  if ( !defined $primerObj ) {
    return;
  }

  if ( $self->Debug ) {
    $self->_printPrimerSummary( $primerObj, '_runPrimerDesign() - after filter' );
  }
  return $self->_keepPools( $primerObj, $poolMinThreshold );
}

# _keepPools takes a primerObj and finds the pools with pools >= the threshold
# number of primers; these pools are retained in the global KeepPools =>
# (arrayref(arrayref(MPD::Primer::Raw))); those pools are then stored in the
# global KeepPrimers
sub _keepPools {
  state $check = compile( Object, Object, Num );
  my ( $self, $primerObj, $poolMinThreshold ) = $check->(@_);

  my (%keep);
  my $poolCountHref = $primerObj->PoolCount;

  for my $p ( $primerObj->all_primers ) {
    if ( $poolCountHref->{ $p->Pool } >= $poolMinThreshold ) {
      push @{ $keep{ $p->Pool } }, $p;
    }
  }

  for my $pool ( keys %keep ) {
    $self->add_pool( $keep{$pool} );
  }
  return $self->_keepPoolPrimers;
}

# _keepPoolPrimers takes all pooled primers in KeepPools and transfers them
# to keepPrimers; it then updates what is not covered by the pools against
# either the original bed targets or the last uncovered bed object
sub _keepPoolPrimers {
  my $self = shift;

  if ( $self->no_pool ) {
    return $self->log( 'info', "no pooled primers" );
  }

  for my $aref ( $self->all_pools ) {
    for my $p (@$aref) {
      my $pHref = $p->as_href;
      $pHref->{Pool} = $self->_poolCount;
      $self->add_primer( MPD::Primer::Raw->new($pHref) );
    }
    $self->_incrPool;
  }
  $self->clear_pools;
  return $self->_updateUncovered();
}

# _updateUncovered updates the UnCovered attribute based on data in the
# KeepPrimers attribute
sub _updateUncovered {
  my $self = shift;

  # pcrParams() knows which bed object (either initial or latest uncovered
  # bed object to provide as the target bed object
  my $primerDesignHref = $self->_pcrParams();
  my $primerObj        = MPD::Primer->new( $self->KeepPrimers );
  my $uncoveredBedObj  = $primerObj->BedUncovered( $primerDesignHref->{Bed} );
  $self->_printPrimerSummary( $primerObj, '_uncovered()' ) if $self->Debug;
  $self->UnCovered($uncoveredBedObj);
  $self->PrintPrimerData( $self->_Iter, 0 );
}

# for debugging
sub _saveBedFile {
  my ( $self, $file, $bedObj ) = @_;
  my $fh = path($file)->filehandle(">");
  print {$fh} join( "\n", @{ $bedObj->Entries_as_aref() } );
}

# for debugging
sub _saveJsonData {
  my ( $self, $file, $data ) = @_;
  my $fh = path($file)->filehandle(">");
  print {$fh} encode_json($data);
}

# _printPrimerSummary prints either an arrayref of MPD::Primer's or a single
# MPD::Primer object with a label to help debug
sub _printPrimerSummary {
  my ( $self, $primer, $labelStr ) = @_;

  $self->log( 'info', $labelStr );

  if ( !defined $primer ) {
    $self->log( 'info', ">> No Primers <<" );
  }
  elsif ( reftype $primer eq 'ARRAY' ) {
    my $count = 1;
    for my $primerObj (@$primer) {
      $self->log( 'info', "--- Primer Group $count ---" );
      $self->log( 'info', $primerObj->Summarize_as_str() );
      $count++;
    }
  }
  elsif ( blessed $primer eq 'MPD::Primer' ) {
    $self->log( 'info', $primer->Summarize_as_str() );
  }
  else {
    $self->log( 'fatal', "unrecognized thing to print" );
  }
}

__PACKAGE__->meta->make_immutable;

1;

