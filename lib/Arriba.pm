package Arriba;

use strict;

# ABSTRACT: PSGI web server with SPDY support

# VERSION

1;
__END__

=head1 SYNOPSIS

Launch a plain HTTP server listening on port 5080:

    arriba --listen :5080

Launch an HTTPS server on port 5443, no SPDY:

    arriba --listen :5443:ssl --ssl-cert cert.pem --ssl-key key.pem

Launch an HTTPS server with SPDY support:

    arriba --listen :5443:ssl --ssl-cert cert.pem --ssl-key key.pem \
        --enable-spdy

=head1 DESCRIPTION

Arriba is a PSGI web server based on L<Starman> and sharing most of its
features, with added support for the SPDY protocol.

B<WARNING:> Arriba is still in early stage of development and is not ready for
production use.

=head1 ACKNOWLEDGEMENTS

Basic server code and plain HTTP connection support is based on L<Starman>,
written by Tatsuhiko Miyagawa.

SPDY support is provided by L<Net::SPDY>, written by Lubomir Rintel.

=head1 SEE ALSO

L<Starman>
L<Net::Server::PreFork>

=cut
