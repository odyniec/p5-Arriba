use warnings;
use strict;

use HTTP::Request::Common;
use Plack::LWPish;
use Plack::Test::Suite;
use Test::More;

# Redefine Plack::LWPish::request to change protocol to HTTPS
# (yes, this is a dirty hack)
{
    no strict 'refs';
    no warnings 'redefine';
    
    my $_Plack_LWPish_request = \&Plack::LWPish::request;

    *{'Plack::LWPish::request'} = sub {
        my ($self, $req) = @_;

        my $url = $req->uri;
        $url =~ s{^http://}{https://};
        $req->uri($url);
        
        return &$_Plack_LWPish_request($self, $req);
    };
}

# Test subroutine to replace the original "psgi.url_scheme" test and accept
# "https" as a correct response
my $url_scheme_test = sub {
    my $cb = shift;
    my $res = $cb->(POST "http://127.0.0.1/");
    is $res->code, 200;
    is $res->message, 'OK';
    is $res->header('content_type'), 'text/plain';
    is $res->content, 'https';
};

@Plack::Test::Suite::TEST = map { $_->[0] eq 'psgi.url_scheme' ?
    [ $_->[0], $url_scheme_test, $_->[2] ] : $_ } @Plack::Test::Suite::TEST;

Plack::Test::Suite->run_server_tests('Arriba', undef, undef, ssl => 1, 
    ssl_cert => 'certs/server-cert.pem', ssl_key => 'certs/server-key.pem');

done_testing();
