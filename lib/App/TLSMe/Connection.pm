package App::TLSMe::Connection;

use strict;
use warnings;

use constant DEBUG => $ENV{APP_TLSME_DEBUG};

use App::TLSMe::Pool;

use Scalar::Util qw(weaken);
use AnyEvent::Handle;
use AnyEvent::Socket;

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    $self->{handle} = $self->_build_handle(@_);

    return $self;
}

sub _build_handle {
    my $self = shift;
    my %args = @_;

    weaken $self;

    return AnyEvent::Handle->new(
        fh      => $self->{fh},
        tls     => 'accept',
        tls_ctx => $self->{tls_ctx},
        on_eof  => sub {
            my $handle = shift;

            DEBUG && warn "Client $self->{fh} disconnected\n";

            $self->_drop;
        },
        on_error => sub {
            my $handle = shift;
            my ($is_fatal, $message) = @_;

            DEBUG && warn "Error: $message\n";

            $self->_drop;
        },
        on_starttls => $self->_on_starttls_handler
    );
}

sub _drop {
    my $self = shift;

    DEBUG && warn "Connection $self->{fh} closed\n";

    $self->{handle}->destroy;

    App::TLSMe::Pool->remove_connection($self->{fh});

    return $self;
}

sub _on_starttls_handler {
    my $self = shift;

    weaken $self;

    return sub {
        my $handle = shift;
        my ($is_success, $message) = @_;

        if (!$is_success) {
            DEBUG && warn "TLS error: $message\n";

            return $self->_drop;
        }

        DEBUG && warn "$message\n";

        return $self->_connect_to_backend;
      }
}

sub _connect_to_backend {
    my $self = shift;

    weaken $self;

    my $backend_host = $self->{backend_host};
    my $backend_port = $self->{backend_port};

    tcp_connect $backend_host, $backend_port, sub {
        my ($backend_fh) = @_;

        if (!$backend_fh) {
            DEBUG
              && warn
              "Connection to backend $backend_host:$backend_port failed: $!\n";

            return $self->_drop;
        }

        DEBUG && warn "Connected to backend $backend_host:$backend_port\n";

        my $backend_handle = $self->{backend_handle} = AnyEvent::Handle->new(
            fh     => $backend_fh,
            on_eof => sub {
                my $backend_handle = shift;

                DEBUG && 'Backend disconnected';

                $backend_handle->destroy;

                $self->_drop;
            },
            on_error => sub {
                my $backend_handle = shift;
                my ($is_fatal, $message) = @_;

                DEBUG && warn "Backend error: $message\n";

                $backend_handle->destroy;

                $self->_drop;
            }
        );

        $self->{handle}->on_read($self->_on_send_handler);

        $backend_handle->on_read($self->_on_read_handler);
      }
}

sub _on_send_handler {
    my $self = shift;

    weaken $self;

    my $x_forwarded_for   = "X-Forwarded-For: $self->{peer_host}\x0d\x0a";
    my $x_forwarded_proto = "X-Forwarded-Proto: https\x0d\x0a";

    my $headers;
    return sub {
        my $handle = shift;

        if ($headers) {
            $self->{backend_handle}->push_write($handle->rbuf);
            $handle->rbuf = '';
        }
        elsif ($handle->rbuf
            =~ s/ (?<=\x0a)\x0d?\x0a /$x_forwarded_for$x_forwarded_proto\x0d\x0a/xms
          )
        {
            $self->{backend_handle}->push_write($handle->rbuf);
            $handle->rbuf = '';

            $headers = 1;
        }
      }
}

sub _on_read_handler {
    my $self = shift;

    weaken $self;

    return sub {
        my $backend_handle = shift;

        $self->{handle}->push_write($backend_handle->rbuf);
        $backend_handle->rbuf = '';
      }
}

1;
__END__

=head1 NAME

App::TLSMe::Connection - Connection class

=head1 SYNOPSIS

    App::TLSMe::Connection->new(
        fh => $fh,
        backend_host => 'localhost',
        backend_port => 8080,
        ...
    );

=head1 DESCRIPTION

Object-Value that holds handles, callbacks and other information associated with
proxy-backend connection.

=head1 METHODS

=head2 C<new>

    my $connection = App::TLSMe::Connection->new;

=cut
