use strict;
use warnings;

package CloudStore::Driver::Mock;
use Role::Tiny::With;
with 'CloudStore::Role::Driver';

use Carp qw/confess confess/;
use Scalar::Util qw/blessed reftype/;

CloudStore->_register_driver('Mock');

our $storage = {};

sub connect {
  my $self = shift;
  confess "$self is not me" unless ref $self and blessed $self and $self->isa(__PACKAGE__);
  1;
}

sub upload {
  my ($self, $local, $remote) = @_;
  my ($path, $filename) = _parse_remote_path($remote);

  confess "Remote path $path does not exist." if not exists $storage->{$path};
  confess "Remote path $path is not a directory." if not ref $storage->{$path};
  confess "Remote path $remote already exists." if exists $storage->{$path}->{$filename};

  if (not ref $local) {
    open my $fh, '<', $local or confess "Cannot open $local: $!";
    $storage->{$path}->{$filename} = join '', <$fh>;
    close $fh;
    return 1;
  }

  if (ref $local and ref $local eq 'SCALAR') {
    $storage->{$path}->{$filename} = $$local;
    return 1;
  } 

  if (ref $local and reftype $local eq 'GLOB') {
    $storage->{$path}->{$filename} = join '', <$local>;
    return 1;
  }

  confess "Upload from $local: expected filehandle, filename or scalar ref.";
}

sub download {
  my ($self, $remote, $local) = @_;
  my ($path, $filename) = _parse_remote_path($remote);

  confess "Remote path $path does not exist." if not exists $storage->{$path};
  confess "Remote path $path is not a directory." if not ref $storage->{$path};
  confess "Remote file $remote does not exist." if not exists $storage->{$path}->{$filename};
  confess "Remote file $remote is a directory." if ref $storage->{$path}->{$filename};

  if (not ref $local) {
    open my $fh, '>', $local or confess "Cannot open $local: $!";
    print $fh $storage->{$path}->{$filename};
    close $fh;
    return 1;
  }

  if (ref $local and ref $local eq 'SCALAR') {
    $$local = $storage->{$path}->{$filename};
    return 1;
  }

  if (ref $local and reftype $local eq 'GLOB') {
    print $local $storage->{$path}->{$filename};
    return 1;
  }

  confess "Download from $local: expected filehandle, filename or scalar ref.";
}

sub find {
  my $self = shift;
  if (@_ == 1) {
    my $full_filepath = shift;
    my ($path, $file) = _parse_remote_path($full_filepath);
    confess "Remote path $path does not exist."
      if not exists $storage->{$path};
    return $self->make_file_object($path, $file)
      if exists $storage->{$path}->{$file};
    return undef;
  }

  my %params  = @_;
  my $path    = $params{in};
  my $prefix  = $params{prefix};
  my $pattern = $params{pattern};

  $path = '/'.$path if substr($path, 0, 1) ne '/';

  confess "Remote path $path does not exist." if not exists $storage->{$path};
  confess "Remote path $path is not a directory." if not ref $storage->{$path};

  my @results = ();
  foreach my $key (keys %{$storage->{$path}}) {
    if (not defined $prefix or substr($key, 0, length $prefix) eq $prefix) {
      if (not defined $pattern or $key =~ $pattern) {
        push @results, $key;
      }
    }
  }
  return map { $self->make_file_object("$path/$_", $_) } @results;
}

sub create_folder {
  my ($self, $path) = @_;
  $path = '/'.$path if substr($path, 0, 1) ne '/';
  confess "Remote path $path already exists." if exists $storage->{$path};
  $storage->{$path} = {};
  return 1;
}

sub delete_folder {
  my ($self, $path) = @_;
  $path = '/'.$path if substr($path, 0, 1) ne '/';
  confess "Remote path $path does not exist." if not exists $storage->{$path};
  confess "Remote path $path is not a directory." if not ref $storage->{$path};
  delete $storage->{$path};
  return 1;
}

sub delete_file {
  my ($self, $remote) = @_;
  my ($path, $filename) = _parse_remote_path($remote);
  confess "Remote path $path does not exist." if not exists $storage->{$path};
  confess "Remote path $path is not a directory." if not ref $storage->{$path};
  delete $storage->{$path}->{$filename};
  return 1;
}

sub _parse_remote_path {
  my $path = shift;
  $path = substr($path, 1) if substr($path, 0, 1) eq '/';
  my @parts = split '/', $path;
  my $file = pop @parts;
  my $dir  = '/' . join('/', @parts);
  return ($dir, $file);
}

sub make_file_object {
  my ($self, $path, $file) = @_;
  require CloudStore::File;
  return CloudStore::File->new(
    original      => {},
    name          => $file,
    location      => $path,
    last_modified => DateTime->now,
  );
}

1;
