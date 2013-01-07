package Arriba::Request;

use warnings;
use strict;

sub new {
    my $class = shift;
    my $connection = shift;
    bless { connection => $connection, @_ }, $class;
}

1;

