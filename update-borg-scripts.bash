#!/bin/bash

BACKUP_FILE='/usr/local/bin/backup-borg'
RESTORE_FILE='/usr/local/bin/restore-borg'
UPDATE_FILE='/usr/local/bin/update-borg-scripts'

wget "https://raw.githubusercontent.com/Society-for-Internet-Blaseball-Research/sibr-ops/master/backup-borg.bash" -o $BACKUP_FILE
wget "https://raw.githubusercontent.com/Society-for-Internet-Blaseball-Research/sibr-ops/master/restore-borg.bash" -o $RESTORE_FILE
wget "https://raw.githubusercontent.com/Society-for-Internet-Blaseball-Research/sibr-ops/master/update-borg-scripts.bash" -o $UPDATE_FILE

BORG_REPO="$1"
BORG_PASSPHRASE="$2"
BORG_RSH="$3"

PATTERN="$BORG_REPO" perl -pi.bak -e "s/export BORG_REPO=''/export BORG_REPO='\$ENV{PATTERN}'/" $BACKUP_FILE
PATTERN="$BORG_PASSPHRASE" perl -pi.bak -e "s/export BORG_PASSPHRASE=''/export BORG_PASSPHRASE='\$ENV{PATTERN}'/" $BACKUP_FILE
PATTERN="$BORG_RSH" perl -pi.bak -e "s/export BORG_RSH=''/export BORG_RSH='\$ENV{PATTERN}'/" $BACKUP_FILE