use warnings;
use strict;

use HTTP::Request::Common;
use LWP::UserAgent;
use Plack::Test::Suite;
use Test::More;

# Redefine LWP::UserAgent::prepare_request to change protocol to HTTPS
# (yes, this is a dirty hack)

my $_LWP_UserAgent_prepare_request = \&LWP::UserAgent::prepare_request;

sub LWP_UserAgent_prepare_request {
    my ($self, $request) = @_;
    my $url = $request->uri;
    $url =~ s{^http://}{https://};
    $request->uri($url);
    return &$_LWP_UserAgent_prepare_request($self, $request);
}

{
    no strict 'refs';
    no warnings 'redefine';
    *{'LWP::UserAgent::prepare_request'} = \&LWP_UserAgent_prepare_request;
}

# Skip SSL hostname verification
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

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

Plack::Test::Suite->run_server_tests('Arriba', undef, undef, listen_ssl => '*', 
    ssl_cert_file => 'certs/server-cert.pem', 
    ssl_key_file => 'certs/server-key.pem');

done_testing();

