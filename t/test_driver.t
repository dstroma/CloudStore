use strict;
use warnings;

use Test::More;
use CloudStore::Test::Driver;

my $has_mock        = 1; # it better!
my $has_dropbox     = eval "require CloudStore::Driver::Dropbox; 1" || 0;
my $has_rackspacecf = eval "require CloudStore::Driver::RackspaceCloudFiles; 1" || 0;

plan tests => ($has_mock + $has_dropbox + $has_rackspacecf) * 22;

CloudStore::Test::Driver::test_driver(
  driver => 'Mock',
  connection_info => {},
  make_plan => 0
) if $has_mock;

CloudStore::Test::Driver::test_driver(
  driver => 'Dropbox',
  connection_info => {
    key => $ENV{'DROPBOX_KEY'},
    secret => $ENV{'DROPBOX_SECRET'},
    access_token => $ENV{'DROPBOX_ACCESS_TOKEN'},
  },
  make_plan => 0
) if $has_dropbox;

CloudStore::Test::Driver::test_driver(
  driver => 'RackspaceCloudFiles',
  connection_info => {
    user => $ENV{'RACKSPACE_CLOUDFILES_USER'},
    key => $ENV{'RACKSPACE_CLOUDFILES_KEY'},
  },
  make_plan => 0
) if $has_rackspacecf;
