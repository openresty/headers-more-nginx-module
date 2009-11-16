# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => 2 * blocks();

no_diff;

run_tests();

__DATA__

=== TEST 1: simple set (1 arg)
--- config
    location /foo {
        echo hi;
        more_set_headers 'X-Foo: Blah';
    }
--- request
    GET /foo
--- response_headers
X-Foo: Blah
--- response_body
hi

