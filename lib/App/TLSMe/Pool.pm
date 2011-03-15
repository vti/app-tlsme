package App::TLSMe::Pool;

use strict;
use warnings;

use App::TLSMe::Connection;

sub instance {
    my $class = shift;

    no strict;

    ${"$class\::_instance"} ||= $class->_new_instance(@_);

    return ${"$class\::_instance"};
}

sub add_connection {
    my $class = shift;
    my %args  = @_;

    my $instance = $class->instance;

    $instance->{connections}->{$args{fh}} =
      App::TLSMe::Connection->new(%args);
}

sub remove_connection {
    my $class = shift;
    my ($fh) = @_;

    my $instance = $class->instance;

    delete $instance->{connections}->{$fh};
}

sub _new_instance {
    my $class = shift;

    my $self = bless {@_}, $class;

    $self->{connections} = {};

    return $self;
}

1;
