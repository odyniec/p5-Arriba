package Arriba::Server;

use warnings;
use strict;

use base 'Net::Server::PreFork';

use HTTP::Date;
use HTTP::Status qw(status_message);
use HTTP::Parser::XS qw(parse_http_request);
use IO::Socket::SSL;

use Plack::Util;
use Plack::TempBuffer;

use constant DEBUG => $ENV{ARRIBA_DEBUG};
use constant CHUNKSIZE => 64 * 1024;

my $null_io = do { open my $io, "<", \""; $io };

use Net::Server::SIG qw(register_sig);

# Override Net::Server's HUP handling - just restart all the workers and that's
# about it
sub sig_hup {
    my $self = shift;
    $self->hup_children;
}

sub parse_listen_options {
    my ($listen_options, $listen_ssl) = @_;
    my ($host, $port, $proto);

    # Strip off the leading colon, if present
    ($listen_ssl ||= 0) =~ s/^://;

    for my $listen (@$listen_options) {
        if ($listen =~ /:/) {
            my($h, $p) = split /:/, $listen, 2;
            push @$host, $h || '*';
            push @$port, $p;
            push @$proto, $listen_ssl eq '*' || $p == $listen_ssl ?
                'ssl' : 'tcp';
        } else {
            push @$host, 'localhost';
            push @$port, $listen;
            push @$proto, 'unix';
        }
    }

    return ($host, $port, $proto);
}

sub run {
    my ($self, $app, $options) = @_;

    $self->{app} = $app;
    $self->{options} = $options;

    my %extra = ();
    if ($options->{pid}) {
        $extra{pid_file} = $options->{pid};
    }
    if ($options->{daemonize}) {
        $extra{setsid} = $extra{background} = 1;
    }
    if (!exists $options->{keepalive}) {
        $options->{keepalive} = 1;
    }
    if (!exists $options->{keepalive_timeout}) {
        $options->{keepalive_timeout} = 1;
    }

    my ($host, $port, $proto) = parse_listen_options($options->{listen} ||
        [ "$options->{host}:$options->{port}" ], $options->{listen_ssl});

    my $workers = $options->{workers} || 5;

    local @ARGV = ();

    $self->SUPER::run(
        port => $port,
        host => $host,
        proto => $proto,
        serialize => 'flock',
        log_level => DEBUG ? 4 : 2,
        ($options->{error_log} ? ( log_file => $options->{error_log} ) : () ),
        min_servers => $options->{min_servers} || $workers,
        min_spare_servers => $options->{min_spare_servers} || $workers - 1,
        max_spare_servers => $options->{max_spare_servers} || $workers - 1,
        max_servers => $options->{max_servers} || $workers,
        max_requests => $options->{max_requests} || 1000,
        user => $options->{user} || $>,
        group => $options->{group} || $),
        listen => $options->{backlog} || 1024,
        check_for_waiting => 1,
        no_client_stdout => 1,
        %extra
    );
}

sub configure_hook {
    my $self = shift;

    # FIXME: Is this (configure_hook) the best place for this?
    
    if ($self->{options}->{listen_ssl}) {
        $self->{server}->{ssl_args}->{SSL_key_file} =
            $self->{options}->{ssl_key_file};
        $self->{server}->{ssl_args}->{SSL_cert_file} =
            $self->{options}->{ssl_cert_file};
    }

    $self->SUPER::configure_hook(@_);
}

sub pre_bind {
    my $self = shift;

    $self->SUPER::pre_bind(@_);

    if ($self->{options}->{spdy}) {
        # Enable SPDY on SSL sockets
        for my $sock (@{$self->{server}->{sock}}) {
            if ($sock->NS_proto eq 'SSL') {
                $sock->SSL_npn_protocols(['spdy/3']);
            }
        }
    }
}

sub pre_loop_hook {
    my $self = shift;
 
    my $host = $self->{server}->{host}->[0];
    my $port = $self->{server}->{port}->[0];
 
    $self->{options}{server_ready}->({
        host => $host,
        port => $port,
        proto => $port =~ /unix/ ? 'unix' : 'http',
        server_software => 'Arriba',
    }) if $self->{options}{server_ready};
 
    register_sig(
        TTIN => sub { $self->{server}->{$_}++ for qw( min_servers max_servers ) },
        TTOU => sub { $self->{server}->{$_}-- for qw( min_servers max_servers ) },
        QUIT => sub { $self->server_close(1) },
    );
}

sub server_close {
    my($self, $quit) = @_;
 
    if ($quit) {
        $self->log(2, $self->log_time . " Received QUIT. Running a graceful shutdown\n");
        $self->{server}->{$_} = 0 for qw( min_servers max_servers );
        $self->hup_children;
        while (1) {
            Net::Server::SIG::check_sigs();
            $self->coordinate_children;
            last if !keys %{$self->{server}{children}};
            sleep 1;
        }
        $self->log(2, $self->log_time . " Worker processes cleaned up\n");
    }
 
    $self->SUPER::server_close();
}

sub run_parent {
    my $self = shift;
    $0 = "arriba master " . join(" ", @{$self->{options}{argv} || []});
    no warnings 'redefine';
    local *Net::Server::PreFork::register_sig = sub {
        my %args = @_;
        delete $args{QUIT};
        Net::Server::SIG::register_sig(%args);
    };
    $self->SUPER::run_parent(@_);
}

sub child_init_hook {
    my $self = shift;
    srand();
    if ($self->{options}->{psgi_app_builder}) {
        $self->{app} = $self->{options}->{psgi_app_builder}->();
    }
    $0 = "arriba worker " . join(" ", @{$self->{options}{argv} || []});
}
 
sub post_accept_hook {
    my $self = shift;
 
    $self->{client} = { };
}

sub process_request {
    my $self = shift;

    my $client = $self->{server}->{client};

    # Is this an SSL connection?
    my $ssl = $client->NS_proto eq 'SSL';

    if ($ssl && $client->next_proto_negotiated &&
        $client->next_proto_negotiated eq 'spdy/3')
    {
        # SPDY connection
        require Arriba::Connection::SPDY;
        $self->{client}->{connection} =
            Arriba::Connection::SPDY->new($client);
    }
    else {
        # HTTP(S) connection
        require Arriba::Connection::HTTP;
        $self->{client}->{connection} =
            Arriba::Connection::HTTP->new($client, ssl => $ssl,
                chunk_size => CHUNKSIZE);
    }

    my $connection = $self->{client}->{connection};

    while (my $req = $connection->read_request) {
        my $env;
        my $conn_header;

        if ($req->{env}) {
            # Headers already parsed
            $env = $req->{env};
        }
        else {
            $env = {
                REMOTE_ADDR => $self->{server}->{peeraddr},
                REMOTE_HOST => $self->{server}->{peerhost} || $self->{server}->{peeraddr},
                REMOTE_PORT => $self->{server}->{peerport} || 0,
                SERVER_NAME => $self->{server}->{sockaddr} || 0, # XXX: needs to be resolved?
                SERVER_PORT => $self->{server}->{sockport} || 0,
                SCRIPT_NAME => '',
                'psgi.version' => [ 1, 1 ],
                'psgi.errors' => *STDERR,
                'psgi.url_scheme' => $req->{scheme},
                'psgi.nonblocking' => Plack::Util::FALSE,
                'psgi.streaming' => Plack::Util::TRUE,
                'psgi.run_once' => Plack::Util::FALSE,
                'psgi.multithread' => Plack::Util::FALSE,
                'psgi.multiprocess' => Plack::Util::TRUE,
                'psgix.io' => $client,
                'psgix.input.buffered' => Plack::Util::TRUE,
                'psgix.harakiri' => Plack::Util::TRUE,
            };

            my $reqlen = parse_http_request($req->{headers}, $env);

            if ($reqlen < 0) {
                # Bad request
                $self->_http_error($req, 400);
                last;
            }

            $conn_header = delete $env->{HTTP_CONNECTION};
            my $proto = $env->{SERVER_PROTOCOL};

            if ($proto && $proto eq 'HTTP/1.0' ) {
                if ($conn_header && $conn_header =~ /^keep-alive$/i) {
                    # Keep-alive only with explicit header in HTTP/1.0
                    $connection->{_keepalive} = 1;
                }
                else {
                    $connection->{_keepalive} = 0;
                }
            }
            elsif ($proto && $proto eq 'HTTP/1.1') {
                if ($conn_header && $conn_header =~ /^close$/i ) {
                    $connection->{_keepalive} = 0;
                }
                else {
                    # Keep-alive assumed in HTTP/1.1
                    $connection->{_keepalive} = 1;
                }
 
                # Do we need to send 100 Continue?
                if ($env->{HTTP_EXPECT}) {
                    if ($env->{HTTP_EXPECT} eq '100-continue') {
                        # FIXME:
                        #syswrite $client, 'HTTP/1.1 100 Continue' . $CRLF . $CRLF;
                    }
                    else {
                        $self->_http_error(417, $env);
                        last;
                    }
                }
 
                unless ($env->{HTTP_HOST}) {
                    # No host, bad request
                    $self->_http_error(400, $env);
                    last;
                }
            }

            unless ($self->{options}->{keepalive}) {
                $connection->{_keepalive} = 0;
            }

            $req->{env} = $env;
        }
        
        # Process this request later if it's not ready yet
        next if !$req->{complete};

        if ($req->{body_stream}) {
            $env->{'psgi.input'} = $req->{body_stream}->rewind;
        }
        else {
            $env->{'psgi.input'} = $null_io;
        }

        my $res = Plack::Util::run_app($self->{app}, $env);

        if (ref $res eq 'CODE') {
            $res->(sub { $connection->write_response($req, $_[0]) });
        }
        else {
            $connection->write_response($req, $res);
        }

        my $sel = IO::Select->new($client);
        last unless $sel->can_read($self->{options}->{keepalive_timeout});
    }
}

sub _http_error {
    my ($self, $req, $code) = @_;
 
    my $status = $code || 500;
    my $msg = status_message($status);
 
    my $res = [
        $status,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => length($msg) ],
        [ $msg ],
    ];

    $self->{client}->{connection}->{_keepalive} = 0;
    $self->{client}->{connection}->write_response($req, $res);
}

1;

