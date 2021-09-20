#!/bin/bash

BACKUP_FILE='/usr/local/bin/backup-borg'
RESTORE_FILE='/usr/local/bin/restore-borg'
UPDATE_FILE='/usr/local/bin/update-borg-scripts'

rm -rf sibr-ops
git clone https://github.com/Society-for-Internet-Blaseball-Research/sibr-ops.git
cp sibr-ops/backup-borg.bash $BACKUP_FILE
cp sibr-ops/restore-borg.bash $RESTORE_FILE
cp sibr-ops/update-borg-scripts.bash $UPDATE_FILE
rm -rf sibr-ops

BORG_REPO="$1"
BORG_PASSPHRASE="$2"
BORG_RSH="$3"

PATTERN="$BORG_REPO" perl -pi.bak -e "s/%BORG_REPO%/\$ENV{PATTERN}/" $BACKUP_FILE
PATTERN="$BORG_PASSPHRASE" perl -pi.bak -e "s/%BORG_PASSPHRASE%/\$ENV{PATTERN}/" $BACKUP_FILE
PATTERN="$BORG_RSH" perl -pi.bak -e "s/%BORG_RSH%/\$ENV{PATTERN}/" $BACKUP_FILE

PATTERN="$BORG_REPO" perl -pi.bak -e "s/%BORG_REPO%/\$ENV{PATTERN}/" $RESTORE_FILE
PATTERN="$BORG_PASSPHRASE" perl -pi.bak -e "s/%BORG_PASSPHRASE%/\$ENV{PATTERN}/" $RESTORE_FILE
PATTERN="$BORG_RSH" perl -pi.bak -e "s/%BORG_RSH%/\$ENV{PATTERN}/" $RESTORE_FILE

argbash $BACKUP_FILE -o $BACKUP_FILE
argbash $RESTORE_FILE -o $RESTORE_FILE

argbash $BACKUP_FILE --type completion --strip all -o /etc/bash_completion.d/backup-borg.sh
argbash $RESTORE_FILE --type completion --strip all -o /etc/bash_completion.d/restore-borg.sh