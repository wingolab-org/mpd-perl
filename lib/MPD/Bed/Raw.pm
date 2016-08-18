package MPD::Bed::Raw;

# ABSTRACT: Handles raw bed entry data
# NOTE: Bed entries with start == end will be coerced to start + 1 = end

use 5.10.0;

use Moose 2;
use namespace::autoclean;

our $VERSION = '0.001';

with "MPD::Role::Message";

has Chr   => ( is => 'ro', isa => 'Int', required => 1, );
has Start => ( is => 'ro', isa => 'Int', required => 1, );
has End   => ( is => 'ro', isa => 'Int', required => 1, );
has Name  => ( is => 'ro', isa => 'Str', required => 1, );

my @attrs = qw/ Chr Start End Name /;

around 'End' => sub {
  my $org  = shift;
  my $self = shift;

  # if @_ is empty then we're reading but when it contains
  # data (i.e., $val, $setter, $attr) then just set the val

  if ( !@_ ) {
    my $oldEnd = $self->$org;
    if ( $oldEnd == $self->Start ) {
      return $oldEnd + 1;
    }
    else {
      return $oldEnd;
    }
  }
  else {
    my $val = shift;
    return $self->$org($val);
  }
};

sub Size {
  my $self = shift;
  return $self->End - $self->Start;
}

sub as_aref {
  my $self = shift;
  my @array = map { $self->$_ } @attrs;
  return \@array;
}

sub BUILD {
  my $self = shift;

  if ( $self->Start > $self->End ) {
    my $msg = sprintf( "Error: Bed entry, start > stop: %s:%s-%s",
      $self->Chr, $self->Start, $self->End );
    return $self->log('fatal', $msg);
  }
  if ( $self->Size == 0 ) {
    my $msg = sprintf( "Warn: Bed entry, start == stop: %s:%s-%s",
      $self->Chr, $self->Start, $self->End );
    $self->log('warn', $msg);
  }
}

__PACKAGE__->meta->make_immutable;

1;
