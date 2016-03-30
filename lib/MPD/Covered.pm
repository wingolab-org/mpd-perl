package MPD::Covered;

# ABSTRACT: This package manipulates MPD-designed primers.

use 5.10.0;

use Moose 2;
use namespace::autoclean;

use Carp qw/ croak /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Scalar::Util qw/ looks_like_number reftype /;

use Data::Dump qw/ dump /; # for debugging

our $VERSION = '0.001';

has Covered => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => 'ArrayRef[MPD::Bed::Covered]',
  handles => {
    all_entries   => 'elements',
    no_entries    => 'is_empty',
    count_entries => 'count',
  },
  default => sub { [] },
);

sub Entries_as_aref {
  my $self = shift;

  my @array;

  for my $e ( $self->all_entries ) {
    if ( !@array ) {
      push @array, $e->Attributes();
    }
    push @array, $e->as_aref;
  }
  return \@array;
}

sub Entries_as_str {
  my $self = shift;

  my @strs;

  my $entriesAref = $self->Entries_as_aref();

  my $line = 0;
  for my $e (@$entriesAref) {
    if ( $line == 0 ) {
      push @strs, join( "\t", @$e );
    }
    else {
      my $line = "chr" . join( "\t", @$e );
      push @strs, $line;
    }
    $line++;
  }
  return join( "\n", @strs );
}

# PercentBasesCovered() calculates the %bases in the covered object with the
# name "covered"; pass a bedObj to restrict counting to a set of sites
sub PercentBasesCovered {
  state $check = compile( Object, Optional [Object] );
  my ( $self, $bedObj ) = $check->(@_);

  my %hash;

  if ( !defined $bedObj ) {
    for my $c ( $self->all_entries ) {
      $hash{ $c->Name } += $c->Size;
    }
  }
  else {
    for my $c ( $self->all_entries ) {
      for ( my $i = $c->Start; $i <= $c->End; $i++ ) {
        my $site = join ":", $c->Chr, $i;
        if ( $bedObj->exists_site($site) ) {
          $hash{covered}{ $c->Name } += 1;
        }
        else {
          $hash{uncovered}{ $c->Name } += 1;
        }
      }
    }
  }
  say dump(%hash);

  if ( !%hash ) {
    return 0;
  }
  return \%hash;
}

sub PercentCovered {
  state $check = compile( Object, Num );
  my ( $self, $threshold ) = $check->(@_);

  my ( $coveredCount, $entryCount ) = ( 0, 0 );
  for my $c ( $self->all_entries ) {
    if ( $c->PercentCovered > $threshold ) {
      $coveredCount++;
    }
    $entryCount++;
  }
  if ( $entryCount == 0 ) {
    return 0;
  }
  else {
    say "$coveredCount / $entryCount";
    return $coveredCount / $entryCount;
  }
}

# BUILDARGS takes either a hash reference or string, which is a primer file
sub BUILDARGS {
  my $class = shift;

  if ( scalar @_ == 1 ) {
    if ( !reftype( $_[0] ) ) {
      my $msg =
        "Error: MPD::Covered object is built with either a hashref, arrayref of MPD::Bed::Covered Objects";
      croak($msg);
    }
    elsif ( reftype( $_[0] ) eq "ARRAY" ) {
      return $class->SUPER::BUILDARGS( { Covered => $_[0] } );
    }
    elsif ( reftype( $_[0] ) eq "HASH" ) {
      return $class->SUPER::BUILDARGS( $_[0] );
    }
    else {
      my $msg =
        "Error: MPD::Covered object is built with either a hashref, arrayref of MPD::Bed::Covered Objects";
      croak($msg);
    }
  }
  else {
    my $msg =
      "Error: Construct MPD::Primer object with either a hashref, arrayref of hashrefs, or primer file";
    croak($msg);
  }
}

__PACKAGE__->meta->make_immutable;

1;

