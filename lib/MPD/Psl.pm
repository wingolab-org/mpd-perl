package MPD::Psl;

# ABSTRACT: This package manipulates PSL files

use 5.10.0;

use Moose 2;
use namespace::autoclean;

use Path::Tiny;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Scalar::Util qw/ reftype /;

use Data::Dump qw/ dump /; # for debugging

use MPD::Psl::Raw;

with 'MPD::Role::Message';

our $VERSION = '0.001';

has Matches => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => 'ArrayRef[MPD::Psl::Raw]',
  handles => {
    all_matches   => 'elements',
    no_matches    => 'is_empty',
    count_matches => 'count',
  },
  default => sub { [] },
);

sub DegenerateMatches {
  my $self = shift;

  my ( @degenPairs, %hash );

  if ( $self->no_matches ) {
    return $self->log('warn', "No matches to process for DegenerateMatches()");
  }

  for my $m ( $self->all_matches ) {
    push @{ $hash{ $m->qName } }, $m;
  }

  for my $qName ( sort keys %hash ) {
    if ( scalar @{ $hash{$qName} } > 1 ) {
      for my $m ( @{ $hash{$qName} } ) {
        if ( $m->tName !~ m/alt\z/xmi ) {
          push @degenPairs, $qName;
        }
        else {
          my $msg = sprintf( "Warning: unrecognized chromosome '%s' for match: %s",
            $m->tName, $m->qName );
          $self->log('warn', $msg);
        }
      }
    }
  }
  return \@degenPairs;
}

# BUILDARGS takes either a hash reference or string, which is a psl file
sub BUILDARGS {
  my $class = shift;

  if ( scalar @_ == 1 ) {
    if ( !reftype( $_[0] ) ) {
      # assumption is that you passed a file be read and used to create
      # recall, reftype returns undef for string values

      my $file = $_[0];
      my (@matches);
      my @lines = path($file)->lines( { chomp => 1 } );

      for my $line (@lines) {
        my @fields = split /\t/, $line;
        my $m = MPD::Psl::Raw->new( \@fields );
        push @matches, $m;
      }
      return $class->SUPER::BUILDARGS( { Matches => \@matches } );
    }
    elsif ( reftype( $_[0] ) eq "ARRAY" ) {
      my $aref = $_[0];
      my @matches;
      for my $href (@$aref) {
        my $m = MPD::Psl::Raw->new($href);
        push @matches, $m;
      }
      return $class->SUPER::BUILDARGS( { Matches => \@matches } );
    }
    elsif ( reftype( $_[0] ) eq "HASH" ) {
      return $class->SUPER::BUILDARGS( $_[0] );
    }
    else {
      return $class->log('fatal', 'Error: Construct MPD::Primer object with either'
      . ' a hashref, arrayref of hashrefs, or primer file');
    }
  }
  else {
    return $class->log('fatal', 'Error: Construct MPD::Primer object with either'
     .' a hashref, arrayref of hashrefs, or primer file');
  }
}

__PACKAGE__->meta->make_immutable;

1;

