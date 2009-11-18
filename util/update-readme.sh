#!/bin/bash

perl util/wiki2pod.pl doc/readme.wiki > /tmp/a.pod && pod2text /tmp/a.pod > README

