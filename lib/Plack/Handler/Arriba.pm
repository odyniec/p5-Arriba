package Plack::Handler::Arriba;

use strict;

# ABSTRACT: Plack adapter for Arriba

use Arriba::Server;

sub new {
    my $class = shift;
    bless { @_ }, $class;
}

sub run {
    my ($self, $app) = @_;

    Arriba::Server->new->run($app, {%$self});
}

1;
__END__

=head1 SYNOPSIS

    plackup -s Arriba --listen :5443 --listen-ssl 5443 --enable-spdy \
        --ssl-cert-file cert.pem --ssl-key-file key.pem app.psgi

=cut
