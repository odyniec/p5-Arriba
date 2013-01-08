package Arriba;

# ABSTRACT: PSGI web server with SPDY support

use strict;

our $VERSION = '0.01';

1;
__END__

=head1 SYNOPSIS

Launch a plain HTTP server listening on port 5080:

    arriba --listen :5080

Launch an HTTPS server on port 5443, no SPDY:

    arriba --listen :5443 --listen-ssl 5443 --ssl-cert-file cert.pem \
        --ssl-key-file key.pem

Launch an HTTPS server with SPDY support:

    arriba --listen :5443 --listen-ssl 5443 --ssl-cert-file cert.pem \
        --ssl-key-file key.pem --enable-spdy

=head1 DESCRIPTION

Description coming soonish.

=head1 ACKNOWLEDGEMENTS

Basic server code and plain HTTP connection support is based on L<Starman>,
written by Tatsuhiko Miyagawa.

SPDY support is provided by L<Net::SPDY>, written by Lubomir Rintel.

=head1 SEE ALSO

L<Starman>
L<Net::Server::PreFork>

=cut

