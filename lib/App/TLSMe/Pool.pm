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
__END__

=head1 NAME

App::TLSMe::Pool - Connection pool

=head1 SYNOPSIS

    App::TLSMe::Pool->add_connection(...);

    App::TLSMe::Pool->remove_connection(...);

=head1 DESCRIPTION

Singleton connection pool.

=head1 METHODS

=head2 C<instance>

    App::TLSMe::Pool->instance;

Return instance object.

=head2 C<add_connection>

    App::TLSMe::Pool->add_connection(...);

Add new connection.

=head2 C<remove_connection>

    App::TLSMe::Pool->remove_connection(...);

Remove connection.

=cut
