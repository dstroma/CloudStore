use strict;
use warnings;
use Test::More;
use CloudStore;
use CloudStore::Encrypted;
use File::Temp;
use v5.14;

my @drivers;
push @drivers, {
  name => 'Mock'
};

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

  my $data_copy_raw;
  $cs->download_raw("/test-$$-encrypted-folder/data.txt.enc" => \$data_copy_raw);
  ok(
    $data ne $data_copy_raw,
    "The encrypted data is not equal to the original data"
  );

  ok(
    length $data_copy_raw > length $data,
    "The encrypted data is longer than the original (due to header)"
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
