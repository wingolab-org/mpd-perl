package MPD::Bed;

# ABSTRACT: This package manipulates Bed Files

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

use Data::Dump qw/ dump /; # for debugging

use MPD::Bed::Raw;

our $VERSION = '0.001';

has BedFile => ( is => 'ro', isa => AbsPath, coerce => 1 );
has Entries => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => 'ArrayRef[MPD::Bed::Raw]',
  handles => {
    all_entries   => 'elements',
    no_entires    => 'is_empty',
    count_entries => 'count',
  },
  default => sub { [] },
);

has CoveredChr => (
  traits  => ['Hash'],
  is      => 'ro',
  isa     => 'HashRef',
  handles => {
    exists_chr => 'exists',
    all_chrs   => 'keys',
    get_chr    => 'get',
    no_chrs    => 'is_empty',
    count_chrs => 'count',
  },
  default => sub { {} },
);

has CoveredSite => (
  traits  => ['Hash'],
  is      => 'ro',
  isa     => 'HashRef',
  handles => {
    exists_site => 'exists',
    all_sites   => 'keys',
    get_site    => 'get',
    no_sites    => 'is_empty',
    count_sites => 'count',
  },
  default => sub { {} },
);

sub Entries_as_BedFileLetter {
  my $self = shift;

  my @strs;

  my $entriesAref = $self->Entries_as_aref();

  for my $e (@$entriesAref) {
    my $line;
    if ( $e->[0] == 23 ) {
      $line = "chr", join "\t", ( 'M', @{ $e->[ 1 .. $#{$e} ] } );
    }
    elsif ( $e->[0] == 24 ) {
      $line = "chr", join "\t", ( 'X', @{ $e->[ 1 .. $#{$e} ] } );
    }
    elsif ( $e->[0] == 25 ) {
      $line = "chr", join "\t", ( 'Y', @{ $e->[ 1 .. $#{$e} ] } );
    }
    else {
      my $line = "chr" . join( "\t", @$e );
    }
    push @strs, $line;
  }
  return join( "\n", @strs );
}

sub Entries_as_BedFile {
  my $self = shift;

  my @strs;

  my $entriesAref = $self->Entries_as_aref();
  for my $e (@$entriesAref) {
    my $line = "chr" . join( "\t", @$e );
    push @strs, $line;
  }
  return join( "\n", @strs );
}

sub Entries_as_BedFileLetter {
  my $self = shift;

  my @strs;

  my $entriesAref = $self->Entries_as_aref();
  for my $e (@$entriesAref) {
    if ( $e->[0] == 23 ) {
      $e->[0] = "M";
    }
    elsif ( $e->[0] == 24 ) {
      $e->[0] = "X";
    }
    elsif ( $e->[0] == 25 ) {
      $e->[0] = "Y";
    }
    my $line = "chr" . join( "\t", @$e );
    push @strs, $line;
  }
  return join( "\n", @strs );
}

sub Entries_as_aref {
  my $self = shift;

  my @array;

  for my $e ( $self->all_entries ) {
    push @array, $e->as_aref;
  }
  return \@array;
}

# SiteNames gives a hash ref of all sites in the bed object and their
# corresponding names
sub SiteNames {
  my $self = shift;

  my %hash;

  for my $e ( $self->all_entries ) {
    my $chr = $e->Chr;
    for ( my $i = $e->Start; $i <= $e->End; $i++ ) {
      my $site = join ":", $chr, $i;
      $hash{$site} = $e->Name;
    }
  }
  return \%hash;
}

# _processBedFile returns a matrix of the bedfile coordinates
sub _processBedFile {
  state $check = compile( Str, Str );
  my ( $class, $bedFile ) = $check->(@_);

  my @array;

  my @lines = path($bedFile)->lines( { chomp => 1 } );
  for my $line (@lines) {
    my @fields = split /\t/, $line;
    my ( $chr, $start, $stop, $name ) = @fields;

    if ( defined $chr && defined $start && defined $stop ) {
      if ( !defined $name ) {
        $name = sprintf( "%s:%d-%d", $chr, $start, $stop );
      }

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

      try {
        my $b = MPD::Bed::Raw->new(
          {
            Chr   => $chr,
            Start => $start,
            End   => $stop,
            Name  => $name,
          }
        );
        push @array, $b;
      }
      catch {
        my $msg = "In bedfile, '$bedFile', ignoring line: $line";
        say $msg;
      };

    }
    else {
      my $msg = sprintf( "Error Bedfile missing chr, start, or stop: %s", $line );
    }
  }
  return $class->_processBedObjs( \@array );
}

# _processBedObjs returns a matrix of the bedfile coordinates
sub _processBedObjs {
  state $check = compile( Str, ArrayRef );
  my ( $class, $bedObjAref ) = $check->(@_);

  my %sites;

  for my $b (@$bedObjAref) {
    my $chr = $b->Chr;
    for ( my $i = $b->Start; $i <= $b->End; $i++ ) {
      $sites{$chr}{$i} = $b->Name;
    }
  }
  return $class->_bedSites( \%sites );
}

# _bedSites takes a hash of sites and creates a unique bedfile as an arrayref
sub _bedSites {
  state $check = compile( Str, HashRef );
  my ( $class, $sitesHref ) = $check->(@_);

  my ( %coveredSite, %coveredChr, @bed );
  my @chrs = ( 1 .. 26, 'M', 'X', 'Y' );

  for my $chr (@chrs) {
    if ( exists $sitesHref->{$chr} ) {
      $coveredChr{$chr} = 1;
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
        my $name  = $sitesHref->{$chr}{ $boundaries[$i] };
        my $entry = MPD::Bed::Raw->new(
          {
            Chr   => $chr,
            Start => $boundaries[$i],
            End   => $boundaries[ $i + 1 ],
            Name  => $name,
          }
        );
        push @bed, $entry;

        # assign covered sites
        for ( my $pos = $boundaries[$i]; $pos < $boundaries[ $i + 1 ]; $pos++ ) {
          my $site = join ":", $chr, $pos;
          $coveredSite{$site} = $name;
        }
      }
    }
  }
  return ( \@bed, \%coveredChr, \%coveredSite );
}

# BUILDARGS takes either a hash reference or string, which is a primer file
sub BUILDARGS {
  my $class = shift;

  if ( scalar @_ == 1 ) {
    if ( !reftype( $_[0] ) ) {
      # assumption is that you passed a file be read and used to create
      # recall, reftype returns undef for string values

      my $file = $_[0];
      my ( $bedAref, $coveredChrHref, $coveredSitesHref ) = $class->_processBedFile($file);
      return $class->SUPER::BUILDARGS(
        {
          BedFile     => $file,
          Entries     => $bedAref,
          CoveredSite => $coveredSitesHref,
          CoveredChr  => $coveredChrHref,
        }
      );
    }
    elsif ( reftype( $_[0] ) eq "ARRAY" ) {
      my $bedObjsAref = $_[0];
      my ( $bedAref, $coveredChrHref, $coveredSitesHref ) =
        $class->_processBedObjs($bedObjsAref);
      return $class->SUPER::BUILDARGS(
        {
          Entries     => $bedAref,
          CoveredSite => $coveredSitesHref,
          CoveredChr  => $coveredChrHref,
        }
      );
    }
    elsif ( reftype( $_[0] ) eq "HASH" ) {
      return $class->SUPER::BUILDARGS( $_[0] );
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

__PACKAGE__->meta->make_immutable;

1;
