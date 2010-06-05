# vi:filetype=perl

use lib 'lib';
use Test::Nginx::Socket; # 'no_plan';

plan tests => 3;

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

