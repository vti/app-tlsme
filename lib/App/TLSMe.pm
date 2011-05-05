package App::TLSMe;

use strict;
use warnings;

our $VERSION = '0.00901';

use constant DEBUG => $ENV{APP_TLSME_DEBUG};

use App::TLSMe::Pool;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

sub new {
    my $class = shift;
    my %args  = @_;

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

    $self->{cv} = AnyEvent->condvar;

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
__END__

=head1 NAME

App::TLSMe - TLS/SSL tunnel

=head1 SYNOPSIS

    App::TLSMe->new(
        listen    => ':443',
        backend   => 'localhost:8080',
        cert_file => 'cert.pem',
        key_file  => 'key.pem'
    )->run;

Run C<tlsme -h> for more options.

=head1 DESCRIPTION

This module is used by a command line application C<tlsme>. You might want to
look at its documentation instead.

=head1 METHODS

=head2 C<new>

    my $app = App::TLSMe->new;

=head2 C<run>

    $app->run;

Start the secure tunnel.

=head1 DEVELOPMENT

=head2 Repository

    http://github.com/vti/app-tlsme

=head1 AUTHOR

Viacheslav Tykhanovskyi, C<vti@cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Viacheslav Tykhanovskyi

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=cut
