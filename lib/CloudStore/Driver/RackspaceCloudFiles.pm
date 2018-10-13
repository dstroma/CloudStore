use strict;
use warnings;

package CloudStore::Driver::RackspaceCloudFiles;
use Role::Tiny::With;
with 'CloudStore::Role::Driver';

use experimental 'signatures';
use Carp qw(croak confess);
use Scalar::Util qw/blessed/;
use Try::Tiny;

CloudStore->_register_driver('RackspaceCloudFiles');

=pod

Notes on Rackspace CloudFiles:
 - Folders are called "containers"
 - Containers cannot be nested
 - Container names 
   - cannot exceed 256 bytescontain:
   - cannot contain / (forward slash), ? (question mark), or . (dot).
 - Object names
   - cannot exceed 1024 bytes
   - have no character restrictions


=cut

sub connect ($self, %params) {
  require WebService::Rackspace::CloudFiles;
  $self->{'_cf'} = WebService::Rackspace::CloudFiles->new(
    user => delete $params{'username'},
    key  => delete $params{'key'},
    %params,
  );
  #warn "the cf object is " . $self->{'_cf'};
  #use Data::Dumper; warn Dumper $self->{'_cf'};
  #warn "the cf object total bytes used is " . $self->{'_cf'}->total_bytes_used;
  $self;
}

sub download ($self, $remote, $local) {
  my ($remote_contname, $remote_filename) = _parse_remote_path($remote);

  my $cf   = $self->{'_cf'};
  my $cont = $cf->container(name => $remote_contname);
  my $obj  = $cont->object(name => $remote_filename);

  if (not ref $local) {
    return $obj->get_filename($local);
  } elsif (ref $local eq 'SCALAR') {
    return $$local = $obj->get;
  } else {
    return print $local $obj->get;
  }
}

sub upload ($self, $local, $remote) {
  my ($remote_contname, $remote_filename) = _parse_remote_path($remote);

  my $cf   = $self->{'_cf'};
  my $cont = $cf->container(name => $remote_contname);
  my $obj  = $cont->object(name => $remote_filename);

  if (not ref $local) {
    return $obj->put_filename($local);
  } elsif (ref $local eq 'SCALAR') {
    return $obj->put($$local);
  } else {
    return $obj->put(join '', <$local>);
  }
}

sub find {
  my $self = shift;
  if (@_ == 1) {
    my $path_orig = shift;
    my ($path, $file) = _parse_remote_path($path_orig);
    my $success;
    my $file_obj;
    try {
      my $cont = $self->{'_cf'}->container(name => $path);
      $file_obj = $cont->object(name => $file);
      $file_obj->head;
      die "file not found" unless $file_obj->last_modified;
      $success = 1;
    };
    return undef unless $success;
    return $self->make_file_object($file_obj);
  }

  my %params = @_;
  my $folder  = $params{'in'} // $params{'folder'} // $params{'container'};
  my $prefix  = $params{'prefix'};
  my $pattern = $params{'pattern'};

  my %maybe_prefix = ();
  $maybe_prefix{prefix} = $prefix if defined $prefix and length $prefix;

  my $cf     = $self->{'_cf'};
  my $cont   = $cf->container(name => $folder);
  my @obs    = $cont->objects(%maybe_prefix)->all;

  @obs = map { $self->make_file_object($_) } @obs;

  if (defined $pattern) {
    @obs = grep { $_->name =~ $pattern } @obs;
  }

  return wantarray ? @obs : \@obs;
}

sub create_folder ($self, $name) {
  my $cf = $self->{'_cf'};
  $name = substr($name, 1) if substr($name, 0, 1) eq '/';
  $cf->create_container(name => $name);
}

sub get_folders ($self) {
  my $cf     = $self->{'_cf'};
  my @containers = $cf->containers;
  #use Data::Dumper; warn Dumper \@containers;
  return map { $_->{name} } @containers;
}

sub delete_folder ($self, $name) {
  my $cf   = $self->{'_cf'};
  $name = substr($name, 1) if substr($name, 0, 1) eq '/';
  my $cont = $cf->container(name => $name);
  $cont->delete;
  1;
}

sub delete_file ($self, $remote) {
  my ($remote_contname, $remote_filename) = _parse_remote_path($remote);
  my %params = @_ if @_ > 0 and @_ % 2 == 0;

  # Shortcut by supplying a file object instead
  if (
    $params{file} 
    and ref $params{file}
    and blessed $params{file}
    and $params{file}->can('original')
    and $params{file}->original
    and ref $params{file}->original
    and blessed $params{file}->original
    and $params{file}->original->can('delete')
  ) {
    $params{'file'}->original->delete;
    return 1;
  } 

  my $cf   = $self->{'_cf'};
  my $cont = $cf->container(name => $remote_contname);
  my $obj  = $cont->object(name => $remote_filename);
  $obj->delete;
  1;
}

sub make_file_object ($self, $orig) {
  require CloudStore::File;
  return CloudStore::File->new(
    original      => $orig,
    name          => $orig->name,
    last_modified => $orig->last_modified
  );
}

sub _parse_remote_path ($path) {
  if (ref $path and ref $path eq 'ARRAY') {
    return @$path;
  } elsif (ref $path and ref $path eq 'HASH') {
    return ($path->{'container'}, $path->{'name'});
  } elsif (ref $path) {
    confess "Unexpected path $path";
  } else {
    $path = substr($path, 1) if substr($path, 0, 1) eq '/';
    return split('/', $path, 2);
  }
}

1;

__END__

=head1 METHODS


