#!/bin/bash

OUTPUT='/usr/local/bin/backup-borg'
curl $1 > $OUTPUT

PATTERN="$2" perl -pi.bak -e "s/export BORG_REPO=''/export BORG_REPO='\$ENV{PATTERN}'/" $OUTPUT
PATTERN="$3" perl -pi.bak -e "s/export BORG_PASSPHRASE=''/export BORG_PASSPHRASE='\$ENV{PATTERN}'/" $OUTPUT
PATTERN="$4" perl -pi.bak -e "s/export BORG_RSH=''/export BORG_RSH='\$ENV{PATTERN}'/" $OUTPUT