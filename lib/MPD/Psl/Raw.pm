package MPD::Psl::Raw;

# ABSTRACT: This package manipulates PSL files

use 5.10.0;

use Moose 2;
use namespace::autoclean;

use Carp qw/ croak /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Scalar::Util qw/ reftype /;

use Data::Dump qw/ dump /; # for debugging

our $VERSION = '0.001';

has matches     => ( is => 'ro', isa => 'Str', required => 1, );
has misMatches  => ( is => 'ro', isa => 'Str', required => 1, );
has repMatches  => ( is => 'ro', isa => 'Str', required => 1, );
has nCount      => ( is => 'ro', isa => 'Str', required => 1, );
has qNumInsert  => ( is => 'ro', isa => 'Str', required => 1, );
has qBaseInsert => ( is => 'ro', isa => 'Str', required => 1, );
has tNumInsert  => ( is => 'ro', isa => 'Str', required => 1, );
has tBaseInsert => ( is => 'ro', isa => 'Str', required => 1, );
has strand      => ( is => 'ro', isa => 'Str', required => 1, );
has qName       => ( is => 'ro', isa => 'Str', required => 1, );
has qSize       => ( is => 'ro', isa => 'Str', required => 1, );
has qStart      => ( is => 'ro', isa => 'Str', required => 1, );
has qEnd        => ( is => 'ro', isa => 'Str', required => 1, );
has tName       => ( is => 'ro', isa => 'Str', required => 1, );
has tSize       => ( is => 'ro', isa => 'Str', required => 1, );
has tStart      => ( is => 'ro', isa => 'Str', required => 1, );
has tEnd        => ( is => 'ro', isa => 'Str', required => 1, );
has blockCount  => ( is => 'ro', isa => 'Str', required => 1, );
has blockSizes  => ( is => 'ro', isa => 'Str', required => 1, );
has qStarts     => ( is => 'ro', isa => 'Str', required => 1, );
has tStarts     => ( is => 'ro', isa => 'Str', required => 1, );

my @attrs = qw/ matches misMatches repMatches nCount qNumInsert qBaseInsert
  tNumInsert tBaseInsert strand qName qSize qStart qEnd tName tSize tStart
  tEnd blockCount blockSizes qStarts tStarts /;

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

sub BUILDARGS {
  my $class = shift;

  if ( scalar @_ == 1 ) {
    if ( !reftype( $_[0] ) ) {
      my $msg = "Cannot construct PSL object: expect hashref or arrayref";
    }
    elsif ( reftype( $_[0] ) eq "ARRAY" ) {
      my $aref = $_[0];
      my %hash;
      for ( my $i = 0; $i < @attrs; $i++ ) {
        my $name = $attrs[$i];
        if ( !defined $name ) {
          my $msg = "Did not find expected field: $name";
          croak $msg;
        }
        elsif ( !defined $aref->[$i] ) {
          my $msg = "Did not find expected data for field: $name";
          croak $msg;
        }
        $hash{$name} = $aref->[$i];
      }
      return $class->SUPER::BUILDARGS( \%hash );
    }
    elsif ( reftype( $_[0] ) eq "HASH" ) {
      return $class->SUPER::BUILDARGS( $_[0] );
    }
    else {
      my $msg = "Cannot construct PSL object: expect hashref or arrayref";
      croak $msg;
    }
  }
  else {
    my $msg = "Cannot construct PSL object: expect hashref or arrayref";
    croak $msg;
  }
}

__PACKAGE__->meta->make_immutable;

1;

