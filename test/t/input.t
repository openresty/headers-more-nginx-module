# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP; # 'no_plan';

plan tests => 34;

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



=== TEST 3: rewrite content length
--- config
    location /bar {
        more_set_input_headers 'Content-Length: 2048';
        echo_read_request_body;
        echo_request_body;
    }
--- request eval
"POST /bar\n" .
"a" x 4096
--- response_body eval
"a" x 2048



=== TEST 4: rewrite host and user-agent
--- config
    location /bar {
        more_set_input_headers 'Host: foo' 'User-Agent: blah';
        echo "Host: $host";
        echo "User-Agent: $http_user_agent";
    }
--- request
GET /bar
--- response_body
Host: foo
User-Agent: blah



=== TEST 5: clear host and user-agent
$host always has a default value and cannot be really cleared.
--- config
    location /bar {
        more_clear_input_headers 'Host: foo' 'User-Agent: blah';
        echo "Host: $host";
        echo "Host (2): $http_host";
        echo "User-Agent: $http_user_agent";
    }
--- request
GET /bar
--- response_body
Host: localhost
Host (2): 
User-Agent: 



=== TEST 6: clear host and user-agent (the other way)
--- config
    location /bar {
        more_set_input_headers 'Host:' 'User-Agent:' 'X-Foo:';
        echo "Host: $host";
        echo "User-Agent: $http_user_agent";
        echo "X-Foo: $http_x_foo";
    }
--- request
GET /bar
--- request_headers
X-Foo: bar
--- response_body
Host: localhost
User-Agent: 
X-Foo: 



=== TEST 7: clear content-length
--- config
    location /bar {
        more_set_input_headers 'Content-Length: ';
        echo "Content-Length: $http_content_length";
    }
--- request
POST /bar
hello
--- request_headers
--- response_body
Content-Length: 



=== TEST 8: clear content-length (the other way)
--- config
    location /bar {
        more_clear_input_headers 'Content-Length: ';
        echo "Content-Length: $http_content_length";
    }
--- request
POST /bar
hello
--- request_headers
--- response_body
Content-Length: 



=== TEST 9: rewrite type
--- config
    location /bar {
        more_set_input_headers 'Content-Type: text/css';
        echo "Content-Type: $content_type";
    }
--- request
POST /bar
hello
--- request_headers
Content-Type: text/plain
--- response_body
Content-Type: text/css



=== TEST 10: clear type
--- config
    location /bar {
        more_set_input_headers 'Content-Type:';
        echo "Content-Type: $content_type";
    }
--- request
POST /bar
hello
--- request_headers
Content-Type: text/plain
--- response_body
Content-Type: 



=== TEST 11: clear type (the other way)
--- config
    location /bar {
        more_clear_input_headers 'Content-Type:foo';
        echo "Content-Type: $content_type";
    }
--- request
POST /bar
hello
--- request_headers
Content-Type: text/plain
--- response_body
Content-Type: 


=== TEST 11: add type constraints
--- config
    location /bar {
        more_set_input_headers -t 'text/plain' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- request_headers
Content-Type: text/plain
--- response_body
yay


=== TEST 11: add type constraints (not matched)
--- config
    location /bar {
        more_set_input_headers -t 'text/plain' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- request_headers
Content-Type: text/css
--- response_body eval: "\n"


=== TEST 11: add type constraints (OR'd)
--- config
    location /bar {
        more_set_input_headers -t 'text/plain text/css' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- request_headers
Content-Type: text/css
--- response_body
yay


=== TEST 11: add type constraints (OR'd)
--- config
    location /bar {
        more_set_input_headers -t 'text/plain text/css' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- request_headers
Content-Type: text/plain
--- response_body
yay


=== TEST 11: add type constraints (OR'd) (not matched)
--- config
    location /bar {
        more_set_input_headers -t 'text/plain text/css' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- request_headers
Content-Type: text/html
--- response_body eval: "\n"

