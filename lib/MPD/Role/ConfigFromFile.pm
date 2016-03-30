use 5.10.0;
use strict;
use warnings;

package MPD::Role::ConfigFromFile;

our $VERSION = '0.001';

# ABSTRACT: A moose role for configuring a class from a YAML file
# VERSION

use Moose::Role 2;
use MooseX::Types::Path::Tiny qw/ Path /;

use Carp qw/ croak /;
use namespace::autoclean;
use Data::Dump qw/ dump /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Scalar::Util qw/ reftype /;
use Path::Tiny;
use YAML::XS qw/ Load /;

sub new_with_config {
  state $check = compile( Str, HashRef );
  my ( $class, $optsHref ) = $check->(@_);

  my $configfile = $optsHref->{configfile};

  # check we have a config file
  if ( !defined $configfile ) {
    my $msg = "new_with_config() expects configfile";
    croak $msg;
  }

  # check we get data from the config file
  my $fileOptsHref = $class->get_config_from_file($configfile);
  if ( !defined $fileOptsHref ) {
    my $msg = "Error processing config file: $configfile";
    croak $msg;
  }

  # add options to existing optHref
  for my $opt ( keys %$fileOptsHref ) {
    if ( exists $optsHref->{$opt} ) {
      my $msg =
        "'$opt' exists in href and configfile passed to 'new_with_config()': Ignoring configfile value.";
      say $msg;
    }
    else {
      $optsHref->{$opt} = $fileOptsHref->{$opt};
    }
  }

  # print options for building class, if needed
  if ( $optsHref->{debug} ) {
    say "Data for Role::ConfigFromFile::new_with_config()";
    say dump($optsHref);
  }

  $class->new($optsHref);
}

sub get_config_from_file {
  state $check = compile( Str, Str );
  my ( $class, $file ) = @_;
  my $txt = path($file)->slurp_raw();
  return Load($txt);
}

no Moose::Role;

1;
