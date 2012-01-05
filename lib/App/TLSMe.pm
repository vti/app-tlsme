package App::TLSMe;

use strict;
use warnings;

our $VERSION = '0.009002';

use constant DEBUG => $ENV{APP_TLSME_DEBUG};

use File::Spec;
require Carp;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

use App::TLSMe::Pool;

use constant CERT => <<'EOF';
-----BEGIN CERTIFICATE-----
MIICsDCCAhmgAwIBAgIJAPZgxGgzkLMkMA0GCSqGSIb3DQEBBQUAMEUxCzAJBgNV
BAYTAkFVMRMwEQYDVQQIEwpTb21lLVN0YXRlMSEwHwYDVQQKExhJbnRlcm5ldCBX
aWRnaXRzIFB0eSBMdGQwHhcNMTEwMzE1MDgxMzExWhcNMzEwMzEwMDgxMzExWjBF
MQswCQYDVQQGEwJBVTETMBEGA1UECBMKU29tZS1TdGF0ZTEhMB8GA1UEChMYSW50
ZXJuZXQgV2lkZ2l0cyBQdHkgTHRkMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKB
gQClL0W4K2Ux4ntepXG4Z4sHPn/KR7efIwy6ciEnOBFa8JPnnP2ZI8b4ifS8ayC0
VqwzZgYEb+roCM2BZ8oJIxGkwS0iwb/16KDgw4ODrIT5c9gRnpbezLpbolbChQMb
rhhH9qPswVPGXFdWIudgZ9bWV1NDGPdvt7tmxryWQO2PEQIDAQABo4GnMIGkMB0G
A1UdDgQWBBTlwxPDs2JacAUoc8KSDPNDKTEZ3TB1BgNVHSMEbjBsgBTlwxPDs2Ja
cAUoc8KSDPNDKTEZ3aFJpEcwRTELMAkGA1UEBhMCQVUxEzARBgNVBAgTClNvbWUt
U3RhdGUxITAfBgNVBAoTGEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZIIJAPZgxGgz
kLMkMAwGA1UdEwQFMAMBAf8wDQYJKoZIhvcNAQEFBQADgYEAGtfsSndB3GftZKEa
74bgp8UZNJJT9W2bQgHFoL/4Tjl9CpoAtNR0wuTO7TvV+jzhON85YkMR83OQ4ol4
J+ew017cvKvsk5lKNZhgX8d+CBgWHh5FBZA19TYmH4RgV0ZKGJnDky2CR3fdcHnk
ChexCtgZ2nIYm3W/Z7wRA+xjHok=
-----END CERTIFICATE-----
EOF

use constant KEY => << 'EOF';
-----BEGIN RSA PRIVATE KEY-----
MIICXwIBAAKBgQClL0W4K2Ux4ntepXG4Z4sHPn/KR7efIwy6ciEnOBFa8JPnnP2Z
I8b4ifS8ayC0VqwzZgYEb+roCM2BZ8oJIxGkwS0iwb/16KDgw4ODrIT5c9gRnpbe
zLpbolbChQMbrhhH9qPswVPGXFdWIudgZ9bWV1NDGPdvt7tmxryWQO2PEQIDAQAB
AoGBAJkpduzol+EkTh4ZK5O/tmKWKemGjBTra97o+iKiUz1OOuYUY/R9/vzu9dVL
Q7zTbMIPxF6S424Y02w8r1G/iZgLt3HjbYEbkBZWFIIH4CTttnd5IjtRsJvVkFU3
YR6bWG4qvoqVxdlb2cE8BJofdM3f/zYkoP1UEBcwdUXLAvGdAkEA1jidDz7CgbN2
2TS33/p6lHb4C9f+DedlWOJYzzBkfExOE1J1UdxzUtB4K6iZeE5idELCiOtXsxeV
5Efahob4NwJBAMVma+lD8KVCZR/lOyAK3F9SHTgP1Wi3/Dawrq8Cc3emNusSLzsO
kFSoW8p0jZUKx2PVO0Z1D3ls/UXPHBc/fvcCQQCAJJ929iDd+x+V8J4pYikfVEcu
toanhIqwb72WOqlxXSe7ETFSxZ9Ko5+u5gzf1Wu5hhHeW4E7hVlJk93ZaTVjAkEA
mjj04iAEaPjAjPTJBrW1inta/KvSLahg0lGjiHO/xqEDkxB3+gnc1Wdbn4cD/oeX
U/YKA3f9iP6PufSfm8It7QJBAMZmOUrkGJyScCVP7ugzLliGExtYQeuXtl+79sOz
M+T4ZKNBUAz3HOOy3HTMs1bpudLd/Jgpi9ftbW+0+fZ07II=
-----END RSA PRIVATE KEY-----
EOF

sub new {
    my $class = shift;
    my %args  = @_;

    my ($host, $port) = split ':', delete $args{listen}, -1;
    $host ||= '0.0.0.0';
    $port ||= 443;

    my ($backend_host, $backend_port);
    if ($args{backend} =~ m/:\d+$/) {
        ($backend_host, $backend_port) = split ':', delete $args{backend}, -1;
        $backend_host ||= '127.0.0.1';
        $backend_port ||= 8080;
    }
    else {
        $backend_host = 'unix/';
        $backend_port = File::Spec->rel2abs($args{backend});
    }

    my $tls_ctx = {method => $args{method}};

    if (!defined $args{cert_file} && !defined $args{key_file}) {
        DEBUG && warn "Using default certificate and private key values\n";

        $tls_ctx = {%$tls_ctx, cert => CERT, key => KEY};
    }
    elsif (defined $args{cert_file} && defined $args{key_file}) {
        Carp::croak("Certificate file '$args{cert_file}' does not exist")
          unless -f $args{cert_file};
        Carp::croak("Private key file '$args{key_file}' does not exist")
          unless -f $args{key_file};

        $tls_ctx = {
            cert_file => $args{cert_file},
            key_file  => $args{key_file} % $tls_ctx
        };
    }
    else {
        Carp::croak('Either both cert_file and key_file must be specified '
              . 'or both omitted (default cert and key will be used)');
    }

    my $self = {
        host         => $host,
        port         => $port,
        backend_host => $backend_host,
        backend_port => $backend_port,
        tls_ctx      => $tls_ctx
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

sub stop {
    my $self = shift;

    $self->{cv}->send;

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
            tls_ctx      => $self->{tls_ctx},
            on_eof       => sub {
                my ($conn) = @_;

                App::TLSMe::Pool->remove_connection($fh);
            },
            on_error => sub {
                my ($conn, $error) = @_;

                if ($error =~ m/ssl23_get_client_hello: http request/) {
                    my $response = $self->_build_http_response(
                        '501 Not Implemented',
                        '<h1>501 Not Implemented</h1><p>Maybe <code>https://</code> instead of <code>http://</code>?</p>'
                    );

                    syswrite $fh, $response;
                }

                App::TLSMe::Pool->remove_connection($fh);
            },
            on_backend_eof => sub {
            },
            on_backend_error => sub {
                my ($conn, $message) = @_;

                my $response = $self->_build_http_response('502 Bad Gateway',
                    '<h1>502 Bad Gateway</h1>');

                $conn->write($response);
            }
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

sub _build_http_response {
    my $self = shift;
    my ($status_message, $body) = @_;

    my $length = length($body);

    return join "\015\012", "HTTP/1.1 $status_message",
      "Content-Length: $length", "", $body;
}

1;
__END__

=head1 NAME

App::TLSMe - TLS/SSL tunnel

=head1 SYNOPSIS

    App::TLSMe->new(
        listen    => ':443',
        backend   => '127.0.0.1:8080',
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

=head2 C<stop>

    $app->stop;

Stop the secure tunnel (used for testing).

=head1 DEVELOPMENT

=head2 Repository

    http://github.com/vti/app-tlsme

=head1 AUTHOR

Viacheslav Tykhanovskyi, C<vti@cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Viacheslav Tykhanovskyi

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=cut
