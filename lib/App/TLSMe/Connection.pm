package App::TLSMe::Connection;

use strict;
use warnings;

use Scalar::Util qw(weaken);
use AnyEvent::Handle;
use AnyEvent::Socket;

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    $self->{handle} = $self->_build_handle();

    $self->{on_eof}           ||= sub { };
    $self->{on_error}         ||= sub { };
    $self->{on_backend_error} ||= sub { };

    return $self;
}

sub write {
    my $self = shift;

    $self->{handle}->push_write(@_);
}

sub _build_handle {
    my $self = shift;

    weaken $self;

    return AnyEvent::Handle->new(
        fh      => $self->{fh},
        tls     => 'accept',
        tls_ctx => $self->{tls_ctx},
        on_eof  => sub {
            my $handle = shift;

            if (my $backend_handle = delete $self->{backend_handle}) {
                $self->{on_backend_eof}->($self);
                $self->_close_handle($backend_handle);
            }

            $self->_drop;
        },
        on_error => sub {
            my $handle = shift;
            my ($is_fatal, $message) = @_;

            if (my $backend_handle = delete $self->{backend_handle}) {
                $self->{on_backend_error}->($self, $message || $!);
                $self->_close_handle($backend_handle);
            }

            $self->_drop($message);
        },
        on_starttls => $self->_on_starttls_handler
    );
}

sub _drop {
    my $self = shift;
    my ($error) = @_;

    if (defined $error) {
        $self->{on_error}->($self, $error);
    }
    else {
        $self->{on_eof}->($self);
    }

    my $handle = delete $self->{handle};

    $self->_close_handle($handle);

    undef $handle;

    return $self;
}

sub _on_starttls_handler {
    my $self = shift;

    weaken $self;

    return sub {
        my $handle = shift;
        my ($is_success, $message) = @_;

        if (!$is_success) {
            return $self->_drop($message);
        }

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
            $self->{on_backend_error}->($self, $! || 'Connection refused');
            return $self->_drop;
        }

        $self->{on_backend_connected}->($self);

        return unless $self->{handle};

        my $backend_handle = $self->{backend_handle} = AnyEvent::Handle->new(
            fh     => $backend_fh,
            on_eof => sub {
                my $backend_handle = shift;

                $self->{on_backend_eof}->($self);

                $self->_close_handle($backend_handle);
                delete $self->{backend_handle};

                $self->_drop;
            },
            on_error => sub {
                my $backend_handle = shift;
                my ($is_fatal, $message) = @_;

                $self->{on_backend_error}->($self, $message);

                $self->_close_handle($backend_handle);
                delete $self->{backend_handle};

                $self->_drop;
            }
        );

        if ($backend_handle) {
            $self->{handle}->on_read($self->_on_send_handler);

            $backend_handle->on_read($self->_on_read_handler);
        }
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
            $handle->{rbuf} = '';
        }
        elsif ($handle->rbuf
            =~ s/ (?<=\x0a)\x0d?\x0a /$x_forwarded_for$x_forwarded_proto\x0d\x0a/xms
          )
        {
            $self->{backend_handle}->push_write($handle->rbuf);
            $handle->{rbuf} = '';

            $headers = 1;
        }
      }
}

sub _on_read_handler {
    my $self = shift;

    weaken $self;

    return sub {
        my ($backend_handle) = @_ or return;

        $self->{handle}->push_write($backend_handle->rbuf);
        $backend_handle->{rbuf} = '';
      }
}

sub _close_handle {
    my $self = shift;
    my ($handle) = @_;

    $handle->wtimeout(0);

    $handle->on_drain;
    $handle->on_error;

    $handle->on_drain(
        sub {
            if ($_[0]->fh) {
                shutdown $_[0]->fh, 1;
                close $handle->fh;
            }

            $_[0]->destroy;
            undef $handle;
        }
    );

    undef $handle;
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

=head2 C<write>

    $connection->write(...);

=cut
