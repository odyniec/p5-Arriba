package Arriba::Connection::HTTP;

use warnings;
use strict;

use Data::Dump qw(dump);
use HTTP::Status qw(status_message);
use IO::Socket qw(:crlf);
use Plack::Util;
use Socket qw(IPPROTO_TCP TCP_NODELAY);

use base 'Arriba::Connection';

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    if ($self->{client}->NS_proto eq 'TCP') {
        setsockopt($self->{client}, IPPROTO_TCP, TCP_NODELAY, 1)
            or die $!;
    }
    
    $self->{_inputbuf} = '';
    $self->{_current_req} = undef;
    $self->{_keepalive} = 1;

    return $self;
}

sub read_request {
    my $self = shift;

    my $req;

    if ($req = $self->{_current_req}) {
        # Partially processed request
        my $get_chunk = sub {
            if ($self->{_inputbuf}) {
                my $chunk = delete $self->{_inputbuf};
                return ($chunk, length $chunk);
            }
            my $read = sysread $self->{client}, my($chunk), $self->{chunk_size};
            return ($chunk, $read);
        };

        my $chunked = do {
            no warnings;
            lc delete $req->{env}->{HTTP_TRANSFER_ENCODING} eq 'chunked'
        };

        if ((my $cl = $req->{content_length}) >= 0) {
            $req->{body_stream} = Stream::Buffered->new($req->{content_length});
            while ($cl > 0) {
                my($chunk, $read) = $get_chunk->();

                if (!defined $read || $read == 0) {
                    die "Read error: $!\n";
                }

                $cl -= $read;
                $req->{body_stream}->print($chunk);
            }
        }
        elsif ($chunked) {
            $req->{body_stream} = Stream::Buffered->new;
            my $chunk_buffer = '';
            my $length;

            DECHUNK:
            while (1) {
                my($chunk, $read) = $get_chunk->();
                $chunk_buffer .= $chunk;

                while ($chunk_buffer =~ s/^(([0-9a-fA-F]+).*\015\012)// ) {
                    my $trailer = $1;
                    my $chunk_len = hex $2;
 
                    if ($chunk_len == 0) {
                        last DECHUNK;
                    } elsif (length $chunk_buffer < $chunk_len + 2) {
                        $chunk_buffer = $trailer . $chunk_buffer;
                        last;
                    }
 
                    $req->{body_stream}->print(substr($chunk_buffer, 0,
                        $chunk_len, ''));
                    $chunk_buffer =~ s/^\015\012//;
 
                    $length += $chunk_len;
                }
 
                last unless $read && $read > 0;
            }
 
            $req->{content_length} = $length;
        }

        $req->{complete} = 1;
        $self->{_current_req} = undef;
    }
    elsif ($self->{_keepalive}) {
        # New request
        $req = Arriba::Request->new($self);
        $req->{scheme} = $self->{ssl} ? 'https' : 'http';

        while (1) {
            last if defined $self->{_inputbuf} &&
                $self->{_inputbuf} =~ /$CRLF$CRLF/s;
            
            my $read = sysread $self->{client}, my $buf, $self->{chunk_size};

            if (!defined $read || $read == 0) {
                die "Read error: $!\n";
            }

            $self->{_inputbuf} .= $buf;
        }

        (my $headers, $self->{_inputbuf}) =
            split /$CRLF$CRLF/, $self->{_inputbuf}, 2;

        # Add back two CRLFs, HTTP::Parser's parse_http_requests expects that
        $req->{headers} = $headers . $CRLF . $CRLF;

        if ($req->{headers} =~ /^content-length:\s*(\d+)\015?$/im) {
            $req->{content_length} = $1;
            $self->{_current_req} = $req;
        }
        else {
            # No "Content-length" header, we have the whole request
            $req->{complete} = 1;
            $self->{_current_req} = undef;
        }
    }

    return $req;
}

sub write_response {
    my $self = shift;
    my $req = shift;
    my $res = shift;

    my $proto = $req->{env}->{SERVER_PROTOCOL};
    my $status = $res->[0];

    my %headers;
    my $chunked;
    my @header_lines = ("$proto $status " . status_message($status));
    
    my $res_headers = $res->[1];

    for (my $i = 0; $i < @$res_headers; $i += 2) {
        next if $res_headers->[$i] eq 'Connection';
        push @header_lines, $res_headers->[$i] . ": " . $res_headers->[$i+1];
        $headers{lc $res_headers->[$i]} = $res_headers->[$i+1];
    }

    if ($proto eq 'HTTP/1.1') {
        if (!exists $headers{'content-length'}) {
            if ($status !~ /^1\d\d|[23]04$/) {
                push @header_lines, 'Transfer-Encoding: chunked';
                $chunked = 1;
            }
        }
        elsif (my $te = $headers{'transfer-encoding'}) {
            if ($te eq 'chunked') {
                $chunked = 1;
            }
        }
    }
    else {
        if (!exists $headers{'transfer-encoding'}) {
            $self->{_keepalive} = 0;
        }
    }

    if ($self->{_keepalive}) {
        push @header_lines, 'Connection: keep-alive';
    }
    else {
        push @header_lines, 'Connection: close';
    }

    syswrite $self->{client}, join($CRLF, @header_lines, '') . $CRLF;

    if (defined $res->[2]) {
        Plack::Util::foreach($res->[2], sub {
            my $buffer = $_[0];
            my ($len, $offset);

            if ($chunked) {
                $len = length $buffer;
                return unless $len;
                $buffer = sprintf( "%x", $len ) . $CRLF . $buffer . $CRLF;
            }
            
            $len = length $buffer;
            $offset = 0;
            while ($len) {
                my $written = syswrite $self->{client}, $buffer, $len, $offset;
                # TODO: Handle errors maybe?
                $len -= $written;
                $offset += $written;
            }
        });
 
        syswrite $self->{client}, "0$CRLF$CRLF" if $chunked;
    }
    else {
        # TODO: Above loop also needed here
        return Plack::Util::inline_object
            write => sub {
                my $buf = $_[0];
                if ($chunked) {
                    my $len = length $buf;
                    return unless $len;
                    $buf = sprintf( "%x", $len ) . $CRLF . $buf . $CRLF;
                }
                syswrite $self->{client}, $buf;
            },
            close => sub {
                syswrite $self->{client}, "0$CRLF$CRLF" if $chunked;
            };
    }
}

1;

