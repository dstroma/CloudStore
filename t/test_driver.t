use strict;
use warnings;

use Test::More;
use CloudStore::Test::Driver;
use constant USER_PROMPT_TIMEOUT => 10;

my $has_dropbox     = eval "require CloudStore::Driver::Dropbox; 1"
  or warn "Will not test Dropbox driver (not installed or incomplete)\n";
my $has_rackspacecf = eval "require CloudStore::Driver::RackspaceCloudFiles; 1"
  or warn "Will not test RackspaceCloudFiles driver (not installed or incomplete)\n";

CloudStore::Test::Driver::test_driver(
  driver => 'Mock',
  connection_info => {},
  make_plan => 0
);

CloudStore::Test::Driver::test_driver(
  driver => 'Dropbox',
  connection_info => {
    key          => $ENV{'DROPBOX_KEY'}
                // maybe_prompt('Dropbox Key: '),
    secret       => $ENV{'DROPBOX_SECRET'}
                // maybe_prompt('Dropbox Secret: '),
    access_token => $ENV{'DROPBOX_ACCESS_TOKEN'}
                // maybe_prompt('Dropbox Access Token: '),
  },
  make_plan => 0
) if $has_dropbox;

CloudStore::Test::Driver::test_driver(
  driver => 'RackspaceCloudFiles',
  connection_info => {
    user => $ENV{'RACKSPACE_CLOUDFILES_USER'}
         // maybe_prompt('Rackspace CloudFiles User: '),
    key  => $ENV{'RACKSPACE_CLOUDFILES_KEY'}
         // maybe_prompt('Rackspace CloudFiles Key: '),
  },
  make_plan => 0
) if $has_rackspacecf;

done_testing();

#######################################################################
# Maybe prompt with timeout

{
  my $skip_first_prompt;
  my $donot_prompt;
  sub maybe_prompt {
    return if $donot_prompt;

    unless ($skip_first_prompt) {
      print "\nPress ENTER/RETURN within " . USER_PROMPT_TIMEOUT . " seconds to add credentials...";
      eval {
        local $SIG{ALRM} = sub {
          $donot_prompt = 1;
          die "timeout\n"
        };

        alarm USER_PROMPT_TIMEOUT;
        my $garbage = <STDIN>;
        alarm 0;
        print "\n";
        1;
      } or return;

      print "*** Note your input will be shown on screen ***\n\n";
    }

    $skip_first_prompt = 1;
    my $prompt_text = shift;
    print $prompt_text;
    my $answer = <STDIN>;
    chomp $answer;
    return $answer;
  }
}
