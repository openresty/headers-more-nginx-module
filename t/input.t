# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket; # 'no_plan';

repeat_each(2);

plan tests => repeat_each() * 73;

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



=== TEST 25: rewrite + set request header
--- config
    location /t {
        rewrite ^ /foo last;
    }

    location /foo {
        more_set_input_headers 'X-Foo: howdy';
        proxy_pass http://127.0.0.1:$server_port/echo;
    }

    location /echo {
        echo "X-Foo: $http_x_foo";
    }
--- request
    GET /foo
--- response_headers
! X-Foo
--- response_body
X-Foo: howdy



=== TEST 26: clear_header should clear all the instances of the user custom header
--- config
    location = /t {
        more_clear_input_headers Foo;

        proxy_pass http://127.0.0.1:$server_port/echo;
    }

    location = /echo {
        echo "Foo: [$http_foo]";
        echo "Test-Header: [$http_test_header]";
    }
--- request
GET /t
--- more_headers
Foo: foo
Foo: bah
Test-Header: 1
--- response_body
Foo: []
Test-Header: [1]



=== TEST 27: clear_header should clear all the instances of the builtin header
--- config
    location = /t {
        more_clear_input_headers Content-Type;

        proxy_pass http://127.0.0.1:$server_port/echo;
    }

    location = /echo {
        echo "Content-Type: [$http_content_type]";
        echo "Test-Header: [$http_test_header]";
        #echo $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers
Content-Type: foo
Content-Type: bah
Test-Header: 1
--- response_body
Content-Type: []
Test-Header: [1]



=== TEST 28: Converting POST to GET - clearing headers (bug found by Matthieu Tourne, 411 error page)
--- config
    location /t {
        more_clear_input_headers Content-Type;
        more_clear_input_headers Content-Length;

        #proxy_pass http://127.0.0.1:8888;
        proxy_pass http://127.0.0.1:$server_port/back;
    }

    location /back {
        echo $echo_client_request_headers;
    }
--- request
POST /t
hello world
--- more_headers
Content-Type: application/ocsp-request
Test-Header: 1
--- response_body_like eval
qr/Connection: close\r
Test-Header: 1\r
$/
--- no_error_log
[error]



=== TEST 29: clear_header() does not duplicate subsequent headers (old bug)
--- config
    location = /t {
        more_clear_input_headers Foo;

        proxy_pass http://127.0.0.1:$server_port/echo;
    }

    location = /echo {
        echo $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers
Bah: bah
Foo: foo
Test-Header: 1
Foo1: foo1
Foo2: foo2
Foo3: foo3
Foo4: foo4
Foo5: foo5
Foo6: foo6
Foo7: foo7
Foo8: foo8
Foo9: foo9
Foo10: foo10
Foo11: foo11
Foo12: foo12
Foo13: foo13
Foo14: foo14
Foo15: foo15
Foo16: foo16
Foo17: foo17
Foo18: foo18
Foo19: foo19
Foo20: foo20
Foo21: foo21
Foo22: foo22
--- response_body_like eval
qr/Bah: bah\r
Test-Header: 1\r
Foo1: foo1\r
Foo2: foo2\r
Foo3: foo3\r
Foo4: foo4\r
Foo5: foo5\r
Foo6: foo6\r
Foo7: foo7\r
Foo8: foo8\r
Foo9: foo9\r
Foo10: foo10\r
Foo11: foo11\r
Foo12: foo12\r
Foo13: foo13\r
Foo14: foo14\r
Foo15: foo15\r
Foo16: foo16\r
Foo17: foo17\r
Foo18: foo18\r
Foo19: foo19\r
Foo20: foo20\r
Foo21: foo21\r
Foo22: foo22\r
/



=== TEST 30: clear input header (just more than 20 headers)
--- config
    location = /t {
        more_clear_input_headers "R";
        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Host foo;
        #proxy_pass http://127.0.0.1:1234/back;
    }

    location = /back {
        echo $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\n";

for my $i ('a' .. 'r') {
    $s .= uc($i) . ": " . "$i\n"
}
$s
--- response_body eval
"GET /back HTTP/1.0\r
Host: foo\r
Connection: close\r
User-Agent: curl\r
A: a\r
B: b\r
C: c\r
D: d\r
E: e\r
F: f\r
G: g\r
H: h\r
I: i\r
J: j\r
K: k\r
L: l\r
M: m\r
N: n\r
O: o\r
P: p\r
Q: q\r

"



=== TEST 31: clear input header (just more than 20 headers, and add more)
--- config
    location = /t {
        more_clear_input_headers R;
        more_set_input_headers "foo-1: 1" "foo-2: 2" "foo-3: 3" "foo-4: 4"
            "foo-5: 5" "foo-6: 6" "foo-7: 7" "foo-8: 8" "foo-9: 9"
            "foo-10: 10" "foo-11: 11" "foo-12: 12" "foo-13: 13"
            "foo-14: 14" "foo-15: 15" "foo-16: 16" "foo-17: 17" "foo-18: 18"
            "foo-19: 19" "foo-20: 20" "foo-21: 21";

        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Host foo;
        #proxy_pass http://127.0.0.1:1234/back;
    }

    location = /back {
        echo $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\n";

for my $i ('a' .. 'r') {
    $s .= uc($i) . ": " . "$i\n"
}
$s
--- response_body eval
"GET /back HTTP/1.0\r
Host: foo\r
Connection: close\r
User-Agent: curl\r
A: a\r
B: b\r
C: c\r
D: d\r
E: e\r
F: f\r
G: g\r
H: h\r
I: i\r
J: j\r
K: k\r
L: l\r
M: m\r
N: n\r
O: o\r
P: p\r
Q: q\r
foo-1: 1\r
foo-2: 2\r
foo-3: 3\r
foo-4: 4\r
foo-5: 5\r
foo-6: 6\r
foo-7: 7\r
foo-8: 8\r
foo-9: 9\r
foo-10: 10\r
foo-11: 11\r
foo-12: 12\r
foo-13: 13\r
foo-14: 14\r
foo-15: 15\r
foo-16: 16\r
foo-17: 17\r
foo-18: 18\r
foo-19: 19\r
foo-20: 20\r
foo-21: 21\r

"



=== TEST 32: clear input header (just more than 21 headers)
--- config
    location = /t {
        more_clear_input_headers R Q;
        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Host foo;
        #proxy_pass http://127.0.0.1:1234/back;
    }

    location = /back {
        echo $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\nBah: bah\n";

for my $i ('a' .. 'r') {
    $s .= uc($i) . ": " . "$i\n"
}
$s
--- response_body eval
"GET /back HTTP/1.0\r
Host: foo\r
Connection: close\r
User-Agent: curl\r
Bah: bah\r
A: a\r
B: b\r
C: c\r
D: d\r
E: e\r
F: f\r
G: g\r
H: h\r
I: i\r
J: j\r
K: k\r
L: l\r
M: m\r
N: n\r
O: o\r
P: p\r

"



=== TEST 33: clear input header (just more than 21 headers)
--- config
    location = /t {
        more_clear_input_headers R Q;
        more_set_input_headers "foo-1: 1" "foo-2: 2" "foo-3: 3" "foo-4: 4"
            "foo-5: 5" "foo-6: 6" "foo-7: 7" "foo-8: 8" "foo-9: 9"
            "foo-10: 10" "foo-11: 11" "foo-12: 12" "foo-13: 13"
            "foo-14: 14" "foo-15: 15" "foo-16: 16" "foo-17: 17" "foo-18: 18"
            "foo-19: 19" "foo-20: 20" "foo-21: 21";

        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Host foo;
        #proxy_pass http://127.0.0.1:1234/back;
    }

    location = /back {
        echo $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\nBah: bah\n";

for my $i ('a' .. 'r') {
    $s .= uc($i) . ": " . "$i\n"
}
$s
--- response_body eval
"GET /back HTTP/1.0\r
Host: foo\r
Connection: close\r
User-Agent: curl\r
Bah: bah\r
A: a\r
B: b\r
C: c\r
D: d\r
E: e\r
F: f\r
G: g\r
H: h\r
I: i\r
J: j\r
K: k\r
L: l\r
M: m\r
N: n\r
O: o\r
P: p\r
foo-1: 1\r
foo-2: 2\r
foo-3: 3\r
foo-4: 4\r
foo-5: 5\r
foo-6: 6\r
foo-7: 7\r
foo-8: 8\r
foo-9: 9\r
foo-10: 10\r
foo-11: 11\r
foo-12: 12\r
foo-13: 13\r
foo-14: 14\r
foo-15: 15\r
foo-16: 16\r
foo-17: 17\r
foo-18: 18\r
foo-19: 19\r
foo-20: 20\r
foo-21: 21\r

"

