package Arriba::Connection::SPDY;

use warnings;
use strict;

use HTTP::Date;
use IO::Socket qw(:crlf);
use Net::SPDY::Session;
use Plack::Util;

use Arriba::Request;

use base 'Arriba::Connection';

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

            my $headers = '';
            # Construct the HTTP request line
            $headers .= delete($frame_headers{':method'})  . ' ' .
                delete($frame_headers{':path'}) . ' ' .
                delete($frame_headers{':version'}) . $CRLF;

            $req->{scheme} = delete $frame_headers{':scheme'};

            if ($frame_headers{':host'}) {
                $headers .= 'host: ' . delete($frame_headers{':host'}) . $CRLF;
            }
            
            map { $headers .= "$_: $frame_headers{$_}$CRLF" }
                keys %frame_headers;

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

    my %frame_headers = (
        ':version' => 'HTTP/1.1',
        ':status' => $status,
        'date' => HTTP::Date::time2str(),
        'server' => 'arriba', # FIXME
    );

    Plack::Util::header_iter($res->[1], sub {
        my ($k, $v) = @_;
        $frame_headers{lc $k} = $v;
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
        headers => [ %frame_headers ],
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

