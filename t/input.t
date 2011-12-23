# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket; # 'no_plan';

repeat_each(2);

plan tests => 53 * repeat_each();

no_long_string();
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
--- more_headers
X-Foo: blah
--- response_headers
! X-Foo
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
--- more_headers
X-Foo: blah
--- response_headers
! X-Foo
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
--- timeout: 15



=== TEST 4: try to rewrite content length using the rewrite module
Thisshould not take effect ;)
--- config
    location /bar {
        set $http_content_length 2048;
        echo_read_request_body;
        echo_request_body;
    }
--- request eval
"POST /bar\n" .
"a" x 4096
--- response_body eval
"a" x 4096



=== TEST 5: rewrite host and user-agent
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



=== TEST 6: clear host and user-agent
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



=== TEST 7: clear host and user-agent (the other way)
--- config
    location /bar {
        more_set_input_headers 'Host:' 'User-Agent:' 'X-Foo:';
        echo "Host: $host";
        echo "User-Agent: $http_user_agent";
        echo "X-Foo: $http_x_foo";
    }
--- request
GET /bar
--- more_headers
X-Foo: bar
--- response_body
Host: localhost
User-Agent: 
X-Foo: 



=== TEST 8: clear content-length
--- config
    location /bar {
        more_set_input_headers 'Content-Length: ';
        echo "Content-Length: $http_content_length";
    }
--- request
POST /bar
hello
--- more_headers
--- response_body
Content-Length: 



=== TEST 9: clear content-length (the other way)
--- config
    location /bar {
        more_clear_input_headers 'Content-Length: ';
        echo "Content-Length: $http_content_length";
    }
--- request
POST /bar
hello
--- more_headers
--- response_body
Content-Length: 



=== TEST 10: rewrite type
--- config
    location /bar {
        more_set_input_headers 'Content-Type: text/css';
        echo "Content-Type: $content_type";
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/plain
--- response_body
Content-Type: text/css



=== TEST 11: clear type
--- config
    location /bar {
        more_set_input_headers 'Content-Type:';
        echo "Content-Type: $content_type";
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/plain
--- response_body
Content-Type: 



=== TEST 12: clear type (the other way)
--- config
    location /bar {
        more_clear_input_headers 'Content-Type:foo';
        echo "Content-Type: $content_type";
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/plain
--- response_body
Content-Type: 



=== TEST 13: add type constraints
--- config
    location /bar {
        more_set_input_headers -t 'text/plain' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/plain
--- response_body
yay



=== TEST 14: add type constraints (not matched)
--- config
    location /bar {
        more_set_input_headers -t 'text/plain' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/css
--- response_body eval: "\n"



=== TEST 15: add type constraints (OR'd)
--- config
    location /bar {
        more_set_input_headers -t 'text/plain text/css' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/css
--- response_body
yay



=== TEST 16: add type constraints (OR'd)
--- config
    location /bar {
        more_set_input_headers -t 'text/plain text/css' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/plain
--- response_body
yay



=== TEST 17: add type constraints (OR'd) (not matched)
--- config
    location /bar {
        more_set_input_headers -t 'text/plain text/css' 'X-Blah:yay';
        echo $http_x_blah;
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/html
--- response_body eval: "\n"



=== TEST 18: mix input and output cmds
--- config
    location /bar {
        more_set_input_headers 'X-Blah:yay';
        more_set_headers 'X-Blah:hiya';
        echo $http_x_blah;
    }
--- request
GET /bar
--- response_headers
X-Blah: hiya
--- response
yay



=== TEST 19: set request header at client side and replace
--- config
    location /foo {
        more_set_input_headers -r 'X-Foo: howdy';
        echo $http_x_foo;
    }
--- request
    GET /foo
--- more_headers
X-Foo: blah
--- response_headers
! X-Foo
--- response_body
howdy



=== TEST 20: do no set request header at client, so no replace with -r option
--- config
    location /foo {
        more_set_input_headers -r 'X-Foo: howdy';
        echo "empty_header:" $http_x_foo;
    }
--- request
    GET /foo
--- response_headers
! X-Foo
--- response_body
empty_header: 



=== TEST 21: clear input headers
--- config
    location /foo {
        set $val 'dog';

        more_clear_input_headers 'User-Agent';

        proxy_pass http://127.0.0.1:$server_port/proxy;
    }
    location /proxy {
        echo -n $echo_client_request_headers;
    }
--- request
    GET /foo
--- more_headers
User-Agent: my-sock
--- response_body eval
"GET /proxy HTTP/1.0\r
Host: 127.0.0.1:\$ServerPort\r
Connection: close\r
"
--- skip_nginx: 3: < 0.7.46



=== TEST 22: clear input headers
--- config
    location /foo {
        more_clear_input_headers 'User-Agent';

        proxy_pass http://127.0.0.1:$server_port/proxy;
    }
    location /proxy {
        echo -n $echo_client_request_headers;
    }
--- request
    GET /foo
--- response_body eval
"GET /proxy HTTP/1.0\r
Host: 127.0.0.1:\$ServerPort\r
Connection: close\r
"
--- skip_nginx: 3: < 0.7.46



=== TEST 23: clear input headers
--- config
    location /foo {
        more_clear_input_headers 'X-Foo19';
        more_clear_input_headers 'X-Foo20';
        more_clear_input_headers 'X-Foo21';

        proxy_pass http://127.0.0.1:$server_port/proxy;
    }
    location /proxy {
        echo -n $echo_client_request_headers;
    }
--- request
    GET /foo
--- more_headers eval
my $s;
for my $i (3..21) {
    $s .= "X-Foo$i: $i\n";
}
$s;
--- response_body eval
"GET /proxy HTTP/1.0\r
Host: 127.0.0.1:\$ServerPort\r
Connection: close\r
X-Foo3: 3\r
X-Foo4: 4\r
X-Foo5: 5\r
X-Foo6: 6\r
X-Foo7: 7\r
X-Foo8: 8\r
X-Foo9: 9\r
X-Foo10: 10\r
X-Foo11: 11\r
X-Foo12: 12\r
X-Foo13: 13\r
X-Foo14: 14\r
X-Foo15: 15\r
X-Foo16: 16\r
X-Foo17: 17\r
X-Foo18: 18\r
"
--- skip_nginx: 3: < 0.7.46



=== TEST 24: Accept-Encoding
--- config
    location /bar {
        default_type 'text/plain';
        more_set_input_headers 'Accept-Encoding: gzip';
        gzip on;
        gzip_min_length  1;
        gzip_buffers     4 8k;
        gzip_types       text/plain;
    }
--- user_files
">>> bar
" . ("hello" x 512)
--- request
GET /bar
--- response_headers
Content-Encoding: gzip
--- response_body_like: .

