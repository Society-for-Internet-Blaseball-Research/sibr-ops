#!/bin/bash

BACKUP_FILE='/usr/local/bin/backup-borg'
wget "https://raw.githubusercontent.com/Society-for-Internet-Blaseball-Research/sibr-ops/master/backup-borg.bash" -o $BACKUP_FILE

PATTERN="$1" perl -pi.bak -e "s/export BORG_REPO=''/export BORG_REPO='\$ENV{PATTERN}'/" $BACKUP_FILE
PATTERN="$2" perl -pi.bak -e "s/export BORG_PASSPHRASE=''/export BORG_PASSPHRASE='\$ENV{PATTERN}'/" $BACKUP_FILE
PATTERN="$3" perl -pi.bak -e "s/export BORG_RSH=''/export BORG_RSH='\$ENV{PATTERN}'/" $BACKUP_FILE