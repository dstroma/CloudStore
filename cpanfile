requires 'perl', '5.008001';

requires 'Moo';
requires 'Role::Tiny';
requires 'Role::Tiny::With';
requires 'DateTime';
#requires 'DateTime::Format::RFC3339';

# Maybe change to recommends?
requires 'Bytes::Random::Secure';
requires 'Crypt::Mode::CBC';
requires 'File::Temp';

recommends 'WebService::Dropbox';
recommends 'WebService::Rackspace::CloudFiles';

on 'test' => sub {
    requires 'Test::More', '0.98';
};


