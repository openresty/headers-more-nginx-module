# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP; # 'no_plan';

plan tests => 3;

no_diff;

run_tests();

__DATA__

=== TEST 1: vars in input header directives
--- config
    location /main {
        echo_location /foo;
        echo "main: $http_user_agent";
    }
    location /foo {
        set $val 'dog';

        more_set_input_headers 'User-Agent: $val';

        proxy_pass http://127.0.0.1:$server_port/proxy;
    }
    location /proxy {
        echo "sub: $http_user_agent";
    }
--- request
    GET /main
--- response_body
sub: dog
main: dog
--- response_headers
Host:
--- skip_nginx: 3: < 0.7.46

