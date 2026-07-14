use strict;
use warnings;
use v5.14;
package CloudStore::Role::Driver;

use Role::Tiny;

requires qw(
  connect
  download
  upload
  find
  create_folder
  delete_folder
  delete_file
);
 
1;

__END__

=head1 NAME

CloudStore::Role::Driver - Driver role for CloudStore drivers.


=head1 SYNOPSIS

    package CloudStore::Driver::MyDriver;
    use Role::Tiny::With;
    with 'CloudStore::Role::Driver';

    sub connect { ... }
    ...


=head1 DESCRIPTION

This module is used by CloudStore drivers. Each CloudStore driver
must consume this role and implement the following methods:

=over 4

=item connect

=item download

=item upload

=item find

=item create_folder

=item delete_folder

=item delete_file

=back

Please see the main CloudStore package for details on how these methods should
operate.

Note that a new() method is not required. CloudStore will create a blessed
hashref style object and bless it into the driver class. The hashref contains
the keys and values passed to CloudStore->new().


=head1 ERROR HANDLING

Serious errors should typically raise exceptions. Minor errors, such as attempt
to delete a file that does not exist, are left up to the driver implementation.

A more rigid specification for error handling may be released in the future.


=head1 AUTHOR, COPYRIGHT, and LICENSE

See CloudStore.pm.


=cut
