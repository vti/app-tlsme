package App::TLSMe;

use strict;
use warnings;

use constant DEBUG => $ENV{APP_TLSME_DEBUG};

use App::TLSMe::Pool;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

sub new {
    my $class = shift;
    my %args = @_;

    my ($host, $port) = split ':', delete $args{listen}, -1;
    $host ||= '0.0.0.0';
    $port ||= 443;

    my ($backend_host, $backend_port) = split ':', delete $args{backend}, -1;
    $backend_host ||= 'localhost';
    $backend_port ||= 8080;

    my $self = {
        host         => $host,
        port         => $port,
        backend_host => $backend_host,
        backend_port => $backend_port,
        @_
    };
    bless $self, $class;

    $self->{clients} = {};
    $self->{cv}      = AnyEvent->condvar;

    $self->_listen;

    return $self;
}

sub run {
    my $self = shift;

    $self->{cv}->wait;

    return $self;
}

sub _listen {
    my $self = shift;

    tcp_server $self->{host}, $self->{port}, $self->_accept_handler,
      $self->_bind_handler;
}

sub _accept_handler {
    my $self = shift;

    return sub {
        my ($fh, $peer_host, $peer_port) = @_;

        DEBUG
          && warn "Accepted connection $fh from $peer_host:$peer_port\n";

        App::TLSMe::Pool->add_connection(
            fh           => $fh,
            backend_host => $self->{backend_host},
            backend_port => $self->{backend_port},
            peer_host    => $peer_host,
            peer_port    => $peer_port,
            cert_file    => $self->{cert_file},
            key_file     => $self->{key_file}
        );
      };
}

sub _bind_handler {
    my $self = shift;

    return sub {
        my ($fh, $host, $port) = @_;

        DEBUG && warn "Listening on $host:$port\n";

        return 8;
    };
}

1;
