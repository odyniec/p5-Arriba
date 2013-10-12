package Arriba::Connection::SPDY;

use warnings;
use strict;

use HTTP::Date;
use HTTP::Status qw(status_message);
use IO::Socket qw(:crlf);
use Net::SPDY::Session;
use Plack::Util;

use Arriba::Request;

use base 'Arriba::Connection';

# The current version of Net::SPDY::Session has some debugging code in the
# process_frame method, which breaks things. Until that gets fixed, we'll use
# our own version of this method.
{
    no strict 'refs';
    no warnings 'redefine';
    *{"Net::SPDY::Session::process_frame"} = sub {
        my $self = shift;

        my %frame = $self->{framer}->read_frame ();
        return () unless %frame;

        if (not $frame{control}) {
            warn 'Not implemented: Data frame received';
            return %frame;
        }

        if ($frame{type} == Net::SPDY::Framer::SYN_STREAM) {
        } elsif ($frame{type} == Net::SPDY::Framer::SETTINGS) {
            $self->got_settings (%frame);
        } elsif ($frame{type} == Net::SPDY::Framer::PING) {
            $self->{framer}->write_ping (
                flags => 0,
                id => $frame{id},
            );
        } elsif ($frame{type} == Net::SPDY::Framer::GOAWAY) {
            $self->close (0);
        } elsif ($frame{type} == Net::SPDY::Framer::HEADERS) {
            # We should remember values gotten here for stream
            warn 'Not implemented: Got headers frame'
        } else {
            die 'Unknown frame type '.$frame{type};
        }

        return %frame;
    };
}

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    $self->{_spdy} = {
        session => Net::SPDY::Session->new($self->{client}),
        streams => {},
    };

    return $self;
}

sub read_request {
    my $self = shift;

    my $session = $self->{_spdy}->{session};
    my $streams = $self->{_spdy}->{streams};

    my $req;

    while (my %frame = $session->process_frame) {
        if (exists $frame{type} &&
            $frame{type} == Net::SPDY::Framer::SYN_STREAM)
        {
            # Request initiated
            $req = Arriba::Request->new($self);
            $req->{_spdy} = {
                # Keep track of this request's stream ID
                stream_id => $frame{stream_id},
                # Save a reference to the frame that initiated this request
                frame => \%frame,
            };

            $streams->{$frame{stream_id}} = { req => $req };

            my %frame_headers = @{$frame{headers}};
            my @http_headers = @{$frame{headers}};

            my $headers = '';
            # Construct the HTTP request line
            $headers .= $frame_headers{':method'}  . ' ' .
                $frame_headers{':path'} . ' ' .
                $frame_headers{':version'} . $CRLF;

            $req->{scheme} = $frame_headers{':scheme'};

            if ($frame_headers{':host'}) {
                $headers .= 'host: ' . $frame_headers{':host'} . $CRLF;
            }
            
            for (my $i = 0; $i < $#http_headers; $i += 2) {
                if ($http_headers[$i] !~ /^:/) {
                    $headers .= "$http_headers[$i]: $http_headers[$i+1]$CRLF";
                }
            }

            $headers .= $CRLF;

            $req->{headers} = $headers;
        }
        # Existing stream ID
        elsif (my $stream = $streams->{$frame{stream_id}}) {
            # Grab the corresponding request
            $req = $stream->{req};
        }
        # Unknown stream ID
        else {
            # TODO: Error
            next;
        }

        if (!$frame{control}) {
            # Data frame
            if (!$req->{body_stream}) {
                # TODO: Initialize with content length?
                $req->{body_stream} = Stream::Buffered->new;
            }
            $req->{body_stream}->print($frame{data});
        }

        if ($frame{flags} & Net::SPDY::Framer::FLAG_FIN) {
            # Last frame on this stream
            $req->{complete} = 1;
        }

        return $req;
    }
}

sub write_response {
    my $self = shift;
    my $req = shift;
    my $res = shift;

    my $status = $res->[0];

    my @frame_headers = (
        ':version' => 'HTTP/1.1',
        ':status' => "$status " . status_message($status),
        'date' => HTTP::Date::time2str(),
        'server' => 'arriba', # FIXME
    );

    Plack::Util::header_iter($res->[1], sub {
        my ($k, $v) = @_;
        push @frame_headers, lc $k, $v;
    });

    my $data;

    if (defined $res->[2]) {
        Plack::Util::foreach($res->[2], sub {
            $data .= $_[0];
        });
    }

    my %frame = (
        type => Net::SPDY::Framer::SYN_REPLY,
        stream_id => $req->{_spdy}->{stream_id},
        headers => [ @frame_headers ],
        data => $data,
        control => 1,
    );

    $self->{_spdy}->{session}->{framer}->write_frame(%frame);

    delete $frame{type};
    $frame{control} = 0;
    $frame{flags} = Net::SPDY::Framer::FLAG_FIN;

    $self->{_spdy}->{session}->{framer}->write_frame(%frame);
}

1;

