use warnings;
use strict;

use HTTP::Tiny::SPDY;
use HTTP::Request::Common;
use Plack::LWPish;
use Plack::Test::Suite;
use Test::More;

# Redefine Plack::LWPish::new to use HTTP::Tiny::SPDY and Plack::LWPish::request
# to change protocol to HTTPS (yes, this is a dirty hack)
{
    no strict 'refs';
    no warnings 'redefine';
    
    my $_Plack_LWPish_request = \&Plack::LWPish::request;

    *{'Plack::LWPish::new'} = sub {
        my $class = shift;
        my $self  = bless {}, $class;
        $self->{http} = @_ == 1 ? $_[0] : HTTP::Tiny::SPDY->new(@_);
        $self;     
    };

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

Plack::Test::Suite->run_server_tests('Arriba', undef, undef, listen_ssl => '*',
    spdy => 1, ssl_cert_file => 'certs/server-cert.pem', 
    ssl_key_file => 'certs/server-key.pem');

done_testing();
