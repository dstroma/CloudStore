requires 'perl', '5.014';

requires 'Moo';
requires 'Role::Tiny';
requires 'Role::Tiny::With';
requires 'DateTime';

# Maybe change to recommends?
requires 'Bytes::Random::Secure';
requires 'Crypt::Mode::CBC';
requires 'File::Temp';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

