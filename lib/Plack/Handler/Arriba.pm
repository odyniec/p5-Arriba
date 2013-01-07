package Plack::Handler::Arriba;

use strict;
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

