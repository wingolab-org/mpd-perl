package MPD::Bed::Covered;

# ABSTRACT: Coverage of bed entries

#TODO: Rename this Covered::Raw to be consistent with other names

use 5.10.0;

use Moose 2;
use namespace::autoclean;

our $VERSION = '0.001';

has Chr          => ( is => 'ro', isa => 'Int', required => 1, );
has Start        => ( is => 'ro', isa => 'Int', required => 1, );
has End          => ( is => 'ro', isa => 'Int', required => 1, );
has Name         => ( is => 'ro', isa => 'Str', required => 1, );
has Primer       => ( is => 'ro', isa => 'Str', required => 1, );
has CoveredCount => ( is => 'ro', isa => 'Int', required => 1, );

my @attrs = qw/ Chr Start End Name Primer CoveredCount /;

sub Attributes {
  my @expMethods = qw/ PercentCovered Size /;
  return [ @attrs, @expMethods ];
}

sub PercentCovered {
  my $self = shift;

  if ( $self->Size == 0 ) {
    my $msg = "ERROR: size should not be 0, found: " . $self->Size;
    croak $msg;
  }

  # printf( "covered: %f\n", ( $self->CoveredCount / $self->Size ) );
  return $self->CoveredCount / $self->Size;
}

sub Size {
  my $self = shift;
  return $self->End - $self->Start + 1;
}

sub as_aref {
  my $self = shift;
  my @array = map { $self->$_ } @{ $self->Attributes };
  return \@array;
}

sub BUILD {
  my $self = shift;

  if ( $self->Start > $self->End ) {
    my $msg = sprintf( "Error: Bed entry, start > stop: %s:%s-%s",
      $self->Chr, $self->Start, $self->End );
  }
  if ( $self->Size > 2000 ) {
    my $msg = sprintf( "Error: Bed entry, target is >2000bp: %s:%s-%s",
      $self->Chr, $self->Start, $self->End );
  }
  if ( $self->Size == 0 ) {
    my $msg = sprintf( "Error: Bed entry, start == stop: %s:%s-%s",
      $self->Chr, $self->Start, $self->End );
  }
}

__PACKAGE__->meta->make_immutable;

1;

