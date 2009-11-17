# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP 'no_plan';

#plan tests => 2 * blocks() + 3;

no_diff;

run_tests();

__DATA__

=== TEST 1: set Server
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



=== TEST 2: set Content-Type
--- config
    location /foo {
        default_type 'text/plan';
        more_set_headers 'Content-Type: text/css';
        echo hi;
    }
--- request
    GET /foo
--- response_headers
Content-Type: text/css
--- response_body
hi



=== TEST 3: set Content-Type
--- config
    location /foo {
        default_type 'text/plan';
        more_set_headers 'Content-Type: text/css';
        return 404;
    }
--- request
    GET /foo
--- response_headers
Content-Type: text/css
--- response_body_like: 404 Not Found
--- error_code: 404

