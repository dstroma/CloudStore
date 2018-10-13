package CloudStore;

use strict;
use warnings;
use Carp qw/croak/;

my %drivers;

sub _register_driver {
  my $my_class      = shift;
  my $name          = shift;
  my $driver_class  = caller;

  my $does_role;
  if ($driver_class->can('does') and $driver_class->does('CloudStore::Role::Driver')) {
    $does_role = 1;
  } elsif (Role::Tiny::does($driver_class, 'CloudStore::Role::Driver')) {
    $does_role = 1;
  }
  croak "$driver_class does not do role CloudStore::Role::Driver" unless $does_role;

  $drivers{$name} = $driver_class;
}

sub new {
  my $class  = shift;
  my %params = @_;

  croak "No driver specified" unless exists $params{driver};

  my $driver_name = delete $params{'driver'};
  my $driver_class = $class->load_driver($driver_name);
  my $driver_instance = bless \%params, $driver_class;
  
  my $self = { driver => $driver_instance };
  bless $self, $class;
}

sub load_driver {
  my ($class, $driver_name) = @_;

  return $drivers{$driver_name} if exists $drivers{$driver_name};

  # transform $driver_name to CloudStore::Driver::$driver_name if necessary
  $class = __PACKAGE__; # Bugfix ... subclass of CloudStore still use CloudStore::Driver
  my $driver_class = $driver_name =~ m/^$class/ ? $driver_name : $class.'::Driver::'.$driver_name;

  return $driver_class if eval "require $driver_class; 1";
  #return $driver_name  if eval "require $driver_name; 1";

  die "Cannot load driver with name $driver_class or $driver_name: $@";
}

sub driver {
  my $self = shift;
  $self->{driver};
}

sub connect {
  my $self = shift;
  $self->driver->connect(@_);
}

sub download {
  my $self   = shift;
  $self->driver->download(@_);
}

sub upload {
  my $self   = shift;
  $self->driver->upload(@_);
}

sub find {
  my $self   = shift;
  $self->driver->find(@_);
}

sub create_folder {
  my $self = shift;
  $self->driver->create_folder(@_);
}

sub delete_folder {
  my $self = shift;
  $self->driver->delete_folder(@_);
}

sub delete_file {
  my $self = shift;
  $self->driver->delete_file(@_);
}

1;

__END__

=head1 NAME

CloudStore - Abstraction layer for cloud file storage.

=head1 SYNOPSIS

    use CloudStore;
    use CloudStore::Driver::Mock;
    my $driver = 'Mock'; # or Dropbox, or Rackspace::CloudFiles, ...
    my %conn_options = (); # might need username/key/secret/token/...

    my $cs = CloudStore->new(driver => $driver);
    $cs->connect(%conn_options);
    $cs->download('testdir/testfile.txt' => './testfile.txt');
    $cs->delete_file('testdir/testfile.txt');
    $cs->upload('somefile.txt' => 'testdir/somefile.txt');

=head1 DESCRIPTION

This module is an abstraction layer over various cloud file storage systems,
offering a unified API. Where possible, it attempts to hide differences in
backends, with portability being the goal rather than number of features. For
this reason, the API is somewhat simplistic and lacks such things as ability
to get or set remote file metadata or ability to fetch an old revision of a
file.

Various drivers are supplied out of the box, but you may write your own
as well. Included in the distribution are drivers for Dropbox, Google Drive,
and Rackspace CloudFiles. These drivers are somewhat simple glue code using
preexisting CPAN modules such as Webservice::Dropbox (in the example of the
Dropbox driver), but drivers could be implemented directly as standalone
modules as well.

=head1 TERMINOLOGY

The terms "driver" and "backend" are used throughout this documentation.

Driver refers to the Perl module which implements the CloudStore::Role::Driver
role, and which registers itself with the main CloudStore module. For example,
CloudStore::Driver::Dropbox is the CloudStore driver for Dropbox, and when
loaded registers itself under name, 'Dropbox'.

Backend may refer to the API which is used by the driver. For example, the
Dropbox HTTP/JSON API. It might also refer to a CPAN module used by the driver
to access that API; in the case of the Dropbox driver, this is currently
WebService::Dropbox.

=head1 VARIATIONS IN BACKENDS AND DRIVERS 

There are differences between various backends that this module may not be
able to reconcile. For example:

 - Nested folders not supported
 - Folders not supported at all
 - Limitations on folder names, such as length or allowable characters
 - Limitations on file names, similar to above
 - ...etc...

In some cases, the driver may choose to emulate behavior that is not supported
by the backend.

In all cases, carefully read the documentation for a particular driver before
attempting to use it, to make sure you are made aware of these differences and
limitations.

=head1 METHODS

=head2 new ( driver => DRIVER_NAME )

    my $cloudstore = CloudStore->new(driver => 'Dropbox');

Create a new instance of CloudStore using the driver whose name is given by the
driver parameter. The preferred method is to name a driver whose module has
already been loaded.

The call to new() will first check to see if a driver has been registered with
the given name. If it has not, it attempts a 

    require CloudStore::Driver::DRIVER_NAME

and if that fails, it attempts to

    require DRIVER_NAME.

If that also fails, the method dies.

=head2 connect ( @OPTIONS )

    $cloudstore->connect(...);

Connects to the backend. Any parameters such as username, password or key,
secret, and token are passed directly to the driver, so those should be supplied
here. These parameters are specific to each driver. For example, "Mock" takes
no parameters (or more accurately, will ignore any and all parameters), while
Rackspace CloudFiles takes a username and password while Dropbox takes a
key, secret, and token.

=head2 download ( REMOTE_FILENAME => LOCAL_DESTINATION )

    $cloudstore->download('/files/somefile.zip' => '/zipfiles/somefile.zip');

Downloads a remote file. Use of the fat arrow is recommended as a mnemonic for
remembering the correct order of the parameters.

LOCAL_DESTINATION may be a path to a local file, a filehandle, or a scalar
reference in which to store the file's contents.

=head2 upload ( LOCAL_SOURCE => REMOTE_FILENAME )

    $cloudstore->upload('/home/bob/address_book.db' => '/address_books/bob.db');

Uploads a file. Use of the fat arrow is recommended as a mnemonic for
remembering the correct order of the parameters.

LOCAL_SOURCE may be a local filename, a filehandle, or a scalar reference which
will be dereferenced and used as the content of the upload.

=head2 delete ( REMOTE_FILENAME)

    $cloudstore->delete_file('/confidential/secrets.txt');

Deletes a remote file.

=head2 find ( REMOTE_FILENAME )
=head2 find ( in => FOLDER [, prefix => PREFIX ] [, pattern => PATTERN ] )

    my $file_info  = $cloudstore->find('/cars/audi.jpg');
    my @cars_files = $cloudstore->find(in => '/cars'); 
    my @audi_files = $cloudstore->find(in => '/cars', prefix => 'audi');
    my @car_pics   = $cloudstore->find(in => '/cars', pattern => qr/\.jpg|jpeg$/i);
    my @audi_pics  = $cloudstore->find(in => '/cars', prefix => 'audi', pattern => qr/\.jpg|jpeg$/i);

Find a file by name, or search for files.

The single-argument form of find checks to see if the file given by the argument
exists, and returns a CloudStore::File object if it does. Returns undef if file
does not exist.

The multi-argument form always returns an array. It takes several parameters:
in (required), and prefix and/or pattern, each of which are optional. If only
the in parameter is given, it returns a list of all the files in the folder,
but not other folders. Each element in the list is a CloudStore::File object.

Backend support for file searching varies. The driver might have to fetch all
the file metadata and then do the searching work itself.

Recursive searching is not supported.

=head2 create_folder

    $cloudstore->create_folder('/cars/fast-cars');

Creates a folder, directory, or similar structure as supported by the backend.
Note that some backends do not permit nested folders.

=head2 delete_folder

Deletes a folder. Whether or not the folder must be empty or first depends upon
the driver and backend. Make no assumptions without checking the driver
documentation.

    $cloudstore->delete_folder('/cars/old');


=head1 AUTHOR

Dondi Michael Stroma, E<lt>dstroma@localE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Dondi Stroma


=cut

