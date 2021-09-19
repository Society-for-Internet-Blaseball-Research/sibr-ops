#!/bin/bash

BACKUP_FILE='/usr/local/bin/backup-borg'
RESTORE_FILE='/usr/local/bin/restore-borg'
UPDATE_FILE='/usr/local/bin/update-borg-scripts'

curl "https://raw.githubusercontent.com/Society-for-Internet-Blaseball-Research/sibr-ops/master/backup-borg.m4" > $BACKUP_FILE
curl "https://raw.githubusercontent.com/Society-for-Internet-Blaseball-Research/sibr-ops/master/restore-borg.m4" > $RESTORE_FILE
curl "https://raw.githubusercontent.com/Society-for-Internet-Blaseball-Research/sibr-ops/master/update-borg-scripts.bash" > $UPDATE_FILE

BORG_REPO="$1"
BORG_PASSPHRASE="$2"
BORG_RSH="$3"

PATTERN="$BORG_REPO" perl -pi.bak -e "s/%BORG_REPO%/\$ENV{PATTERN}/" $BACKUP_FILE
PATTERN="$BORG_PASSPHRASE" perl -pi.bak -e "s/%BORG_PASSPHRASE%/\$ENV{PATTERN}/" $BACKUP_FILE
PATTERN="$BORG_RSH" perl -pi.bak -e "s/%BORG_RSH%/\$ENV{PATTERN}/" $BACKUP_FILE

argbash $BACKUP_FILE -o $BACKUP_FILE
argbash $RESTORE_FILE -o $RESTORE_FILE

argbash $BACKUP_FILE --type completion --strip all -o /etc/bash_completion.d/backup-borg.sh
argbash $RESTORE_FILE --type completion --strip all -o /etc/bash_completion.d/restore-borg.sh