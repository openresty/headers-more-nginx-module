# vi:filetype=perl

use lib 'lib';
use Test::Nginx::Socket; # 'no_plan';

plan tests => 5;

no_diff;

run_tests();

__DATA__

=== TEST 1: set Server
--- config
    #more_set_headers 'Last-Modified: x';
    more_clear_headers 'Last-Modified';
--- request
    GET /index.html
--- response_headers
! Last-Modified
--- response_body_like: It works!



=== TEST 2: variables in the Ranges header
--- config
    location /index.html {
        set $rfrom 1;
        set $rto 3;
        more_set_input_headers 'Range: bytes=$rfrom - $rto';
        #more_set_input_headers 'Range: bytes=1 - 3';
        #echo $http_range;
    }
--- request
GET /index.html
--- error_code: 206
--- response_body chomp
htm

