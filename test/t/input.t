# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP 'no_plan';

#plan tests => 103;

#no_diff;

run_tests();

__DATA__

=== TEST 1: set request header at client side
--- config
    location /foo {
        #more_set_input_headers 'X-Foo: howdy';
        echo $http_x_foo;
    }
--- request
    GET /foo
--- request_headers
X-Foo: blah
--- response_headers
X-Foo:
--- response_body
blah



=== TEST 2: set request header at client side and rewrite it
--- config
    location /foo {
        more_set_input_headers 'X-Foo: howdy';
        echo $http_x_foo;
    }
--- request
    GET /foo
--- request_headers
X-Foo: blah
--- response_headers
X-Foo:
--- response_body
howdy
--- SKIP

