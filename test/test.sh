#!/bin/bash

export PATH=/opt/nginx/sbin:$PATH
#killall nginx
#kill 3 `cat t/servroot/logs/nginx.pid`
rm t/servroot/logs/error.log
nginx -V && prove --shuffle "$@"

