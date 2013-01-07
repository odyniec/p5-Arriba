package Arriba::Connection;

use warnings;
use strict;

use Arriba::Request;

sub new {
    my $class = shift;
    my $client = shift;
    my $self = bless { client => $client, @_ }, $class;

    return $self;
}

sub read_request { }

sub write_response { }

1;

