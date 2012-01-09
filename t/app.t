use strict;
use warnings;

use Test::More;
use Test::TCP;

plan skip_all => 'set TEST_APP to enable this test' unless $ENV{TEST_APP};

use AnyEvent;
use AnyEvent::Impl::Perl;
use AnyEvent::Socket;

use App::TLSMe;

my $host         = '127.0.0.1';
my $port         = _free_port();
my $backend_host = '127.0.0.1';
my $backend_port = _free_port();

tcp_server $backend_host, $backend_port, sub {
    my ($fh, $host, $port) = @_;

    syswrite $fh, "200 OK\015\012";
};

my $tlsme = App::TLSMe->new(
    listen  => "$host:$port",
    backend => "$backend_host:$backend_port"
);

my $handle = AnyEvent::Handle->new(
    connect => [$host, $port],
    tls     => "connect",
    tls_ctx => {},
    on_read => sub {
        my ($handle) = @_;

        $handle->push_read(
            line => sub {
                is($_[1], '200 OK');
            }
        );
    },
    on_eof => sub {
        $tlsme->stop;
    }
);

$handle->push_write(<<"EOF");
GET / HTTP/1.1

EOF

$tlsme->run;

done_testing;

sub _free_port {
    my ($from, $to) = @_;

# http://enwp.org/List_of_TCP_and_UDP_port_numbers#Dynamic.2C_private_or_ephemeral_ports
    $from ||= 49152;
    $to   ||= 65535;
    my $try = 0;
    while ($try <= 20) {
        my $port = int $from + rand $to - $from;
        my $socket;
        $socket = IO::Socket::INET->new(
            Proto    => 'tcp',
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
        );
        if ($socket) {    # can connect, so port is occupied by someone else
            $socket->close;
            next;
        }
        $socket = IO::Socket::INET->new(
            Listen    => 5,
            LocalAddr => '127.0.0.1',
            LocalPort => $port,
            Proto     => 'tcp',
            ReuseAddr => 1,
        );
        if ($socket) {    # ok, can bind, use this
            $socket->close;
            return $port;
        }
        $try++;
    }
    die "Could not find an unused port between $from and $to.\n";
}
