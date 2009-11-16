package Test::Nginx::LWP;

our $NoNginxManager = 0;

use lib 'lib';
use lib 'inc';
use Time::HiRes qw(sleep);

#use Smart::Comments::JSON '##';
use LWP::UserAgent; # XXX should use a socket level lib here
use Test::Base -Base;
use Module::Install::Can;
use List::Util qw( shuffle );
use File::Spec ();
use Cwd qw( cwd );

our $UserAgent = LWP::UserAgent->new;
$UserAgent->agent("Test::Nginx::LWP");
#$UserAgent->default_headers(HTTP::Headers->new);

our $Workers                = 1;
our $WorkerConnections      = 1024;
our $LogLevel               = 'debug';
#our $MasterProcessEnabled   = 'on';
#our $DaemonEnabled          = 'on';
our $ServerPort             = 1984;

#our ($PrevRequest, $PrevConfig);

our $ServRoot   = File::Spec->catfile(cwd(), 't/servroot');
our $LogDir     = File::Spec->catfile($ServRoot, 'logs');
our $ErrLogFile = File::Spec->catfile($LogDir, 'error.log');
our $AccLogFile = File::Spec->catfile($LogDir, 'access.log');
our $HtmlDir    = File::Spec->catfile($ServRoot, 'html');
our $ConfDir    = File::Spec->catfile($ServRoot, 'conf');
our $ConfFile   = File::Spec->catfile($ConfDir, 'nginx.conf');
our $PidFile    = File::Spec->catfile($LogDir, 'nginx.pid');

our @EXPORT = qw( run_tests run_test );

sub trim ($);

sub show_all_chars ($);

sub run_tests () {
    for my $block (shuffle blocks()) {
        run_test($block);
    }
}

sub setup_server_root () {
    if (-d $ServRoot) {
        #sleep 0.5;
        #die ".pid file $PidFile exists.\n";
        system("rm -rf t/servroot > /dev/null") == 0 or
            die "Can't remove t/servroot";
        #sleep 0.5;
    }
    mkdir $ServRoot or
        die "Failed to do mkdir $ServRoot\n";
    mkdir $LogDir or
        die "Failed to do mkdir $LogDir\n";
    mkdir $HtmlDir or
        die "Failed to do mkdir $HtmlDir\n";
    mkdir $ConfDir or
        die "Failed to do mkdir $ConfDir\n";
}

sub write_config_file ($) {
    my $rconfig = shift;
    open my $out, ">$ConfFile" or
        die "Can't open $ConfFile for writing: $!\n";
    print $out <<_EOC_;
worker_processes  $Workers;
daemon on;
master_process on;
error_log $ErrLogFile $LogLevel;
pid       $PidFile;

http {
    access_log $AccLogFile;

    default_type text/plain;
    keepalive_timeout  65;
    server {
        listen          $ServerPort;
        server_name     localhost;

        client_max_body_size 30M;
        #client_body_buffer_size 4k;

        # Begin test case config...
$$rconfig
        # End test case config.

        location / {
            root $HtmlDir;
            index index.html index.htm;
        }
    }
}

events {
    worker_connections  $WorkerConnections;
}

_EOC_
    close $out;
}

sub parse_request ($$) {
    my ($name, $rrequest) = @_;
    open my $in, '<', $rrequest;
    my $first = <$in>;
    if (!$first) {
        Test::More::BAIL_OUT("$name - Request line should be non-empty");
        die;
    }
    $first =~ s/^\s+|\s+$//g;
    my ($meth, $rel_url) = split /\s+/, $first, 2;
    my $url = "http://localhost:$ServerPort" . $rel_url;

    my $content = do { local $/; <$in> };
    if ($content) {
        $content =~ s/^\s+|\s+$//s;
    }

    close $in;

    return {
        method  => $meth,
        url     => $url,
        content => $content,
    };
}

sub get_pid_from_pidfile ($) {
    my ($name) = @_;
    open my $in, $PidFile or
        Test::More::BAIL_OUT("$name - Failed to open the pid file $PidFile for reading: $!");
    my $pid = do { local $/; <$in> };
    #warn "Pid: $pid\n";
    close $in;
    $pid;
}

sub chunk_it ($$$) {
    my ($chunks, $start_delay, $middle_delay) = @_;
    my $i = 0;
    return sub {
        if ($i == 0) {
            if ($start_delay) {
                sleep($start_delay);
            }
        } elsif ($middle_delay) {
            sleep($middle_delay);
        }
        return $chunks->[$i++];
    }
}

sub run_test ($) {
    my $block = shift;
    my $name = $block->name;
    my $request = $block->request;
    if (!defined $request) {
        #$request = $PrevRequest;
        #$PrevRequest = $request;
        Test::More::BAIL_OUT("$name - No '--- request' section specified");
        die;
    }

    my $config = $block->config;
    if (!defined $config) {
        Test::More::BAIL_OUT("$name - No '--- config' section specified");
        #$config = $PrevConfig;
        die;
    }

    if (!$NoNginxManager) {
        my $nginx_is_running = 1;
        if (-f $PidFile) {
            my $pid = get_pid_from_pidfile($name);
            if (system("ps $pid > /dev/null") == 0) {
                write_config_file(\$config);
                if (kill(1, $pid) == 0) { # send HUP signal
                    Test::More::BAIL_OUT("$name - Failed to send signal to the nginx process with PID $pid using signal HUP");
                }
                sleep 0.02;
            } else {
                unlink $PidFile or
                    die "Failed to remove pid file $PidFile\n";
                undef $nginx_is_running;
            }
        } else {
            undef $nginx_is_running;
        }

        unless ($nginx_is_running) {
            setup_server_root();
            write_config_file(\$config);
            if ( ! Module::Install::Can->can_run('nginx') ) {
                Test::More::BAIL_OUT("$name - Cannot find the nginx executable in the PATH environment");
                die;
            }
        #if (system("nginx -p $ServRoot -c $ConfFile -t") != 0) {
        #Test::More::BAIL_OUT("$name - Invalid config file");
        #}
        #my $cmd = "nginx -p $ServRoot -c $ConfFile > /dev/null";
            my $cmd = "nginx -c $ConfFile > /dev/null";
            if (system($cmd) != 0) {
                Test::More::BAIL_OUT("$name - Cannot start nginx using command \"$cmd\".");
                die;
            }
            sleep 0.1;
        }
    }

    my $req_spec = parse_request($name, \$request);
    ## $req_spec
    my $method = $req_spec->{method};
    my $req = HTTP::Request->new($method);
    my $content = $req_spec->{content};
    #$req->header('Content-Type' => $type);
    #$req->header('Accept', '*/*');
    $req->url($req_spec->{url});
    if ($content) {
        if ($method eq 'GET' or $method eq 'HEAD') {
            croak "HTTP 1.0/1.1 $method request should not have content: $content";
        }
        $req->content($content);
    } elsif ($method eq 'POST' or $method eq 'PUT') {
        my $chunks = $block->chunked_body;
        if (defined $chunks) {
            if (!ref $chunks or ref $chunks ne 'ARRAY') {

                Test::More::BAIL_OUT("$name - --- chunked_body should takes a Perl array ref as its value");
            }

            my $start_delay = $block->start_chunk_delay || 0;
            my $middle_delay = $block->middle_chunk_delay || 0;
            $req->content(chunk_it($chunks, $start_delay, $middle_delay));
            $req->header('Content-Type' => 'text/plain');
        } else {
            $req->header('Content-Type' => 'text/plain');
            $req->header('Content-Length' => 0);
        }
    }

    if ($block->more_headers) {
        my @headers = split /\n+/, $block->more_headers;
        for my $header (@headers) {
            next if $header =~ /^\s*\#/;
            my ($key, $val) = split /:\s*/, $header, 2;
            warn "[$key, $val]\n";
            $req->header($key => $val);
        }
    }
    #warn "DONE!!!!!!!!!!!!!!!!!!!!";

    my $res = $UserAgent->request($req);

    #warn "res returned!!!";

    if (defined $block->error_code) {
        is($res->code, $block->error_code, "$name - status code ok");
    } else {
        is($res->code, 200, "$name - status code ok");
    }

    if (defined $block->response_body) {
        my $content = $res->content;
        if (defined $content) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
        }
        $content =~ s/^Connection: TE, close\r\n//gms;
        my $expected = $block->response_body;
        $expected =~ s/\$ServerPort\b/$ServerPort/g;
        #warn show_all_chars($content);
        is($content, $expected, "$name - response_body - response is expected");
    } elsif (defined $block->response_body_like) {
        my $content = $res->content;
        if (defined $content) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
        }
        $content =~ s/^Connection: TE, close\r\n//gms;
        my $expected_pat = $block->response_body_like;
        $expected_pat =~ s/\$ServerPort\b/$ServerPort/g;
        my $summary = trim($content);
        like($content, qr/$expected_pat/sm, "$name - response_body_like - response is expected ($summary)");
    }
}

sub trim ($) {
    (my $s = shift) =~ s/^\s+|\s+$//g;
    $s =~ s/\n/ /gs;
    $s =~ s/\s{2,}/ /gs;
    $s;
}

sub show_all_chars ($) {
    my $s = shift;
    $s =~ s/\n/\\n/gs;
    $s =~ s/\r/\\r/gs;
    $s =~ s/\t/\\t/gs;
    $s;
}

1;
__END__

=head1 NAME

Test::Nginx::LWP - Test scaffold for the echo Nginx module

=head1 AUTHOR

agentzh C<< <agentzh@gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 by agentzh.
Copyright (C) 2009 by Taobao Inc. ( http://www.taobao.com )

This software is licensed under the terms of the BSD License.

