use strict;
use warnings;
use v5.14;
package CloudStore;

our $VERSION = 0.04;
use Carp qw/croak/;

sub new {
  my ($class, %params) = @_;
  my $driver_name      = delete $params{driver};

  croak 'No driver specified. Use $class->new(driver => $driver_name).'
    unless defined $driver_name;

  my $driver_class     = $class->load_driver($driver_name);
  my $driver_instance  = bless \%params, $driver_class;
  return bless { driver => $driver_instance }, $class;
}

sub load_driver {
  my ($class, $driver_name) = @_;

  # transform $driver_name to CloudStore::Driver::$driver_name if necessary
  my $driver_class = $driver_name =~ m/^CloudStore::/ ? $driver_name : 'CloudStore::Driver::'.$driver_name;
  return $class->verify_driver($driver_class)
    if eval "use $driver_class; 1";

  # Try another approach in case we're dealing with subclasses
  return $class->verify_driver($driver_name)
    if eval "use $driver_name; 1";

  die "Cannot load driver with name $driver_class or $driver_name: $@";
}

sub verify_driver {
  my ($self_class, $driver_class) = @_;

  croak "$driver_class is not a valid driver"
    unless $driver_class->DOES('CloudStore::Role::Driver');

  return $driver_class;
}

sub driver {
  my $self = shift;
  $self->{driver};
}

# Generate a bunch of trivial methods
no strict 'refs';
for my $method (qw(connect download upload find create_folder delete_folder delete_file)) {
  *{$method} = sub { shift->driver->$method(@_) };
}

1;

__END__

=head1 NAME

CloudStore - Abstraction layer for remote (cloud) file storage services.

=head1 SYNOPSIS

    use CloudStore;
    my $driver = 'Mock';
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

Other than a mock driver for testing, drivers must be installed separately.
Drivers are somewhat simple glue code, usually using preexisting CPAN modules
such as Webservice::Dropbox (in the example of the Dropbox driver), but drivers
could be implemented directly as standalone modules as well.

=head1 TERMINOLOGY

The terms "driver" and "backend" are used throughout this documentation.

Driver refers to the Perl module which implements the CloudStore::Role::Driver
role.

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

    my $cloudstore = CloudStore->new(driver => $driver);

Create a new instance of CloudStore using the driver whose name is given by the
driver parameter. CloudStore will look for a package named
CloudStore::Driver::$driver or just $driver and will load it, checking it to
make sure it "DOES" the role CloudStore::Role::Driver. If the package cannot
be loaded or is not a valid driver, the method dies.

=head2 connect ( @OPTIONS )

    $cloudstore->connect(...);

Connects to the backend. Any parameters such as username, password or key,
secret, and token are passed directly to the driver, so those should be supplied
here. These parameters are specific to each driver. For example,
Mock takes no parameters (or more accurately, will ignore any);
Rackspace::CloudFiles takes a username and password;
Dropbox takes a key, secret, and token.

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

=head2 delete_file ( REMOTE_FILENAME )

    $cloudstore->delete_file('/confidential/secrets.txt');

Deletes a remote file.

=head2 delete_folder ( REMOTE_PATH )

    $cloudstore->delete_folder('/confidential/documents');

Deletes a remote folder.

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
Note that some backends may not permit nested folders.

=head2 delete_folder

Deletes a folder. Whether or not the folder must be empty or first depends upon
the driver and backend. Make no assumptions without checking the driver
documentation.

    $cloudstore->delete_folder('/cars/old');


=head1 AUTHOR

Dondi Michael Stroma, E<lt>dstroma@localE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016-2026 by Dondi Michael Stroma.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.


=cut

