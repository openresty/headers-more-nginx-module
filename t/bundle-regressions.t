use Test::Nginx::Socket 'no_plan';
no_long_string();
run_tests();
__DATA__

=== TEST 1: request media type ignores case and parameters
--- config
location /t {
    more_set_input_headers -t text/plain 'X-Matched: yes';
    echo $http_x_matched;
}
--- request
GET /t
--- more_headers
Content-Type: Text/Plain; charset=utf-8
--- response_body
yes
--- no_error_log
[error]



=== TEST 2: response media type ignores case
--- config
location /t {
    default_type Text/Plain;
    more_set_headers -t text/plain 'X-Matched: yes';
    echo ok;
}
--- request
GET /t
--- response_headers
X-Matched: yes
--- response_body
ok
--- no_error_log
[error]



=== TEST 3: replacement discards the previous charset
--- config
location /t {
    more_set_headers 'Content-Type: text/plain; charset=utf-8' 'Content-Type: application/json';
    echo ok;
}
--- request
GET /t
--- response_headers
Content-Type: application/json
--- response_body
ok
--- no_error_log
[error]



=== TEST 4: preserve the upstream charset for configured conversion
--- http_config
charset_map iso-8859-1 utf-8 {
    E9 C3A9;
}
--- config eval
q~
location = /upstream {
    charset off;
    more_set_headers 'Content-Type: text/plain; charset=iso-8859-1';
    echo -n '~ . "abc\xe9def" . q~';
}
location = /t {
    charset utf-8;
    override_charset on;
    proxy_pass http://127.0.0.1:$server_port/upstream;
    more_set_headers 'Content-Type: text/plain';
}
~
--- request
GET /t
--- response_headers
Content-Type: text/plain; charset=utf-8
--- response_body eval
"abc\xc3\xa9def"
--- no_error_log
[error]



=== TEST 5: separate directives discard the previous charset
--- config
location /t {
    more_set_headers 'Content-Type: text/plain; charset=utf-8';
    more_set_headers 'Content-Type: application/json';
    echo ok;
}
--- request
GET /t
--- response_headers
Content-Type: application/json
--- response_body
ok
--- no_error_log
[error]



=== TEST 6: clearing and setting content type discards the previous charset
--- config
location /t {
    more_set_headers 'Content-Type: text/plain; charset=utf-8';
    more_clear_headers Content-Type;
    more_set_headers 'Content-Type: application/json';
    echo ok;
}
--- request
GET /t
--- response_headers
Content-Type: application/json
--- response_body
ok
--- no_error_log
[error]



=== TEST 7: configured charset applies after replacement
--- config
location /t {
    charset utf-8;
    more_set_headers 'Content-Type: text/plain; charset=iso-8859-1';
    more_set_headers 'Content-Type: text/plain';
    echo ok;
}
--- request
GET /t
--- response_headers
Content-Type: text/plain; charset=utf-8
--- response_body
ok
--- no_error_log
[error]



=== TEST 8: request media type must not match a subtype prefix
--- config
location /t {
    more_set_input_headers -t text/plain 'X-Matched: yes';
    echo "[$http_x_matched]";
}
--- request
GET /t
--- more_headers
Content-Type: text/plainx; charset=utf-8
--- response_body
[]
--- no_error_log
[error]



=== TEST 9: request media type permits whitespace before parameters
--- config
location /t {
    more_set_input_headers -t text/plain 'X-Matched: yes';
    echo $http_x_matched;
}
--- request
GET /t
--- more_headers eval
"Content-Type: Text/Plain \t ; format=flowed"
--- response_body
yes
--- no_error_log
[error]



=== TEST 10: request media type rejects extra tokens before parameters
--- config
location /t {
    more_set_input_headers -t text/plain 'X-Matched: yes';
    echo "[$http_x_matched]";
}
--- request
GET /t
--- more_headers
Content-Type: text/plain extra; charset=utf-8
--- response_body
[]
--- no_error_log
[error]



=== TEST 11: request media type ignores non-charset parameters
--- config
location /t {
    more_clear_input_headers -t text/plain X-Original;
    echo "[$http_x_original]";
}
--- request
GET /t
--- more_headers
Content-Type: text/plain; format="a;b"
X-Original: present
--- response_body
[]
--- no_error_log
[error]



=== TEST 12: a shorter configured type does not hide a longer match
--- config
location /t {
    more_set_input_headers -t 'text/plain text/plainx' 'X-Matched: yes';
    echo $http_x_matched;
}
--- request
GET /t
--- more_headers
Content-Type: Text/Plainx; charset=utf-8
--- response_body
yes
--- no_error_log
[error]
