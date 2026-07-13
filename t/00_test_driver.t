use strict;
use warnings;
use Test::More;
use CloudStore::Test::Driver;

CloudStore::Test::Driver::test_driver(
  driver => 'Mock',
  connection_info => {},
  make_plan => 0
);

done_testing();
