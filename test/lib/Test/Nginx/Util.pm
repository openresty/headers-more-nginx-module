package Test::Nginx::Util;

use strict;
use warnings;

our $VERSION = '0.10';

use base 'Exporter';

use POSIX qw( SIGQUIT SIGKILL SIGTERM );
use File::Spec ();
use HTTP::Response;
use Cwd qw( cwd );
use List::Util qw( shuffle );
use Time::HiRes qw( sleep );
use ExtUtils::MakeMaker ();

our $LatestNginxVersion = 0.008039;

our $NoNginxManager = 0;
our $Profiling = 0;

our $RepeatEach = 1;
our $MAX_PROCESSES = 10;

our $NoShuffle = $ENV{TEST_NGINX_NO_SHUFFLE} || 0;

our $UseValgrind = $ENV{TEST_NGINX_USE_VALGRIND};

sub no_shuffle () {
    $NoShuffle = 1;
}

our $ForkManager;

if ($Profiling || $UseValgrind) {
    eval "use Parallel::ForkManager";
    if ($@) {
        die "Failed to load Parallel::ForkManager: $@\n";
    }
    $ForkManager = new Parallel::ForkManager($MAX_PROCESSES);
}

our $NginxBinary            = $ENV{TEST_NGINX_BINARY} || 'nginx';
our $Workers                = 1;
our $WorkerConnections      = 64;
our $LogLevel               = $ENV{TEST_NGINX_LOG_LEVEL} || 'debug';
our $MasterProcessEnabled   = $ENV{TEST_NGINX_MASTER_PROCESS} || 'off';
our $DaemonEnabled          = 'on';
our $ServerPort             = $ENV{TEST_NGINX_SERVER_PORT} || $ENV{TEST_NGINX_PORT} || 1984;
our $ServerPortForClient    = $ENV{TEST_NGINX_CLIENT_PORT} || $ENV{TEST_NGINX_PORT} || 1984;
our $NoRootLocation         = 0;
our $TestNginxSleep         = $ENV{TEST_NGINX_SLEEP} || 0;

sub repeat_each (@) {
    if (@_) {
        $RepeatEach = shift;
    } else {
        return $RepeatEach;
    }
}

sub worker_connections (@) {
    if (@_) {
        $WorkerConnections = shift;
    } else {
        return $WorkerConnections;
    }
}

sub no_root_location () {
    $NoRootLocation = 1;
}

sub workers (@) {
    if (@_) {
        #warn "setting workers to $_[0]";
        $Workers = shift;
    } else {
        return $Workers;
    }
}

sub log_level (@) {
    if (@_) {
        $LogLevel = shift;
    } else {
        return $LogLevel;
    }
}

sub master_on () {
    $MasterProcessEnabled = 'on';
}

sub master_process_enabled (@) {
    if (@_) {
        $MasterProcessEnabled = shift() ? 'on' : 'off';
    } else {
        return $MasterProcessEnabled;
    }
}

our @EXPORT_OK = qw(
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
    $NginxVersion
    $PidFile
    $ServRoot
    $ConfFile
    $RunTestHelper
    $NoNginxManager
    $RepeatEach
    worker_connections
    workers
    master_on
    config_preamble
    repeat_each
    master_process_enabled
    log_level
    no_shuffle
    no_root_location
    html_dir
    server_root
);


if ($Profiling || $UseValgrind) {
    $DaemonEnabled          = 'off';
    $MasterProcessEnabled   = 'off';
}

our $ConfigPreamble = '';

sub config_preamble ($) {
    $ConfigPreamble = shift;
}

our $RunTestHelper;

our $NginxVersion;
our $NginxRawVersion;
our $TODO;

#our ($PrevRequest, $PrevConfig);

our $ServRoot   = $ENV{TEST_NGINX_SERVROOT} || File::Spec->catfile(cwd(), 't/servroot');
our $LogDir     = File::Spec->catfile($ServRoot, 'logs');
our $ErrLogFile = File::Spec->catfile($LogDir, 'error.log');
our $AccLogFile = File::Spec->catfile($LogDir, 'access.log');
our $HtmlDir    = File::Spec->catfile($ServRoot, 'html');
our $ConfDir    = File::Spec->catfile($ServRoot, 'conf');
our $ConfFile   = File::Spec->catfile($ConfDir, 'nginx.conf');
our $PidFile    = File::Spec->catfile($LogDir, 'nginx.pid');

sub html_dir () {
    return $HtmlDir;
}

sub server_root () {
    return $ServRoot;
}

sub run_tests () {
    $NginxVersion = get_nginx_version();

    if (defined $NginxVersion) {
        #warn "[INFO] Using nginx version $NginxVersion ($NginxRawVersion)\n";
    }

    for my $block ($NoShuffle ? Test::Base::blocks() : shuffle Test::Base::blocks()) {
        #for (1..3) {
            run_test($block);
        #}
    }

    if ($Profiling || $UseValgrind) {
        $ForkManager->wait_all_children;
    }
}

sub setup_server_root () {
    if (-d $ServRoot) {
        # Take special care, so we won't accidentally remove
        # real user data when TEST_NGINX_SERVROOT is mis-used.
        system("rm -rf $ConfDir > /dev/null") == 0 or
            die "Can't remove $ConfDir";
        system("rm -rf $HtmlDir > /dev/null") == 0 or
            die "Can't remove $HtmlDir";
        system("rm -rf $LogDir > /dev/null") == 0 or
            die "Can't remove $LogDir";
        system("rm -rf $ServRoot/*_temp > /dev/null") == 0 or
            die "Can't remove $ServRoot/*_temp";
        system("rmdir $ServRoot > /dev/null") == 0 or
            die "Can't remove $ServRoot (not empty?)";
    }
    mkdir $ServRoot or
        die "Failed to do mkdir $ServRoot\n";
    mkdir $LogDir or
        die "Failed to do mkdir $LogDir\n";
    mkdir $HtmlDir or
        die "Failed to do mkdir $HtmlDir\n";

    my $index_file = "$HtmlDir/index.html";

    open my $out, ">$index_file" or
        die "Can't open $index_file for writing: $!\n";

    print $out '<html><head><title>It works!</title></head><body>It works!</body></html>';

    close $out;

    mkdir $ConfDir or
        die "Failed to do mkdir $ConfDir\n";
}

sub write_user_files ($) {
    my $block = shift;

    my $name = $block->name;

    if ($block->user_files) {
        my $raw = $block->user_files;

        open my $in, '<', \$raw;

        my @files;
        my ($fname, $body);
        while (<$in>) {
            if (/>>> (\S+)/) {
                if ($fname) {
                    push @files, [$fname, $body];
                }

                $fname = $1;
                undef $body;
            } else {
                $body .= $_;
            }
        }

        if ($fname) {
            push @files, [$fname, $body];
        }

        for my $file (@files) {
            my ($fname, $body) = @$file;
            #warn "write file $fname with content [$body]\n";

            if (!defined $body) {
                $body = '';
            }

            open my $out, ">$HtmlDir/$fname" or
                die "$name - Cannot open $HtmlDir/$fname for writing: $!\n";
            print $out $body;
            close $out;
        }
    }
}

sub write_config_file ($$$) {
    my ($config, $http_config, $main_config) = @_;

    if (!defined $config) {
        $config = '';
    }

    if (!defined $http_config) {
        $http_config = '';
    }

    if (!defined $main_config) {
        $main_config = '';
    }

    open my $out, ">$ConfFile" or
        die "Can't open $ConfFile for writing: $!\n";
    print $out <<_EOC_;
worker_processes  $Workers;
daemon $DaemonEnabled;
master_process $MasterProcessEnabled;
error_log $ErrLogFile $LogLevel;
pid       $PidFile;

$main_config

http {
    access_log $AccLogFile;

    default_type text/plain;
    keepalive_timeout  68;

$http_config

    server {
        listen          $ServerPort;
        server_name     'localhost';

        client_max_body_size 30M;
        #client_body_buffer_size 4k;

        # Begin preamble config...
$ConfigPreamble
        # End preamble config...

        # Begin test case config...
$config
        # End test case config.

_EOC_

    if (! $NoRootLocation) {
        print $out <<_EOC_;
        location / {
            root $HtmlDir;
            index index.html index.htm;
        }
_EOC_
    }

    print $out <<_EOC_;
    }
}

events {
    worker_connections  $WorkerConnections;
}

_EOC_
    close $out;
}

sub get_canon_version (@) {
    sprintf "%d.%03d%03d", $_[0], $_[1], $_[2];
}

sub get_nginx_version () {
    my $out = `$NginxBinary -V 2>&1`;
    if (!defined $out || $? != 0) {
        warn "Failed to get the version of the Nginx in PATH.\n";
    }
    if ($out =~ m{(?:nginx|ngx_openresty)/(\d+)\.(\d+)\.(\d+)}s) {
        $NginxRawVersion = "$1.$2.$3";
        return get_canon_version($1, $2, $3);
    }
    warn "Failed to parse the output of \"nginx -V\": $out\n";
    return undef;
}

sub get_pid_from_pidfile ($) {
    my ($name) = @_;
    open my $in, $PidFile or
        Test::More::BAIL_OUT("$name - Failed to open the pid file $PidFile for reading: $!");
    my $pid = do { local $/; <$in> };
    #warn "Pid: $pid\n";
    close $in;
    return $pid;
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

sub parse_headers ($) {
    my $s = shift;
    my %headers;
    open my $in, '<', \$s;
    while (<$in>) {
        s/^\s+|\s+$//g;
        my $neg = ($_ =~ s/^!\s*//);
        #warn "neg: $neg ($_)";
        if ($neg) {
            $headers{$_} = undef;
        } else {
            my ($key, $val) = split /\s*:\s*/, $_, 2;
            $headers{$key} = $val;
        }
    }
    close $in;
    return \%headers;
}

sub run_test ($) {
    my $block = shift;
    my $name = $block->name;

    my $config = $block->config;
    if (!defined $config) {
        Test::More::BAIL_OUT("$name - No '--- config' section specified");
        #$config = $PrevConfig;
        die;
    }

    my $skip_nginx = $block->skip_nginx;
    my $skip_nginx2 = $block->skip_nginx2;
    my ($tests_to_skip, $should_skip, $skip_reason);
    if (defined $skip_nginx) {
        if ($skip_nginx =~ m{
                ^ \s* (\d+) \s* : \s*
                    ([<>]=?) \s* (\d+)\.(\d+)\.(\d+)
                    (?: \s* : \s* (.*) )?
                \s*$}x) {
            $tests_to_skip = $1;
            my ($op, $ver1, $ver2, $ver3) = ($2, $3, $4, $5);
            $skip_reason = $6;
            #warn "$ver1 $ver2 $ver3";
            my $ver = get_canon_version($ver1, $ver2, $ver3);
            if ((!defined $NginxVersion and $op =~ /^</)
                    or eval "$NginxVersion $op $ver")
            {
                $should_skip = 1;
            }
        } else {
            Test::More::BAIL_OUT("$name - Invalid --- skip_nginx spec: " .
                $skip_nginx);
            die;
        }
    } elsif (defined $skip_nginx2) {
        if ($skip_nginx2 =~ m{
                ^ \s* (\d+) \s* : \s*
                    ([<>]=?) \s* (\d+)\.(\d+)\.(\d+)
                    \s* (or|and) \s*
                    ([<>]=?) \s* (\d+)\.(\d+)\.(\d+)
                    (?: \s* : \s* (.*) )?
                \s*$}x) {
            $tests_to_skip = $1;
            my ($opa, $ver1a, $ver2a, $ver3a) = ($2, $3, $4, $5);
            my $opx = $6;
            my ($opb, $ver1b, $ver2b, $ver3b) = ($7, $8, $9, $10);
            $skip_reason = $11;
            my $vera = get_canon_version($ver1a, $ver2a, $ver3a);
            my $verb = get_canon_version($ver1b, $ver2b, $ver3b);

            if ((!defined $NginxVersion)
                or (($opx eq "or") and (eval "$NginxVersion $opa $vera"
                                        or eval "$NginxVersion $opb $verb"))
                or (($opx eq "and") and (eval "$NginxVersion $opa $vera"
                                        and eval "$NginxVersion $opb $verb")))
            {
                $should_skip = 1;
            }
        } else {
            Test::More::BAIL_OUT("$name - Invalid --- skip_nginx2 spec: " .
                $skip_nginx2);
            die;
        }
    }

    if (!defined $skip_reason) {
        $skip_reason = "various reasons";
    }

    my $todo_nginx = $block->todo_nginx;
    my ($should_todo, $todo_reason);
    if (defined $todo_nginx) {
        if ($todo_nginx =~ m{
                ^ \s*
                    ([<>]=?) \s* (\d+)\.(\d+)\.(\d+)
                    (?: \s* : \s* (.*) )?
                \s*$}x) {
            my ($op, $ver1, $ver2, $ver3) = ($1, $2, $3, $4);
            $todo_reason = $5;
            my $ver = get_canon_version($ver1, $ver2, $ver3);
            if ((!defined $NginxVersion and $op =~ /^</)
                    or eval "$NginxVersion $op $ver")
            {
                $should_todo = 1;
            }
        } else {
            Test::More::BAIL_OUT("$name - Invalid --- todo_nginx spec: " .
                $todo_nginx);
            die;
        }
    }

    if (!defined $todo_reason) {
        $todo_reason = "various reasons";
    }

    if (!$NoNginxManager && !$should_skip) {
        my $nginx_is_running = 1;
        if (-f $PidFile) {
            my $pid = get_pid_from_pidfile($name);
            if (!defined $pid or $pid eq '') {
                undef $nginx_is_running;
                goto start_nginx;
            }

            if (system("ps $pid > /dev/null") == 0) {
                #warn "found running nginx...";
                write_config_file($config, $block->http_config, $block->main_config);
                if (kill(SIGQUIT, $pid) == 0) { # send quit signal
                    #warn("$name - Failed to send quit signal to the nginx process with PID $pid");
                }
                sleep 0.02;
                if (system("ps $pid > /dev/null") == 0) {
                    #warn "killing with force...\n";
                    kill(SIGKILL, $pid);
                    sleep 0.02;
                }
                undef $nginx_is_running;
            } else {
                unlink $PidFile or
                    die "Failed to remove pid file $PidFile\n";
                undef $nginx_is_running;
            }
        } else {
            undef $nginx_is_running;
        }

start_nginx:

        unless ($nginx_is_running) {
            #system("killall -9 nginx");

            #warn "*** Restarting the nginx server...\n";
            setup_server_root();
            write_user_files($block);
            write_config_file($config, $block->http_config, $block->main_config);
            if ( ! can_run($NginxBinary) ) {
                Test::More::BAIL_OUT("$name - Cannot find the nginx executable in the PATH environment");
                die;
            }
        #if (system("nginx -p $ServRoot -c $ConfFile -t") != 0) {
        #Test::More::BAIL_OUT("$name - Invalid config file");
        #}
        #my $cmd = "nginx -p $ServRoot -c $ConfFile > /dev/null";
            if (!defined $NginxVersion) {
                $NginxVersion = $LatestNginxVersion;
            }

            my $cmd;
            if ($NginxVersion >= 0.007053) {
                $cmd = "$NginxBinary -p $ServRoot/ -c $ConfFile > /dev/null";
            } else {
                $cmd = "$NginxBinary -c $ConfFile > /dev/null";
            }

            if ($UseValgrind) {
                if (-f 'valgrind.suppress') {
                    $cmd = "valgrind -q --leak-check=full --gen-suppressions=all --suppressions=valgrind.suppress $cmd";
                } else {
                    $cmd = "valgrind -q --leak-check=full --gen-suppressions=all $cmd";
                }

                warn "$name\n";
                #warn "$cmd\n";
            }

            if ($Profiling || $UseValgrind) {
                my $pid = $ForkManager->start;
                if (!$pid) {
                    # child process
                    exec $cmd;

=begin cmt

                    if (system($cmd) != 0) {
                        Test::More::BAIL_OUT("$name - Cannot start nginx using command \"$cmd\".");
                    }

                    $ForkManager->finish; # terminate the child process

=end cmt

=cut

                }
                #warn "sleeping";
                if ($TestNginxSleep) {
                    sleep $TestNginxSleep;
                } else {
                    sleep 1;
                }
            } else {
                if (system($cmd) != 0) {
                    Test::More::BAIL_OUT("$name - Cannot start nginx using command \"$cmd\".");
                }
            }

            sleep 0.1;
        }
    }

    if ($block->init) {
        eval $block->init;
        if ($@) {
            Test::More::BAIL_OUT("$name - init failed: $@");
        }
    }

    my $i = 0;
    while ($i++ < $RepeatEach) {
        if ($should_skip) {
            SKIP: {
                Test::More::skip("$name - $skip_reason", $tests_to_skip);

                $RunTestHelper->($block);
            }
        } elsif ($should_todo) {
            TODO: {
                local $TODO = "$name - $todo_reason";

                $RunTestHelper->($block);
            }
        } else {
            $RunTestHelper->($block);
        }
    }

    if (my $total_errlog = $ENV{TEST_NGINX_ERROR_LOG}) {
        my $errlog = "$LogDir/error.log";
        if (-s $errlog) {
            open my $out, ">>$total_errlog" or
                die "Failed to append test case title to $total_errlog: $!\n";
            print $out "\n=== $0 $name\n";
            close $out;
            system("cat $errlog >> $total_errlog") == 0 or
                die "Failed to append $errlog to $total_errlog. Abort.\n";
        }
    }

    if ($Profiling || $UseValgrind) {
        #warn "Found quit...";
        if (-f $PidFile) {
            #warn "found pid file...";
            my $pid = get_pid_from_pidfile($name);
            if (system("ps $pid > /dev/null") == 0) {
                write_config_file($config, $block->http_config, $block->main_config);
                if (kill(SIGQUIT, $pid) == 0) { # send quit signal
                    warn("$name - Failed to send quit signal to the nginx process with PID $pid");
                }
                if ($TestNginxSleep) {
                    sleep $TestNginxSleep;
                } else {
                    sleep 0.1;
                }
                if (-f $PidFile) {
                    #warn "killing with force (valgrind or profile)...\n";
                    kill(SIGKILL, $pid);
                    sleep 0.02;
                } else {
                    #warn "nginx killed";
                }
            } else {
                unlink $PidFile or
                    die "Failed to remove pid file $PidFile\n";
            }
        } else {
            #warn "pid file not found";
        }
    }
}

END {
    if ($UseValgrind || !$ENV{TEST_NGINX_NO_CLEAN}) {
        if (-f $PidFile) {
            my $pid = get_pid_from_pidfile('');
            if (!$pid) {
                die "No pid found.";
            }
            if (system("ps $pid > /dev/null") == 0) {
                if (kill(SIGQUIT, $pid) == 0) { # send quit signal
                    #warn("$name - Failed to send quit signal to the nginx process with PID $pid");
                }
                if ($TestNginxSleep) {
                    sleep $TestNginxSleep;
                } else {
                    sleep 0.02;
                }
                if (system("ps $pid > /dev/null") == 0) {
                    #warn "killing with force...\n";
                    kill(SIGKILL, $pid);
                    sleep 0.02;
                }
            } else {
                unlink $PidFile;
            }
        }
    }
}

# check if we can run some command
sub can_run {
	my ($cmd) = @_;

	my $_cmd = $cmd;
	return $_cmd if (-x $_cmd or $_cmd = MM->maybe_command($_cmd));

	for my $dir ((split /$Config::Config{path_sep}/, $ENV{PATH}), '.') {
		next if $dir eq '';
		my $abs = File::Spec->catfile($dir, $_[1]);
		return $abs if (-x $abs or $abs = MM->maybe_command($abs));
	}

	return;
}

1;
