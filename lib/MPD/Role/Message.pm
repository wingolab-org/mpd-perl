package MPD::Role::Message;
use 5.10.0;
use strict;
use warnings;

our $VERSION = '0.001';

# ABSTRACT: A class for communicating to log and to some plugged in messaging service
# VERSION
use Moose::Role 2;

#doesn't work with Parallel::ForkManager;
#for more on AnyEvent::Log
#http://search.cpan.org/~mlehmann/AnyEvent-7.12/lib/AnyEvent/Log.pm
# use AnyEvent;
# use AnyEvent::Log;
use Carp qw/croak confess/;
use Log::Fast;
use namespace::autoclean;
#with 'MooX::Role::Logger';
use Beanstalk::Client;
use Cpanel::JSON::XS;
use Path::Tiny;

$MPD::Role::Message::LOG = Log::Fast->global();
$MPD::Role::Message::LOG = Log::Fast->new(
  {
    level  => 'WARN',
    prefix => '%D %T ',
    type   => 'fh',
    fh     => \*STDOUT,
  }
);

$MPD::Role::Message::mapLevels = {
  info   => 'INFO',  #\&{$LOG->INFO}
  INFO   => 'INFO',
  ERR    => 'ERR',
  error  => 'ERR',
  fatal  => 'ERR',
  warn   => 'WARN',
  WARN   => 'WARN',
  debug  => 'DEBUG',
  DEBUG  => 'DEBUG',
  NOTICE => 'NOTICE',
};

state $debug = 0;

sub setLogPath {
  my ( $self, $path ) = @_;
  #open($Seq::Role::Message::Fh, '<', $path);
  our $LOG;
  #$AnyEvent::Log::LOG->log_to_file ($path);
  $LOG->config( { fh => path($path)->filehandle(">"), } );
}

sub setLogLevel {
  my ( $self, $level ) = @_;

  our $mapLevels;
  our $LOG;

  if ( $level =~ /debug/i ) {
    $debug = 1;
  }

  $LOG->level( $mapLevels->{$level} );
}

state $verbosity = 0;

sub setVerbosity {
  my ( $self, $level ) = @_;

  $verbosity = $level;
}

my $publisher;
my $messageBase;
has hasPublisher => (
  is       => 'ro',
  init_arg => undef,
  writer   => '_setPublisher',
  isa      => 'Bool',
  lazy     => 1,
  default  => sub { !!$publisher }
);

sub setPublisher {
  my ( $self, $publisherConfig ) = @_;

  if ( !ref $publisherConfig eq 'Hash' ) {
    return $self->log->( 'fatal', 'setPublisherAndAddress requires hash' );
  }

  if (
    !(
         defined $publisherConfig->{server}
      && defined $publisherConfig->{queue}
      && defined $publisherConfig->{messageBase}
    )
    )
  {
    return $self->log( 'fatal', 'setPublisher server, queue, messageBase properties' );
  }

  $publisher = Beanstalk::Client->new(
    {
      server          => $publisherConfig->{server},
      default_tube    => $publisherConfig->{queue},
      connect_timeout => 1,
    }
  );

  $self->_setPublisher( !!$publisher );

  $messageBase = $publisherConfig->{messageBase};
}

# note, accessing hash directly because traits don't work with Maybe types
sub publishMessage {
  # my ( $self, $msg ) = @_;
  # to save on perf, $_[0] == $self, $_[1] == $msg;

  # because predicates don't trigger builders, need to check hasPublisherAddress
  return unless $publisher;

  $messageBase->{data} = $_[1];

  $publisher->put(
    {
      priority => 0,
      data     => encode_json($messageBase),
    }
  );
}

sub publishProgress {
  # my ( $self, $msg ) = @_;
  # to save on perf, $_[0] == $self, $_[1] == $msg;

  # because predicates don't trigger builders, need to check hasPublisherAddress
  return unless $publisher;

  $messageBase->{data} = { progress => $_[1] };

  $publisher->put(
    {
      priority => 0,
      data     => encode_json($messageBase),
    }
  );
}

sub log {
  #my ( $self, $log_method, $msg ) = @_;
  #$_[0] == $self, $_[1] == $log_method, $_[2] == $msg;

  # TODO: auto dump refs
  # if(ref $_[2] ) {
  #   $_[2] = dump $_[2];
  # }

  if ( $_[1] eq 'info' ) {
    $MPD::Role::Message::LOG->INFO("[INFO] $_[2]");

    $_[0]->publishMessage("[INFO] $_[2]");

    if ($verbosity) {
      say STDOUT "[INFO] $_[2]";
    }
  }
  elsif ( $_[1] eq 'debug' && $debug ) {
    $MPD::Role::Message::LOG->DEBUG("[DEBUG] $_[2]");
    # $_[0]->publishMessage("[DEBUG] $_[2]");

    if ($verbosity) {
      say STDOUT "[DEBUG] $_[2]";
    }

  }
  elsif ( $_[1] eq 'warn' ) {
    $MPD::Role::Message::LOG->WARN("[WARN] $_[2]");

    $_[0]->publishMessage("[WARN] $_[2]");

    if ($verbosity) {
      say STDERR "[WARN] $_[2]";
    }

  }
  elsif ( $_[1] eq 'fatal' ) {
    $MPD::Role::Message::LOG->ERR("[FATAL] $_[2]");
    $_[0]->publishMessage("[FATAL] $_[2]");

    confess "[FATAL] $_[2]";
  }

  return;
}

no Moose::Role;
1;
