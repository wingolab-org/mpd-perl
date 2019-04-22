use 5.10.0;
use strict;
use warnings;
# A class to compress stuff and make temporary directories
package MPD::Role::IO;

our $VERSION = '0.001';

# ABSTRACT: A moose role for all of our file handle needs
# VERSION

use Moose::Role;

use File::Which qw/which/;

use Path::Tiny;
with 'MPD::Role::Message';

state $tar = which('tar');
state $gzip = which('pigz') || which('gzip');
# state $gzip = which('gzip');
$tar = "$tar --use-compress-program=$gzip";

has gzipPath => (
  is => 'ro',
  isa => 'Str',
  init_arg => undef,
  lazy => 1,
  default => sub {$gzip}
);

#if we compress the output, the extension we store it with
has compressExtension => (
  is      => 'ro',
  lazy    => 1,
  default => '.tar.gz',
  init_arg => undef,
);

sub compressPath {
  my $self = shift;
  #expect a Path::Tiny object or a valid file path
  my $fileObjectOrPath = shift;

  if(!$tar) { $self->log( 'fatal', 'No tar program found'); }

  if(!ref $fileObjectOrPath) {
    $fileObjectOrPath = path($fileObjectOrPath);
  }

  my $filePath = $fileObjectOrPath->stringify;

  $self->log( 'info', 'Compressing all output files' );

  my $basename = $fileObjectOrPath->basename;
  my $parentDir = $fileObjectOrPath->parent->stringify;

  my $compressName =
    substr($basename, 0, rindex($basename, ".") ) . $self->compressExtension;

  my $outcome =system(
    sprintf(
      "cd %s; $tar --exclude '.*' --exclude %s -cf %s %s --remove-files",
      $parentDir,
      $compressName,
      $compressName, #and don't include our new compressed file in our tarball
      "$basename*", #the name of the directory we want to compress
    )
  );

  if($outcome) {
    return $self->log( 'warn', "Zipping failed with $?" );
  }

  return $compressName;
}

#http://www.perlmonks.org/?node_id=233023
sub makeRandomTempDir {
  my ($self, $parentDir) = @_;

  srand( time() ^ ($$ + ($$ << 15)) );
  my @v = qw ( a e i o u y );
  my @c = qw ( b c d f g h j k l m n p q r s t v w x z );

  my ($flip, $childDir) = (0,'');
  $childDir .= ($flip++ % 2) ? $v[rand(6)] : $c[rand(20)] for 1 .. 9;
  $childDir =~ s/(....)/$1 . int rand(10)/e;
  $childDir = ucfirst $childDir if rand() > 0.5;

  my $newDir = $parentDir->child($childDir);

  # it shouldn't exist
  if($newDir->is_dir) {
    goto &_makeRandomTempDir;
  }

  $newDir->mkpath;

  return $newDir;
}

no Moose::Role;

1;
