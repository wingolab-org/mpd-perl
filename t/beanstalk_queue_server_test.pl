
#!/usr/bin/env perl

use 5.10.0;
use strict;
use warnings;

use Beanstalk::Client;
use Parallel::ForkManager;
use Cpanel::JSON::XS;
use DDP;
use Getopt::Long;
use File::Basename;
use Log::Any::Adapter;
use Path::Tiny;
use Try::Tiny;
use Hash::Merge::Simple qw/merge/;
use YAML::XS qw/LoadFile/;

use lib './lib';

use MPD;

my $DEBUG = 0;
my $conf  = LoadFile($ARGV[0] || './config/queue.yaml');

# Beanstalk servers will be sharded
my $beanstalkHost = $conf->{beanstalk_host_1};
my $beanstalkPort = $conf->{beanstalk_port_1};

my $configPathBaseDir = "./config/web/";

my $verbose = 1;

my $beanstalk = Beanstalk::Client->new(
  {
    server          => $conf->{beanstalkd}{host} . ':' . $conf->{beanstalkd}{port},
    default_tube    => $conf->{beanstalkd}{tubes}{annotation}{submission},
    connect_timeout => 1,
    encoder         => sub { encode_json( \@_ ) },
    decoder         => sub { @{ decode_json(shift) } },
  }
);

my $beanstalkEvents = Beanstalk::Client->new(
  {
    server          => $conf->{beanstalkd}{host} . ':' . $conf->{beanstalkd}{port},
    default_tube    => $conf->{beanstalkd}{tubes}{annotation}{events},
    connect_timeout => 1,
    encoder         => sub { encode_json( \@_ ) },
    decoder         => sub { @{ decode_json(shift) } },
  }
);

while ( my $job = $beanstalk->reserve ) {

  # Parallel ForkManager used only to throttle number of jobs run in parallel
  # cannot use run_on_finish with blocking reserves, use try catch instead
  # Also using forks helps clean up leaked memory from LMDB_File
  # Unfortunately, parallel fork manager doesn't play nicely with try tiny
  # prevents anything within the try from executing
  my $jobDataHref = decode_json( $job->data );
  say "Trying job";
  p $jobDataHref;

  my ($err, $result);

  try {
    $result = handleJob( $jobDataHref, $job->id );

    say "completed job with queue id " . $job->id;
  }
  catch {
    my $indexOfConstructor = index( $_, "MPD::" );

    if ( ~$indexOfConstructor ) {
      $err = substr( $_, 0, $indexOfConstructor );
    }
    else {
      $err = $_;
    }

    say "job " . $job->id . " failed with $err";
  };

  say "Finished";
  exit(0);
}

sub handleJob {
  my $submittedJob = shift;
  my $queueId      = shift;

  my $failed;

  my $inputHref = coerceInputs( $submittedJob, $queueId );

  say "inputHref is";
  p $inputHref;

  my $dir = path( $inputHref->{OutDir} );

  if ( !$dir->is_dir ) { $dir->mkpath(); }

  my $m = MPD->new_with_config($inputHref);

  say "MPD is ";
  p $m;

  my $result = $m->RunAll();

  return $result;
}

#Here we may wish to read a json or yaml file containing argument mappings
sub coerceInputs {
  my $jobDetailsHref = shift;
  my $queueId        = shift;

  my $inputFilePath = $jobDetailsHref->{inputFilePath};
  my $outputDir     = $jobDetailsHref->{dirs}{out};
  my $outputExt     = $jobDetailsHref->{name};

  my $configFilePath = getConfigFilePath( $jobDetailsHref->{assembly} );

  my $config = LoadFile($configFilePath);

  my $coreHref = $config->{Core};

  ########## Gather basic and advanced options ###################
  my $basic    = $config->{User}{Basic};
  my $advanced = $config->{User}{Advanced};

  my %basicOptions    = map { $_->{name} => $_->{val} } @$basic;
  my %advancedOptions = map { $_->{name} => $_->{val} } @$advanced;

  my $userBasic    = $jobDetailsHref->{options}{Basic};
  my $userAdvanced = $jobDetailsHref->{options}{Advanced};

  my %userBasicOptions    = map { $_->{name} => $_->{val} } @$userBasic;
  my %userAdvancedOptions = map { $_->{name} => $_->{val} } @$userAdvanced;

  # right hand precedence;

  my $mergedConfig =
    merge( $coreHref, \%basicOptions, \%advancedOptions, \%userBasicOptions,
    \%userAdvancedOptions );

  # JSON::PP::Boolean will not pass moose constraint for Bool
  foreach my $val ( values %$mergedConfig ) {
    if ( ref $val eq 'JSON::PP::Boolean' ) {
      $val = !!$val;
    }
  }

  $mergedConfig->{publisher} = {
    server      => $conf->{beanstalkd}{host} . ':' . $conf->{beanstalkd}{port},
    queue       => $conf->{beanstalkd}{tubes}{annotation}{events},
    messageBase => {
      event   => 'progress',
      queueId => $queueId,
      data    => undef,
    },
  };

  $mergedConfig->{configfile}  = $configFilePath;
  $mergedConfig->{BedFile}     = $jobDetailsHref->{inputFilePath};
  $mergedConfig->{OutExt}      = $jobDetailsHref->{name};
  $mergedConfig->{OutDir}      = $jobDetailsHref->{dirs}{out};
  $mergedConfig->{ProjectName} = $jobDetailsHref->{name};

  # need to compress so web can get a single file to download
  $mergedConfig->{compress} = 1;

  return $mergedConfig;
}

# {
#   configfile  => $config_file,
#   BedFile     => $bed_file,
#   OutExt      => $out_ext,
#   OutDir      => $dir,
#   InitTmMin   => 58,
#   InitTmMax   => 61,
#   PoolMin     => $poolMin,
#   Debug       => $verbose,
#   IterMax     => 2,
#   RunIsPcr    => 0,
#   Act         => $act,
#   ProjectName => $out_ext,
#   FwdAdapter  => 'ACACTGACGACATGGTTCTACA',
#   RevAdapter  => 'TACGGTAGCAGAGACTTGGTCT',
#   Offset      => 0,
#   Randomize   => 1,
#   a => 1
# }

sub getConfigFilePath {
  my $assembly = shift;

  my @maybePath =
    glob( path($configPathBaseDir)->child($assembly . ".y*ml")->stringify );

  if ( scalar @maybePath ) {
    if ( scalar @maybePath > 1 ) {
      #should log
      say "\n\nMore than 1 config path found, choosing first";
    }

    return $maybePath[0];
  }

  die "\n\nNo config path found for the assembly $assembly. Exiting\n\n";
}
