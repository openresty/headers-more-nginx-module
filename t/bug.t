# vi:filetype=

use Test::Nginx::Socket; # 'no_plan';

repeat_each(2);

plan tests => 14 * repeat_each();

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



=== TEST 3: mime type overriding (inlined types)
--- config
    more_clear_headers 'X-Powered-By' 'X-Runtime' 'ETag';

    types {
        text/html                             html htm shtml;
        text/css                              css;
    }
--- user_files
>>> a.css
hello
--- request
GET /a.css
--- error_code: 200
--- response_headers
Content-Type: text/css
--- response_body
hello



=== TEST 4: mime type overriding (included types file)
--- config
    more_clear_headers 'X-Powered-By' 'X-Runtime' 'ETag';
    include mime.types;
--- user_files
>>> a.css
hello
>>> ../conf/mime.types
types {
    text/html                             html htm shtml;
    text/css                              css;
}
--- request
GET /a.css
--- error_code: 200
--- response_headers
Content-Type: text/css
--- response_body
hello



=== TEST 5: empty variable as the header value
--- config
    location /foo {
        more_set_headers 'X-Foo: $arg_foo';
        echo hi;
    }
--- request
    GET /foo
--- response_headers
! X-Foo
--- response_body
hi



=== TEST 6: range bug
--- config
    location /index.html {
        more_clear_input_headers "Range*" ;
        more_clear_input_headers "Content-Range*" ;

        more_set_input_headers 'Range: bytes=1-5';
        more_set_headers  'Content-Range: bytes 1-5/1000';
    }
--- request
    GET /index.html
--- more_headers
Range: bytes=1-3
--- raw_response_headers_like: Content-Range: bytes 1-5/1000$
--- response_body chop
html>
--- error_code: 206
--- SKIP

