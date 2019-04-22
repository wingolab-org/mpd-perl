package MPD::PrimerDesign;

# ABSTRACT: This package is used to for multiplex primer design.

use 5.10.0;

use Moose 2;
use MooseX::Types::Path::Tiny qw/ AbsPath AbsFile File /;
use namespace::autoclean;

use Excel::Writer::XLSX;
use Path::Tiny;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Time::localtime;

use Data::Dump qw/ dump /; # for debugging

use MPD::Bed;
use MPD::isPcr;
use MPD::Primer;
use MPD::Psl;

use IPC::Run qw(run timeout);

with "MPD::Role::Message";

our $VERSION = '0.001';
my $time_now = ctime();

has Bed => ( is => 'ro', isa => 'MPD::Bed', required => 1 );

# optionally run isPcr on design
has RunIsPcr => ( is => 'ro', isa => 'Bool', default => 1 );

# required files
has isPcrBinary => ( is => 'ro', isa => AbsFile, coerce => 1, required => 1, );
has TwoBitFile  => ( is => 'ro', isa => AbsFile, coerce => 1, required => 1, );
has MpdBinary   => ( is => 'ro', isa => AbsFile, coerce => 1, required => 1, );
has MpdIdx      => ( is => 'ro', isa => File,    coerce => 1, required => 1, );
has dbSnpIdx    => ( is => 'ro', isa => File,    coerce => 1, required => 1, );
has OutExt      => ( is => 'ro', isa => 'Str',  required => 1, );

# pcr attrs
has PrimerSizeMin => ( is => 'ro', isa => 'Int', default => 17,  required => 1 );
has PrimerSizeMax => ( is => 'ro', isa => 'Int', default => 27,  required => 1 );
has AmpSizeMin    => ( is => 'ro', isa => 'Int', default => 150, required => 1 );
has AmpSizeMax    => ( is => 'ro', isa => 'Int', default => 250, required => 1 );
has GcMin         => ( is => 'ro', isa => 'Num', default => 0.3, required => 1 );
has GcMax         => ( is => 'ro', isa => 'Num', default => 0.7, required => 1 );
has TmMin         => ( is => 'ro', isa => 'Num', default => 57,  required => 1 );
has TmMax         => ( is => 'ro', isa => 'Num', default => 62,  required => 1 );
has PoolMax       => ( is => 'ro', isa => 'Int', default => 10,  required => 1 );
has PadSize       => ( is => 'ro', isa => 'Int', default => 60,  required => 1 );
has TmStep        => ( is => 'ro', isa => 'Num', default => 1,   required => 1 );
has Timeout       => ( is => 'ro', isa => 'Int', default => 7200 );


# Temporary Files
#my $bedPt    = Path::Tiny->tempfile();
#my $tmpCmdPt = Path::Tiny->tempfile();
#my $primerPt = Path::Tiny->tempfile();
#my $isPcrPt  = Path::Tiny->tempfile();
#my $mpdOut   = Path::Tiny->tempfile();

#PID is not safe to use here if multiple processes are interacting with a shared NFS
my $bedPt    = path("$$.bed");
my $tmpCmdPt = path("$$.cmd");
my $primerPt = path("$$.primer");
my $isPcrPt  = path("$$.isPcr");
my $mpdOut   = path("$$.mpdOut");

sub SayMppCmd {
  state $check = compile( Object, Str );
  my ( $self, $outFile ) = $check->(@_);

  my $bedFh = $bedPt->filehandle(">");
  say {$bedFh} $self->Bed->Entries_as_BedFile();

  my $cmd = join "\n", "d", $outFile, $self->MpdIdx, $self->dbSnpIdx,
    $bedPt->stringify, $self->PrimerSizeMin, $self->PrimerSizeMax, $self->AmpSizeMin,
    $self->AmpSizeMax, $self->GcMin, $self->GcMax, $self->TmMin, $self->TmMax,
    $self->PoolMax, $self->PadSize, $self->TmStep;
  return $cmd;
}

sub RunMpp {
  state $check = compile( Object, Str, Optional[Int] );
  my ( $self, $outFile, $timeout ) = $check->(@_);
  $timeout //= 7200;

  my $o = path($outFile);

  # create temp file with MPD commands
  my $tmpCmdFh = $tmpCmdPt->filehandle(">");
  say {$tmpCmdFh} $self->SayMppCmd( $o->stringify );

  my $ret;

  eval{
    # If command line arguments are ever required they are added as items in the
    # cmd array
    my @cmd = ($self->MpdBinary);
    $ret = run(\@cmd,'<',$tmpCmdPt->stringify,'>',$mpdOut->stringify,timeout($timeout));
  };

  unless ($ret) {
    $self->log( 'fatal', "MPD C choked. We're on it!" );
    return;
  }

  if ( $o->is_file ) {
    return 1;
  }
  else {
    return;
  }
}

# UniqPrimers calls isPcr to filter away primers that amplify >1 thing in the
# genome based on isPcr's rules and any duplicates from the MPD program
sub UniqPrimers {
  my $self = shift;

  my $ok = $self->RunMpp( $primerPt->stringify, $self->timeout );
  if ( !$ok ) {
    $self->log( 'fatal', "Error running mpd binary" );
    return;
  }

  my $primer = MPD::Primer->new( $primerPt->stringify );
  if ( !$self->RunIsPcr ) {
    return $primer;
  }

  my $isPcr = MPD::isPcr->new(
    {
      PrimerFile       => $primerPt->stringify,
      PrimerFileFormat => 'mpp',
      isPcrBinary      => $self->isPcrBinary,
      TwoBitFile       => $self->TwoBitFile,
      OutFile          => $isPcrPt->stringify,
    }
  );
  if ( !$isPcr->Run() ) {
    return;
  }

  my %badPrimers;

  # Remove Degenerate primers
  my $psl     = MPD::Psl->new( $isPcrPt->stringify );
  my $dupAref = $psl->DegenerateMatches();
  $badPrimers{$_}++ for @$dupAref;

  # remove duplicates sometimes introduced by the design process
  my $primerObj = MPD::Primer->new( $primerPt->stringify );
  $dupAref = $primerObj->DuplicatePrimers();
  $badPrimers{$_}++ for @$dupAref;

  if ( !%badPrimers ) {
    return $primerObj;
  }
  return $primerObj->RemovePrimers( [ sort keys %badPrimers ] );
}

__PACKAGE__->meta->make_immutable;

1;
