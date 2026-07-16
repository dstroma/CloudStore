use strict;
use warnings;
use v5.14;
package CloudStore::Encrypted;
use parent 'CloudStore';

use Bytes::Random::Secure   qw/ random_bytes /;
use Scalar::Util            qw/ reftype /;
use Crypt::Mode::CBC        ();
use File::Temp              ();

use constant DEFAULT_CIPHER => 'AES';

sub new {
  my ($class, %params) = @_;
  my $key_hex = delete $params{'key_hex'};
  my $key_bin = delete $params{'key_bin'};
  my $cipher  = delete $params{'cipher'} // DEFAULT_CIPHER;

  my $cbc = Crypt::Mode::CBC->new($cipher);

  # Massage key
  if ($key_hex and $key_bin) {
    die 'Specify one key in hex or bin form' unless pack('H*', $key_hex) eq $key_bin;
  } elsif ($key_hex) {
    $key_bin = pack 'H*', $key_hex;
  }

  #my $bits = length($key_bin)*8;
  #die "Key of length $bits is not proper length" unless $bits >= 128 or $bits == 196 or $bits == 256;

  my $self = $class->SUPER::new(%params);
  $self->{cipher} = $cipher;
  $self->{key}    = $key_bin;
  $self->{cbc}    = $cbc;
  return $self;
}

sub key    { $_[0]->{key}    }
sub cbc    { $_[0]->{cbc}    }
sub cipher { $_[0]->{cipher} }

sub upload {
  my ($self, $local, $remote) = @_;
  $self->generate_iv;

  if (ref $local and ref $local eq 'SCALAR') {
    my $encrypted = $self->make_header . $self->cbc->encrypt($$local, $self->key, $self->iv);
    return $self->SUPER::upload(\$encrypted => $remote);
  } else {
    # Open output tempfile
    my $outfh = File::Temp->new || die "Cannot create tempfile, $!$@";

    # Open unencrypted raw file for reading
    my $infh;
    if (ref $local) {
      $infh = $local;
    } else {
      open $infh, '<', $local or die "...$!";
    }

    # Do encryption
    $self->cbc->start_encrypt($self->key, $self->iv);
    my $buf;
    binmode $infh;
    binmode $outfh;
    print $outfh $self->make_header;
    print $outfh $self->cbc->add($buf) while read $infh, $buf, 1024;
    print $outfh $self->cbc->finish;
    close $infh if not ref $local;

    # Reset file pointer and upload it
    seek $outfh, 0, 0;
    my $rv = $self->SUPER::upload($outfh => $remote);
    close $outfh;
    return $rv;
  }
}

sub download {
  my ($self, $remote, $local) = @_;
  if (ref $local and ref $local eq 'SCALAR') {
    my $return = $self->SUPER::download($remote => $local);

    # Just in case the file is not the expected cipher
    my ($cipher, $iv) = $self->parse_header($local);
    my $cbc = $cipher eq $self->cipher ? $self->cbc : Crypt::Mode::CBC->new($cipher);

    # Decrypt and return original return value
    $$local = $cbc->decrypt($$local, $self->key, $iv);
    return $return;
  } else {
    my $encfh  = File::Temp->new;
    my $return = $self->SUPER::download($remote => $encfh);
    seek $encfh, 0, 0;

    # Just in case the file is not the expected cipher
    my ($cipher, $iv) = $self->parse_header($encfh);
    my $cbc = $cipher eq $self->cipher ? $self->cbc : Crypt::Mode::CBC->new($cipher);

    $cbc->start_decrypt($self->key, $self->iv);
    my $buf;
    my $outfh;

    # Open output file
    if (ref $local) {
      $outfh = $local;
    } else {
      open $outfh, '>', $local or die "Cannot open $local: $!";
    }
    binmode $encfh;
    binmode $outfh;
    print $outfh $self->cbc->add($buf) while read $encfh, $buf, 1024;
    print $outfh $self->cbc->finish;
    close $encfh;
    close $outfh unless ref $local;
    return $return;
  }
}

sub download_raw {
  shift->SUPER::download(@_);
}

sub make_header {
  my $self = shift;
  return $self->cipher . ':iv' . $self->iv_hex . ':';
}

sub parse_header {
  my $self = shift;
  my $what = shift;

  my $header;
  my $cipher;
  my $iv;

  if (ref $what and reftype $what eq 'GLOB') {
    seek $what, 0, 0 or die $!;
    my $buf;
    while (my $bytes = read $what, $buf, 1) {
      $header .= $buf;
      last if ($cipher, $iv) = $header =~ m/^(\w+):iv([a-f0-9]+):/;
      last if length $header > 1024; # give up
    }
  } elsif (ref $what and ref $what eq 'SCALAR') {
    ($cipher, $iv) = $$what =~ m/^(\w+):iv([a-f0-9]+):/;
    $$what = substr($$what, length("$cipher:iv$iv:"));
  }

  die "Cannot parse header! cipher:$cipher, iv:$iv" unless length $cipher and length $iv;

  return ($cipher, pack('H*', $iv));
}

sub generate_iv { shift->{iv} = random_bytes(16) }
sub iv          { shift->{iv}                    }
sub iv_hex      { unpack('H*', shift->iv)        }

1;

__END__

=head1 NAME

CloudStore::Encrypted - Subclass of CloudStore with automatic encryption.


=head1 SYNOPSIS

    use CloudStore::Encrypted;
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
