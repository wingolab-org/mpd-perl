package MPD::Seq;

# ABSTRACT: This package is used for sequencing coverage

use 5.10.0;

use Moose 2;
use MooseX::Types::Path::Tiny qw/ AbsPath AbsFile File /;
use namespace::autoclean;

use Carp qw/ croak /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Scalar::Util qw/ reftype /;
use Path::Tiny;
use Try::Tiny;
use IO::Uncompress::Gunzip qw/ $GunzipError /;

use Data::Dump qw/ dump /; # for debugging

use MPD::Bed::Raw;

our $VERSION = '0.001';

has BaseFile => ( is => 'ro', isa => AbsFile, coerce => 1, required => 1, );
has CallProb          => ( is => 'ro', isa => 'Num', required => 1, );
has CoverageThreshold => ( is => 'ro', isa => 'Num', required => 1, );

has Covered => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => 'ArrayRef[MPD::Bed::Raw]',
  handles => {
    all_covered => 'elements',
    no_covered  => 'is_empty',
  },
  default => sub { [] },
);

has Uncovered => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => 'ArrayRef[MPD::Bed::Raw]',
  handles => {
    all_uncovered => 'elements',
    no_uncovered  => 'is_empty',
  },
  default => sub { [] },
);

sub Entries_as_BedFile {
  state $check = compile( Object, Str );
  my ( $self, $type ) = $check->(@_);

  my @strs;

  my $entriesAref = $self->Entries_as_aref($type);

  for my $e (@$entriesAref) {
    my $line = "chr" . join( "\t", @$e );
    push @strs, $line;
  }
  return join( "\n", @strs );
}

sub Entries_as_aref {
  state $check = compile( Object, Str );
  my ( $self, $type ) = $check->(@_);

  $type = lc $type;

  if ( $type eq 'covered' ) {
    my @array;
    for my $e ( $self->all_covered ) {
      push @array, $e->as_aref;
    }
    return \@array;
  }
  elsif ( $type eq 'uncovered' ) {
    my @array;
    for my $e ( $self->all_uncovered ) {
      push @array, $e->as_aref;
    }
    return \@array;
  }
  else {
    my $msg =
      sprintf( "unrecognized type; expected Covered or Uncovered; got: %s", $type );
    croak $msg;
  }
}

# BUILDARGS takes either a hash reference or string, which is a primer file
sub BUILDARGS {
  my $class = shift;

  if ( scalar @_ == 1 ) {
    if ( !reftype( $_[0] ) ) {
      # assumption is that you passed a file be read and used to create
      # recall, reftype returns undef for string values; hard-coded defaults
      # for genotype probability and %covered

      my $href = $class->_ReadBaseFile( $_[0], 0.8, 0.8 );

      # provide other needed attrs
      $href->{CallProb}          = 0.8;
      $href->{CoverageThreshold} = 0.8;
      $href->{BaseFile}          = $_[0];

      return $class->SUPER::BUILDARGS($href);
    }
    elsif ( reftype( $_[0] ) eq "ARRAY" ) {
      my $msg = "passing an ArrayRef to build MPD::Seq is not implemented";
      croak $msg;
    }
    elsif ( reftype( $_[0] ) eq "HASH" ) {
      my $href = $_[0];

      # return if we already have the bedObj created
      if ( exists $href->{Covered} && $href->{Uncovered} ) {
        return $class->SUPER::BUILDARGS($href);
      }

      my @reqAttrs = qw/ CallProb CoverageThreshold BaseFile /;

      for my $attr (@reqAttrs) {
        if ( !exists $href->{$attr} ) {
          my $msg =
            sprintf( "Error: Did not find expected %s in href to build MPD::Seq", $attr );
          croak $msg;
        }
      }

      # make Covered and Uncovered Bed Objects
      my $newHref =
        $class->_ReadBaseFile( $href->{BaseFile}, $href->{CallProb},
        $href->{CoverageThreshold} );

      # give old values to newHref
      $newHref->{$_} = $href->{$_} for (@reqAttrs);

      return $class->SUPER::BUILDARGS($newHref);
    }
    else {
      my $msg = "Error: Construct MPD::Bed object with either a hashref or bed file";
      croak($msg);
    }
  }
  else {
    my $msg = "Error: Construct MPD::Bed object with either a hashref or bed file";
    croak($msg);
  }
}

sub _ReadBaseFile {
  my ( $class, $file, $probThreshold, $coveredThreshold ) = @_;

  my ( @sites, %header, %ids, $idCount );

  my $fh = new IO::Uncompress::Gunzip $file or die "gunzip failed: $GunzipError\n";
  while ( my $line = $fh->getline() ) {
    my @fields = split /\t/, $line;

    if ( !%header ) {
      %header = map { $fields[$_] => $_ } ( 0 .. 2 );
      for ( my $i = 3; $i < @fields; $i += 2 ) {
        $ids{ $fields[$i] } = $i;
      }
      $idCount = scalar keys %ids;
      #say dump ({ ids => \%ids, header => \%header, idCount => $idCount });
    }
    else {
      my %data = map { $_ => $fields[ $header{$_} ] } ( keys %header );
      my ( $covered, $nonNaCount ) = ( 0, 0 );
      for my $id ( sort keys %ids ) {
        my $geno = $fields[ $ids{$id} ];
        my $prob = $fields[ $ids{$id} + 1 ];
        if ( $geno ne 'N' && $prob >= $probThreshold ) {
          $nonNaCount++;
        }
      }

      my $chr = $data{Fragment};
      $chr =~ s/\Achr//xmi;
      if ( $chr eq 'M' ) {
        $chr = 23;
      }
      elsif ( $chr eq 'X' ) {
        $chr = 24;
      }
      elsif ( $chr eq 'Y' ) {
        $chr = 25;
      }

      # determine whether the site was covered (i.e., some samples were
      # covered at or above some threshold)
      try {
        my $percentIdSeq = $nonNaCount / $idCount;
        if ( $percentIdSeq >= $coveredThreshold ) {
          $covered = 1;
        }
        else {
          $covered = 0;
        }
      }
      catch {
        my $msg = sprintf( "error determining percent covered for site %s:%d: %s",
          $chr, $data{Position}, $_ );
        croak $msg;
      };
      push @sites, [ $chr, $data{Position}, $data{Reference}, $covered ];
    }
  }
  return $class->_processSites( \@sites );
}

sub _processSites {
  my ( $class, $sitesAref ) = @_;

  my %sites;

  for my $s (@$sitesAref) {
    my ( $chr, $pos, $ref, $covered ) = @$s;
    if ( $covered == 1 ) {
      $sites{$chr}{$pos} = 1;
    }
  }
  my $coveredBedAref = $class->_makeBedEntries( \%sites, 'covered' );

  %sites = ();
  for my $s (@$sitesAref) {
    my ( $chr, $pos, $ref, $covered ) = @$s;
    if ( $covered == 0 ) {
      $sites{$chr}{$pos} = 1;
    }
  }
  my $uncoveredBedAref = $class->_makeBedEntries( \%sites, 'uncovered' );

  return { Covered => $coveredBedAref, Uncovered => $uncoveredBedAref };
}

sub _makeBedEntries {
  my ( $class, $sitesHref, $name ) = @_;

  my @bed;

  my @chrs = ( 1 .. 26 );
  for my $chr (@chrs) {
    if ( exists $sitesHref->{$chr} ) {
      my @sites = sort { $a <=> $b } keys %{ $sitesHref->{$chr} };
      my @boundaries = $sites[0];
      for ( my $i = 1; $i < @sites; $i++ ) {
        if ( $sites[ $i - 1 ] != $sites[$i] - 1 ) {
          push @boundaries, $sites[ $i - 1 ], $sites[$i];
        }
      }
      push @boundaries, $sites[$#sites];

      # assign bed entries
      for ( my $i = 0; $i < @boundaries; $i += 2 ) {
        my $entry = MPD::Bed::Raw->new(
          {
            Chr   => $chr,
            Start => $boundaries[$i],
            End   => $boundaries[ $i + 1 ],
            Name  => $name,
          }
        );
        push @bed, $entry;
      }
    }
  }
  return \@bed;
}

__PACKAGE__->meta->make_immutable;

1;

