package MPD::isPcr;

# ABSTRACT: This package performs isPcr on primer files

use 5.10.0;

use Moose 2;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Tiny qw/ AbsPath AbsFile /;
use namespace::autoclean;

use Path::Tiny;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;

use Data::Dump qw/ dump /; # for debugging

use MPD::Primer;
use MPD::Psl;

with 'MPD::Role::Message';

our $VERSION = '0.001';

enum PrimerFileFormat => [ 'isPcr', 'mpp' ];

has PrimerFile => ( is => 'ro', isa => AbsFile, coerce => 1, required => 1, );
has PrimerFileFormat => ( is => 'ro', isa => 'PrimerFileFormat', required => 1, );
has isPcrBinary => ( is => 'ro', isa => AbsFile, coerce => 1, required => 1, );
has TwoBitFile  => ( is => 'ro', isa => AbsFile, coerce => 1, required => 1, );
has OutFile     => ( is => 'ro', isa => AbsPath, coerce => 1, required => 1, );

sub Run {
  my $self = shift;

  my $cmd;
  my $tempIsPcrPrimerFile = Path::Tiny->tempfile();

  if ( $self->PrimerFileFormat eq 'isPcr' ) {
    $cmd = sprintf( "%s %s %s %s -out=psl",
      $self->isPcrBinary, $self->TwoBitFile, $self->PrimerFile, $self->OutFile );
  }
  elsif ( $self->PrimerFileFormat eq 'mpp' ) {
    my $primer = MPD::Primer->new( $self->PrimerFile->stringify );
    my $ok     = $primer->WriteIsPcrFile( $tempIsPcrPrimerFile->absolute->stringify );
    if ( !$ok ) {
      return;
    }
    if ( $tempIsPcrPrimerFile->is_file ) {
      $cmd = sprintf(
        "%s %s %s %s -out=psl",
        $self->isPcrBinary,              $self->TwoBitFile,
        $tempIsPcrPrimerFile->stringify, $self->OutFile
      );
    }
    else {
      my $msg =
        sprintf( "Error: Failed to write isPcr Primer File: %s", $tempIsPcrPrimerFile );
      $self->log( 'fatal', $msg );
    }
  }
  my $runLog = qx/$cmd/;

  if ( $self->OutFile->is_file ) {
    return 1;
  }
  else {
    $self->log( 'warn', "Error running isPcr" );
    $self->log( 'warn', $runLog );
    return;
  }
}

__PACKAGE__->meta->make_immutable;

1;
