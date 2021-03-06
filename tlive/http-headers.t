use strict;
use warnings;

use lib 'tlive/lib';

use Test::More;

use AnyEvent;
use AnyEvent::Impl::Perl;
use AnyEvent::Socket;
use IO::Socket;

use App::TLSMe;
use App::TLSMe::Logger;
use FreePort;

my $host         = '127.0.0.1';
my $port         = FreePort->get_free_port();
my $backend_host = '127.0.0.1';
my $backend_port = FreePort->get_free_port();

my $request = '';
tcp_server $backend_host, $backend_port, sub {
    my ($fh, $host, $port) = @_;

    my $handle;
    $handle = AnyEvent::Handle->new(
        fh      => $fh,
        on_read => sub {
            $handle->push_read(
                sub {
                    $request .= $_[0]->rbuf;

                    if ($request) {
                        $handle->push_write("200 OK\015\012");
                        undef $handle;
                    }
                }
            );
        }
    );
};

my $null = '';
open my $fh, '>', \$null;
my $tlsme = App::TLSMe->new(
    logger    => App::TLSMe::Logger->new(fh => $fh),
    cert_file => 'tlive/cert',
    key_file  => 'tlive/key',
    listen    => "$host:$port",
    backend   => "$backend_host:$backend_port"
);

my $handle;
$handle = AnyEvent::Handle->new(
    connect => [$host, $port],
    tls     => "connect",
    tls_ctx => {},
    on_read => sub {
        my ($handle) = @_;

        $handle->push_read(line => sub { });
    },
    on_error => sub {
        $tlsme->stop;
    },
    on_eof => sub {
        $tlsme->stop;
    }
);

$handle->push_write(<<"EOF");
GET / HTTP/1.1

EOF

$tlsme->run;

$request =~ s/\r|\n//g;
is($request,
    'GET / HTTP/1.1X-Forwarded-For: 127.0.0.1X-Forwarded-Proto: https');

done_testing;
