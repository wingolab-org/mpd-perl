package MPD::Primer::Raw;

# ABSTRACT: This package manipulates MPD-designed primers.

use 5.10.0;

use Moose 2;
use namespace::autoclean;

use Carp qw/ croak /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;

use Data::Dump qw/ dump /; # for debugging

our $VERSION = '0.001';

has Pool                   => ( is => 'ro', isa => 'Str', required => 1, );
has Primer_number          => ( is => 'ro', isa => 'Str', required => 1, );
has Forward_primer         => ( is => 'ro', isa => 'Str', required => 1, );
has Forward_Tm             => ( is => 'ro', isa => 'Str', required => 1, );
has Forward_GC             => ( is => 'ro', isa => 'Str', required => 1, );
has Reverse_primer         => ( is => 'ro', isa => 'Str', required => 1, );
has Reverse_Tm             => ( is => 'ro', isa => 'Str', required => 1, );
has Reverse_GC             => ( is => 'ro', isa => 'Str', required => 1, );
has Chr                    => ( is => 'ro', isa => 'Str', required => 1, );
has Forward_start_position => ( is => 'ro', isa => 'Str', required => 1, );
has Forward_stop_position  => ( is => 'ro', isa => 'Str', required => 1, );
has Reverse_start_position => ( is => 'ro', isa => 'Str', required => 1, );
has Reverse_stop_position  => ( is => 'ro', isa => 'Str', required => 1, );
has Product_length         => ( is => 'ro', isa => 'Str', required => 1, );
has Product_GC             => ( is => 'ro', isa => 'Str', required => 1, );
has Product_tm             => ( is => 'ro', isa => 'Str', required => 1, );
has Product                => ( is => 'ro', isa => 'Str', required => 1, );
has CoveredName            => ( is => 'rw', isa => 'Str', default  => 'NA' );

my @attrs = qw/ Primer_number Forward_primer Forward_Tm Forward_GC Reverse_primer
  Reverse_Tm Reverse_GC Chr Forward_start_position Forward_stop_position Reverse_start_position
  Reverse_stop_position Product_length Product_GC Product_tm Product/;

sub Header {
  my $self = shift;

  return [ 'Name', @attrs ];

}

sub FwdPrimer {
  state $check = compile( Object, Maybe [Str] );
  my ( $self, $adapter ) = $check->(@_);

  my $primer = $adapter . $self->Forward_primer;

  return $primer;
}

sub RevPrimer {
  state $check = compile( Object, Maybe [Str] );
  my ( $self, $adapter ) = $check->(@_);

  my $primer = $adapter . $self->Reverse_primer;

  return $primer;
}

sub Name {
  my $self = shift;
  return sprintf( "primer_%s_%s", $self->Pool, $self->Primer_number );
}

sub Covered {
  my $self = shift;
  my @array =
    ( $self->Chr, $self->Forward_stop_position, $self->Reverse_start_position );
  if (wantarray) {
    return @array;
  }
  elsif ( defined wantarray ) {
    return \@array;
  }
  else {
    my $msg = "Error: Covered() expects to be called in either list or scalar context";
    croak $msg;
  }
}

sub as_href {
  my $self = shift;

  my %hash;

  for my $attr (@attrs) {
    $hash{$attr} = $self->$attr;
  }

  return \%hash;
}

sub as_aref {
  my $self = shift;

  my @array;

  for my $attr (@attrs) {
    push @array, $self->$attr;
  }
  return \@array;
}

__PACKAGE__->meta->make_immutable;

1;

