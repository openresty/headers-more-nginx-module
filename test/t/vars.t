# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP; # 'no_plan';

plan tests => 6;

no_diff;

run_tests();

__DATA__

=== TEST 1: vars
--- config
    location /foo {
        echo hi;
        set $val 'hello, world';
        more_set_headers 'X-Foo: $val';
    }
--- request
    GET /foo
--- response_headers
X-Foo: hello, world
--- response_body
hi



=== TEST 2: vars in both key and val
--- config
    location /foo {
        echo hi;
        set $val 'hello, world';
        more_set_headers '$val: $val';
    }
--- request
    GET /foo
--- response_headers
$val: hello, world
--- response_body
hi

