#!/bin/bash

# this file is mostly meant to be used by the author himself.

root=`pwd`
#cd ~/work
version=$1
opts=$2
target=$root/work/nginx

if [ ! -d ./buildroot ]; then
    mkdir ./buildroot || exit 1
fi

cd buildroot || exit 1

if [ ! -s "nginx-$version.tar.gz" ]; then
    if [ -f ~/work/nginx-$version.tar.gz ]; then
        cp ~/work/nginx-$version.tar.gz ./ || exit 1
    else
        wget "http://sysoev.ru/nginx/nginx-$version.tar.gz" -O nginx-$version.tar.gz || exit 1
    fi

    tar -xzvf nginx-$version.tar.gz || exit 1
fi

#tar -xzvf nginx-$version.tar.gz || exit 1
#cp $root/../no-pool-nginx/nginx-$version-no_pool.patch ./ || exit 1
#patch -p0 < nginx-$version-no_pool.patch || exit 1

cd nginx-$version/ || exit 1

if [[ "$BUILD_CLEAN" -eq 1 || ! -f Makefile || "$root/config" -nt Makefile || "$root/util/build.sh" -nt Makefile ]]; then
    ./configure --prefix=$target \
            --without-mail_pop3_module \
            --without-mail_imap_module \
            --without-mail_smtp_module \
            --without-http_upstream_ip_hash_module \
            --without-http_empty_gif_module \
            --without-http_memcached_module \
            --without-http_referer_module \
            --without-http_autoindex_module \
            --without-http_auth_basic_module \
            --without-http_userid_module \
          --add-module=$root/../eval-nginx-module \
          --add-module=$root/../echo-nginx-module \
          --add-module=$root $opts \
          --with-debug \
        || exit 1
          #--add-module=$root/../ndk-nginx-module \
  #--without-http_ssi_module  # we cannot disable ssi because echo_location_async depends on it (i dunno why?!)

fi
if [ -f $target/sbin/nginx ]; then
    rm -f $target/sbin/nginx
fi
if [ -f $target/logs/nginx.pid ]; then
    kill `cat $target/logs/nginx.pid`
fi
make -j3 && make install

