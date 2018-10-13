use strict;
use warnings;

package CloudStore::Driver::Dropbox;
use Role::Tiny::With;
with 'CloudStore::Role::Driver';

use WebService::Dropbox;
use IO::File;
use DateTime::Format::RFC3339;
use experimental 'signatures';
use List::Util 'maxstr';
use Fcntl qw(SEEK_SET SEEK_END);
use Carp qw(croak confess);
use constant MB => 1024*1024;

CloudStore->_register_driver('Dropbox');

sub connect ($self, %params) {
  my $dropbox = $self->{'_dbox'} = WebService::Dropbox->new({
    key     => delete $params{'key'},
    secret  => delete $params{'secret'},
    %params,
  });
  my $info = $dropbox->get_current_account or die $dropbox->error;
  $self;
}

sub download ($self, $remote, $local) {
  my $_remote = _remote_path_parsed($remote);
  my ($_local, $should_close) = _coerce_to_filehandle('>', $local);

  my $dbox   = $self->{'_dbox'};
  my $result = $dbox->download($_remote, $_local); # ($remotepath, $dest, \%opts)
  close $_local if $should_close;

  # TODO: Parse result. For now just warn
  # warn "Dropbox->download result: $result\n";

  return $result;
}

sub upload ($self, $local, $remote) {
  my $_remote = _remote_path_parsed($remote);
  my ($_local, $should_close) = _coerce_to_filehandle('<', $local);

  my $dbox   = $self->{'_dbox'};

  my $result;
  my $size = _get_fh_size($_local);
  if ($size < 100*MB) {
     $result = $dbox->upload($_remote, $_local, { mode => 'overwrite' });
  } else {
     $result = $dbox->upload_session($_remote, $_local, { mode => 'overwrite' });
  }
  close $_local if $should_close;

  # TODO: Parse result. For now just warn
  # warn "Dropbox->upload result: $result\n";
  return $result;
}

sub find {
  my $self = shift;
  if (@_ == 1) {
    my $path = shift;
    $path = _remote_path_parsed($path);
    my $result = $self->{_dbox}->get_metadata($path);
    if ($result and not $result->{error}) {
      return $self->make_file_object($result);
    } else {
      return undef
    }
  }

  my %params  = @_;
  my $folder  = $params{in};
  my $prefix  = $params{prefix};
  my $pattern = $params{pattern};
  my $dbox    = $self->{'_dbox'};
  my @files   = ();

  $folder = '' if (defined $folder and $folder eq '/');
  $folder = '/'.$folder if length $folder;

  if (!defined $prefix or !length $prefix) {
    my $result = $dbox->list_folder($folder);
    return unless $result and ref $result;
    @files = grep { $_->{'.tag'} eq 'file' } @{$result->{entries}};
  } else {
    my $search = $dbox->search($folder, $prefix, {
      mode  => 'filename',
      start => 0,
      max_results => 200,
    });
    @files = map { $_->{metadata} } @{$search->{matches}};
  }

  @files = grep { $_->{name} =~ $pattern      } @files if defined $pattern;
  @files = map  { $self->make_file_object($_) } @files;
  return wantarray ? @files : \@files;
}

sub create_folder ($self, $name) {
  $self->{'_dbox'}->create_folder(_remote_path_parsed($name));
}

sub delete_folder ($self, $name) {
  $self->delete_folder_or_file($name);
}

sub delete_file ($self, $name) {
  $self->delete_folder_or_file($name);
}

sub delete_folder_or_file ($self, $name) {
  $self->{'_dbox'}->delete(_remote_path_parsed($name));
}

sub make_file_object ($self, $orig) {
  require CloudStore::File;
  return CloudStore::File->new(
    original      => $orig,
    name          => $orig->{name},
    location      => $orig->{path_lower},
    last_modified_inflator => sub {
      DateTime::Format::RFC3339->parse_datetime($orig->{server_modified}),
    },
  );
}

sub _remote_path_parsed ($arg) {
  return $arg if substr($arg, 0, 3) eq 'id:';  # Special Dropbox id
  return $arg if substr($arg, 0, 3) eq 'rev:';

  # Drop box remote paths start with '/'
  $arg = "/$arg" unless substr($arg, 0, 1) eq '/';
  return $arg;
}

sub _coerce_to_filehandle ($mode, $arg) {
  # We expect $local will be a local file path, filehandle, or scalar ref.
  # We need to give back a filehandle.
  my $fh;
  if (not ref $arg or ref $arg eq 'SCALAR') {
    open $fh, $mode, $arg;
    return ($fh, 1);
  }
  return ($arg, 0);
}

sub _get_fh_size ($fh) {
  my $cur_pos = tell($fh);
  seek($fh, 0, SEEK_END);
  my $size = tell($fh);
  seek($fh, $cur_pos, SEEK_SET);
  confess "Unable to get file size: $!" if $cur_pos == -1 or $size == -1;
  return $size;
}
1;
