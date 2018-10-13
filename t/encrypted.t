use strict;
use warnings;

use Test::More;
use CloudStore;
use CloudStore::Encrypted;
use File::Temp;

my @drivers;
push @drivers, {
  name => 'Mock'
};

push @drivers, {
  name      => 'Dropbox',
  conn_info => { access_token => $ENV{'DROPBOX_ACCESS_TOKEN'} },
} if eval "require CloudStore::Driver::Dropbox; 1";

push @drivers, {
  name      => 'RackspaceCloudFiles',
  conn_info => { 
    user => $ENV{'RACKSPACE_CLOUDFILES_USER'},
    key  => $ENV{'RACKSPACE_CLOUDFILES_KEY'}, 
  },
} if eval "require CloudStore::Driver::RackspaceCloudFiles; 1";

foreach my $driver (@drivers) {
  my $key_hex = '0123456789abcdef0123456789abcdef';
  my $data    = 'Hello cryptic world! o_O' . join '', map { chr($_) } 0..255; # Text plus one byte from 0-255

  my $cs = CloudStore::Encrypted->new(driver => $driver->{name}, key_hex => $key_hex);
  $cs->connect(%{$driver->{conn_info}||{}});
  $cs->create_folder("test-$$-encrypted-folder");
  $cs->upload(\$data => "/test-$$-encrypted-folder/data.txt.enc");

  my $data_copy;
  $cs->download("/test-$$-encrypted-folder/data.txt.enc" => \$data_copy);

  ok(
    $data eq $data_copy,
    "The decrypted data is the same as original after upload/download (using scalars)"
  );

  # Create a tempfile
  $data = reverse $data;
  my $fh_beg = File::Temp->new;
  my $fh_end = File::Temp->new;
  print $fh_beg $data;
  seek $fh_beg, 0, 0;

  $cs->upload($fh_beg => "/test-$$-encrypted-folder/data-r.txt.enc");
  $cs->download("/test-$$-encrypted-folder/data-r.txt.enc" => $fh_end);
  seek $fh_end, 0, 0;
  $data_copy = join '', <$fh_end>;
  ok(
    $data eq $data_copy,
     "The decrypted data is the same as original after upload/download (using file handles)"
  );  
}

done_testing();
