package CloudStore::Encrypted;
use Moo;
extends 'CloudStore';

has 'tempfile_path', is => 'ro', default => '/tmp';
has 'key_hex', is => 'ro';
has 'key_bin', is => 'ro';
#has 'cipher', is => 'ro', default => 'AES';

use Bytes::Random::Secure   qw/ random_bytes /;
use Scalar::Util            qw/ reftype /;
use Crypt::Mode::CBC        ();
use File::Temp              ();

my $cbc = Crypt::Mode::CBC->new('AES');

sub key {
  my $self = shift;
  if ($self->key_hex and $self->key_bin) {
    die 'Specify one key in hex or bin form' unless pack('H*', $self->key_hex) eq $self->key_bin;
  } elsif ($self->key_hex) {
    $self->{key_bin} = pack 'H*', $self->key_hex;
  }
  my $bits = length($self->key_bin)*8;
  die 'Key is not proper length' unless $bits == 128 or $bits == 196 or $bits == 256;
  return $self->key_bin;
}

sub upload {
  my ($self, $local, $remote) = @_;
  $self->generate_iv;

  if (ref $local and ref $local eq 'SCALAR') {
    my $encrypted = $self->make_header . $cbc->encrypt($$local, $self->key, $self->iv);
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
    $cbc->start_encrypt($self->key, $self->iv);
    my $buf;
    binmode $infh;
    binmode $outfh;
    print $outfh $self->make_header;
    print $outfh $cbc->add($buf) while read $infh, $buf, 1024;
    print $outfh $cbc->finish;
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
    my $rv = $self->SUPER::download($remote => $local);
    $self->parse_header($local);
    $$local = $cbc->decrypt($$local, $self->key, $self->iv);
    return $rv;
  } else {
    my $encfh = File::Temp->new;
    my $rv = $self->SUPER::download($remote => $encfh);

    # Parse encrypted file $tmpfile
    seek $encfh, 0, 0;
    $self->parse_header($encfh);
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
    print $outfh $cbc->add($buf) while read $encfh, $buf, 1024;
    print $outfh $cbc->finish;
    close $encfh;
    close $outfh unless ref $local;
    return $rv;
  }
}

sub make_header {
  my $self = shift;
  return 'AES:iv' . $self->iv . ':';
}

sub parse_header {
  my $self = shift;
  my $what = shift;

  my $header;
  if (ref $what and reftype $what eq 'GLOB') {
    seek $what, 0, 0;
    read $what, $header, 6+16+1; # length 'AES:iv' + 16 + length ':'
  } elsif (ref $what and ref $what eq 'SCALAR') {
    $header = substr($$what, 0, 6+16+1);
    $$what  = substr($$what, 6+16+1);
  }

  unless (substr($header, 0, 6) eq 'AES:iv' and substr($header, -1, 1) eq ':') {
    die "Cannot parse iv from header $header";
  }

  my $iv = substr $header, 6, 16;
  return $self->{iv} = $iv;
}

sub generate_iv { shift->{iv} = random_bytes(16); }
sub iv { shift->{iv}; }

1;

__END__
