package CloudStore::File;

use strict;
use warnings;

sub new {
  my $class  = shift;
  my %params = @_;
  bless \%params, $class;
}

sub last_modified {
  my $self = shift;
  return $self->{last_modified} if exists $self->{last_modified};
  if ($self->{last_modified_inflator} and ref $self->{last_modified_inflator} eq 'CODE') {
    $self->{last_modified} = $self->{last_modified_inflator}->();
  }
  return $self->{last_modified};
}

sub original {
  my $self = shift;
  $self->{original} = shift if @_;
  return $self->{original};
}

sub name {
  my $self = shift;
  return $self->{name};
}

sub location {
  my $self = shift;
  return $self->{location};
}

1;
