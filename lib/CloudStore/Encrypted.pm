use strict;
use warnings;
use v5.14;
package CloudStore::Encrypted;
use parent 'CloudStore';

use Bytes::Random::Secure qw/ random_bytes /;
use Scalar::Util          qw/ reftype /;
use Crypt::Mode::CBC      ();
use File::Temp            ();

use constant DEFAULT_CIPHER  => 'AES';
use constant DEFAULT_IV_SIZE => 16;

sub new {
  my ($class, %params) = @_;
  my $key_hex = delete $params{'key_hex'};
  my $key_bin = delete $params{'key_bin'};
  my $key_b64 = delete $params{'key_b64'};
  my $cipher  = delete $params{'cipher'};
  my $iv_size = delete $params{'iv_size'};

  $cipher   //= DEFAULT_CIPHER;
  $iv_size  //= eval "require $cipher; $cipher->blocksize"
            //  eval "require Crypt::Cipher::$cipher; Crypt::Cipher::$cipher->blocksize"
            //  DEFAULT_IV_SIZE;

  # Ensure key is binary
  die "Conflicting key formats!"
    if scalar(grep { defined $_ } ($key_hex, $key_bin, $key_b64)) > 1;

  $key_bin = pack 'H*', $key_hex if defined $key_hex;
  $key_bin = do { require MIME::Base64; MIME::Base64::decode_base64($key_b64) } if defined $key_b64;

  my $self = $class->SUPER::new(%params);
  $self->{cbc}     = Crypt::Mode::CBC->new($cipher);
  $self->{cipher}  = $cipher;
  $self->{key}     = $key_bin;
  $self->{iv_size} = $iv_size;
  return $self;
}

sub upload {
  my ($self, $local, $remote) = @_;
  $self->generate_iv;

  # Upload from string (scalar ref)
  if (ref $local and ref $local eq 'SCALAR') {
    my $encrypted = $self->make_header . $self->cbc->encrypt($$local, $self->key, $self->iv);
    return $self->SUPER::upload(\$encrypted => $remote);
  }

  # Open output tempfile
  my $outfh = File::Temp->new || die "Cannot create tempfile, $!$@";

  # Open unencrypted raw file for reading
  my $infh;
  ref $local ?
    $infh = $local :
    open $infh, '<', $local or die "...$!";

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
  my $return = $self->SUPER::upload($outfh => $remote);
  close $outfh;
  return $return;
}

sub download {
  my ($self, $remote, $local) = @_;

  # Download to string (scalar ref)
  if (ref $local and ref $local eq 'SCALAR') {
    my $return = $self->SUPER::download($remote => $local);

    # Just in case the file is not the expected cipher
    my ($cipher, $iv) = $self->parse_header($local);
    my $cbc = $cipher eq $self->cipher ? $self->cbc : Crypt::Mode::CBC->new($cipher);

    # Decrypt and return original return value
    $$local = $cbc->decrypt($$local, $self->key, $iv);
    return $return;
  }

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
  ref $local ?
    $outfh = $local :
    open $outfh, '>', $local or die "Cannot open $local: $!";

  binmode $encfh;
  binmode $outfh;
  print $outfh $self->cbc->add($buf) while read $encfh, $buf, 1024;
  print $outfh $self->cbc->finish;
  close $encfh;
  close $outfh unless ref $local;
  return $return;
}

sub key          { $_[0]->{key}            }
sub cbc          { $_[0]->{cbc}            }
sub cipher       { $_[0]->{cipher}         }
sub iv_size      { $_[0]->{iv_size}        }
sub iv           { $_[0]->{iv}             }
sub iv_hex       { unpack('H*', $_[0]->iv) }
sub generate_iv  { $_[0]->{iv} = random_bytes($_[0]->iv_size)  }
sub download_raw { shift->SUPER::download(@_)                  }
sub make_header  { $_[0]->cipher . ':iv' . $_[0]->iv_hex . ':' }

sub parse_header {
  my ($self, $what) = @_;

  my $header;
  my $cipher;
  my $iv;

  if (ref $what and reftype $what eq 'GLOB') {
    seek $what, 0, 0 or die $!;
    my $buf;
    while (read $what, $buf, 1) {
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

1;

__END__

=head1 NAME

CloudStore::Encrypted - Subclass of CloudStore with automatic encryption.


=head1 SYNOPSIS

    use CloudStore::Encrypted;
    my $driver = 'Mock';
    my %conn_options = (); # might need username/key/secret/token/...

    my $cs = CloudStore->new(driver => $driver, cipher => 'AES', key => ...);
    $cs->connect(%conn_options);
    $cs->download('testdir/testfile.txt' => './testfile.txt');
    $cs->delete_file('testdir/testfile.txt');
    $cs->upload('somefile.txt' => 'testdir/somefile.txt');


=head1 DESCRIPTION

This module is a subclass of CloudStore with automatic encryption.


=head1 DIFFERENCES FROM CloudStore.pm

CloudStore::Encrypted->new takes the following additional arguments:

=over 4

=item key_hex or key_bin

An encryption/decryption key, in hexadecimal or binary format.

=item cipher

A name of a cipher module compatible with Crypt::Mode::CBC. This module
has been tested with AES and Blowfish. Note decrypting a file will
select a cipher automatically from the file's header.

=item iv_size

The size of the initialization vector. AES and Blowfish are supplied
automatically.

=back

=head1 HOW IT WORKS

When encrypting a file, CloudStore::Encrypted will generate an initialization
vector and encrypt the file using Crypt::Mode::CBC with the chosen cipher.
A header containing cipher and IV information is prepended to the file in the
format of CipherName:ivXXXXXXXX:, where the Xs are the IV in hex format.

When decrypting a file, first the header is read to obtain the cipher and IV.
If the cipher and/or IV conflict with the CloudStore::Encrypted object's cipher
or IV properties, the file will be decrypted using the appropriate algorithm
rather than the object's.


=head1 AUTHOR

Dondi Michael Stroma, E<lt>dstroma@localE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016-2026 by Dondi Michael Stroma.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.


=cut
