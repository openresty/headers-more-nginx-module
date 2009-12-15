package Test::Nginx::Socket;

use lib 'lib';
use lib 'inc';
use Test::Base -Base;
use Data::Dumper;

our $VERSION = '0.03';

our $Timeout = 2;

use Time::HiRes qw(sleep time);
use Test::LongString;
use Test::Nginx::Util qw(
    setup_server_root
    write_config_file
    get_canon_version
    get_nginx_version
    trim
    show_all_chars
    parse_headers
    run_tests
    $ServerPortForClient
    $ServerPort
    $PidFile
    $ServRoot
    $ConfFile
    $RunTestHelper
    $RepeatEach
);

#use Smart::Comments::JSON '###';
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use POSIX qw(EAGAIN);
use IO::Socket;

#our ($PrevRequest, $PrevConfig);

our @EXPORT = qw( plan run_tests run_test );

sub send_request ($$);

sub run_test_helper ($);

$RunTestHelper = \&run_test_helper;

sub parse_request ($$) {
    my ($name, $rrequest) = @_;
    open my $in, '<', $rrequest;
    my $first = <$in>;
    if (!$first) {
        Test::More::BAIL_OUT("$name - Request line should be non-empty");
        die;
    }
    $first =~ s/^\s+|\s+$//gs;
    my ($meth, $rel_url) = split /\s+/, $first, 2;
    if (!defined $rel_url) {
        $rel_url = "/";
    }
    #my $url = "http://localhost:$ServerPortForClient" . $rel_url;

    my $content = do { local $/; <$in> };
    if (!defined $content) {
        $content = "";
    }
    #warn Dumper($content);

    close $in;

    return {
        method  => $meth,
        url     => $rel_url,
        content => $content,
    };
}

sub run_test_helper ($) {
    my $block = shift;

    my $request;
    if (defined $block->request_eval) {
        $request = eval $block->request_eval;
        if ($@) {
            warn $@;
        }
    } else {
        $request = $block->request;
    }

    my $name = $block->name;

    my $is_chunked = 0;
    my $more_headers = '';
    if ($block->more_headers) {
        my @headers = split /\n+/, $block->more_headers;
        for my $header (@headers) {
            next if $header =~ /^\s*\#/;
            my ($key, $val) = split /:\s*/, $header, 2;
            if (lc($key) eq 'transfer-encoding' and $val eq 'chunked') {
                $is_chunked = 1;
            }
            #warn "[$key, $val]\n";
            $more_headers .= "$key: $val\r\n";
        }
    }

    my $req;
    if ($block->pipelined_requests) {
        my $reqs = $block->pipelined_requests;
        if (!ref $reqs || ref $reqs ne 'ARRAY') {
            Test::More::BAIL_OUT("$name - invalid entries in --- pipelined_requests");
        }
        my $i = 0;
        for my $request (@$reqs) {
            my $conn_type;
            if ($i++ == @$reqs - 1) {
                $conn_type = 'close';
            } else {
                $conn_type = 'keep-alive';
            }
            my $parsed_req = parse_request($name, \$request);

            my $len_header = '';
            if (!$is_chunked && defined $parsed_req->{content} 
                    && $parsed_req->{content} ne ''
                    && $more_headers !~ /\bContent-Length:/)
            {
                $parsed_req->{content} =~ s/^\s+|\s+$//gs;

                $len_header .= "Content-Length: " . length($parsed_req->{content}) . "\r\n";
            }

            $req .= "$parsed_req->{method} $parsed_req->{url} HTTP/1.1\r
Host: localhost\r
Connection: $conn_type\r
$more_headers$len_header\r
$parsed_req->{content}";
        }
    } else {
        my $parsed_req = parse_request($name, \$request);
        ### $parsed_req

        my $len_header = '';
        if (!$is_chunked && defined $parsed_req->{content}
                && $parsed_req->{content} ne ''
                && $more_headers !~ /\bContent-Length:/)
        {
            $parsed_req->{content} =~ s/^\s+|\s+$//gs;
            $len_header .= "Content-Length: " . length($parsed_req->{content}) . "\r\n";
        }

        $req = "$parsed_req->{method} $parsed_req->{url} HTTP/1.1\r
Host: localhost\r
Connection: Close\r
$more_headers$len_header\r
$parsed_req->{content}";
    }

    if (!$req) {
        Test::More::BAIL_OUT("$name - request empty");
    }

    #warn "request: $req\n";

    my $timeout = $block->timeout;
    if (!defined $timeout) {
        $timeout = $Timeout;
    }

    my $raw_resp = send_request($req, $timeout);

    #warn "raw resonse: [$raw_resp]\n";

    my $res = HTTP::Response->parse($raw_resp);
    my $enc = $res->header('Transfer-Encoding');

    if (defined $enc && $enc eq 'chunked') {
        #warn "Found chunked!";
        my $raw = $res->content;
        if (!defined $raw) {
            $raw = '';
        }

        my $decoded = '';
        while (1) {
            if ($raw =~ /\G0\r\n\r\n$/gcs) {
                last;
            }
            if ($raw =~ m{ \G \ * ( [A-Fa-f0-9]+ ) \ * \r\n }gcsx) {
                my $rest = hex($1);
                #warn "chunk size: $rest\n";
                if ($raw =~ /\G(.{$rest})\r\n/gcs) {
                    $decoded .= $1;
                    #warn "decoded: [$1]\n";
                } else {
                    fail("$name - invalid chunked data received.");
                    return;
                }
            } elsif ($raw =~ /\G.+/gcs) {
                fail "$name - invalid chunked body received: $&";
                return;
            } else {
                fail "$name - no last chunk found";
                return;
            }
        }
        #warn "decoded: $decoded\n";
        $res->content($decoded);
    }

    if (defined $block->error_code) {
        is($res->code || '', $block->error_code, "$name - status code ok");
    } else {
        is($res->code || '', 200, "$name - status code ok");
    }

    if (defined $block->response_headers) {
        my $headers = parse_headers($block->response_headers);
        while (my ($key, $val) = each %$headers) {
            my $expected_val = $res->header($key);
            if (!defined $expected_val) {
                $expected_val = '';
            }
            is $expected_val, $val,
                "$name - header $key ok";
        }
    } elsif (defined $block->response_headers_like) {
        my $headers = parse_headers($block->response_headers_like);
        while (my ($key, $val) = each %$headers) {
            my $expected_val = $res->header($key);
            if (!defined $expected_val) {
                $expected_val = '';
            }
            like $expected_val, qr/^$val$/,
                "$name - header $key like ok";
        }
    }

    if (defined $block->response_body
           || defined $block->response_body_eval) {
        my $content = $res->content;
        if (defined $content) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
            $content =~ s/^Connection: TE, close\r\n//gms;
        }

        my $expected;
        if ($block->response_body_eval) {
            $expected = eval $block->response_body_eval;
            if ($@) {
                warn $@;
            }
        } else {
            $expected = $block->response_body;
        }

        $expected =~ s/\$ServerPort\b/$ServerPort/g;
        $expected =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;
        #warn show_all_chars($content);

        is_string($content, $expected, "$name - response_body - response is expected");
        #is($content, $expected, "$name - response_body - response is expected");

    } elsif (defined $block->response_body_like) {
        my $content = $res->content;
        if (defined $content) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
        }
        $content =~ s/^Connection: TE, close\r\n//gms;
        my $expected_pat = $block->response_body_like;
        $expected_pat =~ s/\$ServerPort\b/$ServerPort/g;
        $expected_pat =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;
        my $summary = trim($content);
        like($content, qr/$expected_pat/s, "$name - response_body_like - response is expected ($summary)");
    }
}

sub send_request ($$) {
    my ($write_buf, $timeout) = @_;

    my $sock = IO::Socket::INET->new(
        PeerAddr => 'localhost',
        PeerPort => $ServerPortForClient,
        Proto    => 'tcp'
    ) or die "Can't connect to localhost:$ServerPortForClient: $!\n";

    my $flags = fcntl $sock, F_GETFL, 0
        or die "Failed to get flags: $!\n";

    fcntl $sock, F_SETFL, $flags | O_NONBLOCK
        or die "Failed to set flags: $!\n";

    my $resp = '';
    my $write_offset = 0;
    my $buf_size = 1024;

    my $now = time;
    while (1) {
        if (time - $now >= $timeout) {
            warn "timed out\n";
            return $resp;
        }
        #warn "main loop...";
        my $read_buf;
        my $bytes = sysread($sock, $read_buf, $buf_size);

        if (!defined $bytes) {
            if ($! == EAGAIN) {
                #warn "read again...";
                #sleep 0.002;
                goto write_sock;
            }
            return "500 read failed: $!";
        }
        if ($bytes == 0) {
            close $sock;
            #warn "returning response: $resp\n";
            return $resp;
        }
        $resp .= $read_buf;
        #warn "read $bytes ($read_buf) bytes.\n";

write_sock:
        my $rest = length($write_buf) - $write_offset;
        #warn "offset: $write_offset, rest: $rest, length ", length($write_buf), "\n";
        #die;

        if ($rest > 0) {
            $bytes = syswrite($sock, $write_buf, $rest, $write_offset);

            if (!defined $bytes) {
                if ($! == EAGAIN) {
                    #warn "write again...";
                    #sleep 0.002;
                    next;
                }
                my $errmsg = "write failed: $!";
                warn "$errmsg\n";
                if (!$resp) {
                    return "$errmsg";
                }
                return $resp;
            }

            #warn "wrote $bytes bytes.\n";
            $write_offset += $bytes;
        }
    }
    return $resp;
}

1;
__END__

=encoding utf-8

=head1 NAME

Test::Nginx::Socket - Socket-backed test scaffold for the Nginx C modules

=head1 SYNOPSIS

    use Test::Nginx::Socket;

    plan tests => $Test::Nginx::Socket::RepeatEach * 2 * blocks();

    run_tests();

    __DATA__

    === TEST 1: sanity
    --- config
        location /echo {
            echo_before_body hello;
            echo world;
        }
    --- request
        GET /echo
    --- response_body
    hello
    world
    --- error_code: 200


    === TEST 2: set Server
    --- config
        location /foo {
            echo hi;
            more_set_headers 'Server: Foo';
        }
    --- request
        GET /foo
    --- response_headers
    Server: Foo
    --- response_body
    hi


    === TEST 3: clear Server
    --- config
        location /foo {
            echo hi;
            more_clear_headers 'Server: ';
        }
    --- request
        GET /foo
    --- response_headers_like
    Server: nginx.*
    --- response_body
    hi


    === TEST 3: chunk size too small
    --- config
        chunkin on;
        location /main {
            echo_request_body;
        }
    --- more_headers
    Transfer-Encoding: chunked
    --- request eval
    "POST /main
    4\r
    hello\r
    0\r
    \r
    "
    --- error_code: 400
    --- response_body_like: 400 Bad Request

=head1 DESCRIPTION

This module provides a test scaffold based on non-blocking L<IO::Socket> for automated testing in Nginx C module development.

This class inherits from L<Test::Base>, thus bringing all its
declarative power to the Nginx C module testing practices.

You need to terminate or kill any Nginx processes before running the test suite if you have changed the Nginx server binary. Normally it's as simple as

  killall nginx
  PATH=/path/to/your/nginx-with-memc-module:$PATH prove -r t

This module will create a temporary server root under t/servroot/ of the current working directory and starts and uses the nginx executable in the PATH environment.

You will often want to look into F<t/servroot/logs/error.log>
when things go wrong ;)

=head1 Sections supported

The following sections are supported:

=over

=item config

=item request

=item request_eval

=item more_headers

=item response_body

=item response_body_eval

=item response_body_like

=item response_headers

=item response_headers_like

=item error_code

=back

=head1 Samples

You'll find live samples in the following Nginx 3rd-party modules:

=over

=item ngx_chunkin

L<http://wiki.nginx.org/NginxHttpChunkinModule>

=item ngx_memc

L<http://wiki.nginx.org/NginxHttpMemcModule>

=back

=head1 AUTHOR

agentzh (章亦春) C<< <agentzh@gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright (c) 2009, Taobao Inc., Alibaba Group (L<http://www.taobao.com>).

Copyright (c) 2009, agentzh C<< <agentzh@gmail.com> >>.

This module is licensed under the terms of the BSD license.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

=over

=item *

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

=item *

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

=item *

Neither the name of the Taobao Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission. 

=back

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 

=head1 SEE ALSO

L<Test::Nginx::LWP>, L<Test::Base>.

