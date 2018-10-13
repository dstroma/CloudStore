use strict;
use warnings;

package CloudStore::Test::Driver;

use CloudStore;
use Scalar::Util qw/blessed/;
use Digest::MD5 qw/md5/;
use Test::More;

sub test_driver {
  shift if $_[0] eq __PACKAGE__;
  my %options = @_;

  my $driver    = $options{driver};
  my $conninfo  = $options{connection_info};
  my $make_plan = $options{make_plan};

  # SETUP
  plan tests => 22 if $make_plan;
  my $localfile = '/tmp/perl-driver-test-' . time() . '-' . $$;
  my $tempfile  = $localfile.'.tmp';
  generate_random_binfile($localfile, 1024);

  my $obj; 
  my $which = "$driver driver: ";

  # BEGIN TESTS
  ok(
    $obj = CloudStore->new(driver => $driver),
    $which.'new() loads driver and returns a true value'
  );

  ok(
    (ref $obj and blessed $obj and $obj->isa('CloudStore')),
    $which.'new() value is instance of expected class'
  );

  ok(
    $obj->connect(%{$conninfo || {}}),
    $which.'Connect to backend',
  );

  # Create a folder
  my $folder_name = '_cloudstore-test-' . time() . '-' . $$;
  ok(
    $obj->create_folder($folder_name),
    $which.'create_folder()'
  );

  # Delete a folder, and recreate the same one just to make sure it was deleted
  ok(
    $obj->delete_folder($folder_name) && $obj->create_folder($folder_name),
    $which.'delete_folder() (and recreate)'
  );

  # Upload file by scalar ref
  my $content1 = $$ . '-' . int(rand()*1000);
  ok(
    $obj->upload(\$content1 => $folder_name.'/file_1.txt'),
    $which.'upload() by scalar ref'
  );

  # Download file into scalar ref
  my $buffer = '';
  ok(
    $obj->download($folder_name.'/file_1.txt' => \$buffer),
    $which.'download() by scalar ref'
  );

  #use Data::Dumper;
  #warn Dumper $CloudStore::Driver::Mock::storage;
  cmp_ok(
    $content1, 'eq', $buffer,
    $which.'Original content matches redownloaded content (using scalar ref buffers)' . $buffer . '<=>' . $content1
  );

  # Upload a file by filehandle
  open my $fh1, '<', $localfile || die "Cannot open $localfile for reading: $!";
  ok(
    $obj->upload($fh1 => $folder_name.'/file_2.txt'),
    $which.'upload() by filehandle'
  );
  close $fh1;

  open my $fh2, '>', $tempfile || die "Cannot open $tempfile for writing: $!";
  ok(
    $obj->download($folder_name.'/file_2.txt' => $fh2),
    $which.'download() by filehandle'
  );
  close $fh2;

  ok(
    md5_file($localfile) eq md5_file($tempfile),
    $which.'Original file and redownloaded file match (using filehandles)'
  );

  unlink $tempfile;
  die "Could not delete $tempfile: $!" if -e $tempfile;

  # Upload by filename
  ok(
    $obj->upload($localfile => $folder_name.'/file_3.txt'),
    $which.'upload() by filename'
  );

  ok(
    $obj->download($folder_name.'/file_3.txt' => $tempfile),
    $which.'download() to filename'
  );
  
  ok(
    md5_file($localfile) eq md5_file($tempfile),
    $which.'Original file and redownloaded file match (using filenames)'
  );

  unlink $tempfile;

  # Find
  my @files;
  @files = $obj->find(in => $folder_name, prefix => 'file_');
  ok(
    @files == 3,
    $which.'Find finds existing files - ',
  );

  @files = $obj->find(in => $folder_name, prefix => 'notafile_');
  ok(
    @files == 0,
    $which.'Find does not find nonexisting files',
  );

  @files = $obj->find(in => $folder_name, prefix => 'file_', pattern => qr/^file_\d.txt$/);
  ok(
    @files == 3,
    $which.'Find by regex shows correct existing files',
  );

  @files = $obj->find(in => $folder_name, prefix => 'file_', pattern => qr/^file_[a-zA-Z].txt$/);
  ok(
    @files == 0,
    $which.'Find by regex does not find files it should not find',
  );

  my $file;
  $file = $obj->find($folder_name.'/file_1.txt');
  ok(
    ($file and ref $file and blessed $file and $file->name eq 'file_1.txt'),
    $which.'Find a single file returns file object for existing file'
  );

  $file = $obj->find($folder_name.'/file_DOES_NOT_EXIST.NOPE');
  ok(
    !defined $file,
    $which.'Attempting to find a single file that does not exist returns undef'
  );
    

  # Delete remote file
  ok(
    $obj->delete_file($folder_name . '/file_1.txt'),
    $which.'Delete a file',
  );

  ok(
    !defined $obj->find($folder_name.'/file_1.txt'),
    $which.'Find says file is really deleted',
  );

  # Clean up
  $obj->delete_file($folder_name . '/file_2.txt');
  $obj->delete_file($folder_name . '/file_3.txt');
  $obj->delete_folder($folder_name);
}

sub generate_random_binfile {
  my $name = shift;
  my $size = shift;

  my $chunk_size = 128;
  my $chunks     = int($size/$chunk_size);

  open(my $fh, '>', $name) or die "Cannot create tempfile $name: $!";
  binmode $fh;
  for (1..$chunks) {
    my $chunk = '';
    for (1..$chunk_size) {
      $chunk .= chr(int(rand()*256));
    }
    print $fh $chunk;
  }
  close $fh;
}

sub md5_file {
  my $filename = shift;
  open my $fh, '<', $filename or die $1;
  my $content = join '', <$fh>;
  close $fh;
  return md5($content);
}

1;
