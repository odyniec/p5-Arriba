package Arriba::Request;

sub new {
    my $class = shift;
    my $connection = shift;
    bless { connection => $connection, @_ }, $class;
}

1;

