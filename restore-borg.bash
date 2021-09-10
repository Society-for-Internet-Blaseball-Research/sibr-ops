#!/bin/bash

HOSTNAME=$(hostname)

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=3

COMPRESSION_LEVEL="zstd,11"
RCLONE_ACCOUNT="b2"
RCLONE_REPO="sibr-dual-backup"

export BORG_PASSPHRASE=''
export BORG_RSH=''
export BORG_REPO=''

showHelp() {
# `cat << EOF` This means that cat should stop reading when EOF is detected
cat << EOF  
Usage: restore-borg -v <espo-version> [-hrV]
Restore a volume and/or database from a borg backup

-h,     --help                  Display help

-v,     --espo-version          Set and Download specific version of EspoCRM

-r,     --rebuild               Rebuild php vendor directory using composer and compiled css using grunt

-V,     --verbose               Run script in verbose mode. Will print out each step of execution.

EOF
# EOF is found above and hence cat command stops reading. This is equivalent to echo but much neater when printing out.
}


HOST=""
CONTAINER_NAME=""
VERBOSE=0
DRY_RUN=0

# $@ is all command line parameters passed to the script.
# -o is for short options like -v
# -l is for long options with double dash like --version
# the comma separates different long options
# -a is for long options with single dash like -version
options=$(getopt -l "help,host:,container_name:,verbose,dry_run" -o "hv" -- "$@")

# set --:
# If no arguments follow this option, then the positional parameters are unset. Otherwise, the positional parameters 
# are set to the arguments, even if some of them begin with a ‘-’.
eval set -- "$options"

while true 
do
    case $1 in
        -h|--help) 
            showHelp
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            set -xv  # Set xtrace and verbose mode.
            ;;
        --host)
            shift
            HOST=$1
            ;;
        --container_name)
            shift
            CONTAINER_NAME=$1
            ;;
        --dry-run)
            shift
            DRY_RUN=1
            ;;
        --)
            shift
            break;;
    esac
shift
done

while read -r -u 3 CONTAINER_ID ; do
    # docker inspect 14b23ea3832f | jq '.[].Config.Env[]|select(startswith("POSTGRES_DB"))'
    DOCKER_DATA=$(docker inspect $CONTAINER_ID | jq '.[]')
    DOCKER_NAME=$(echo $DOCKER_DATA | jq -r .Name | cut -c2-)

    ARCHIVE_NAME=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.name\"])
    DATABASE_TYPE=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.database\"])
    
    echo "Restoring $DOCKER_NAME mounts"

    while read -r -u 4 MOUNT_SOURCE ; do
        echo "Mount: $(echo $MOUNT_SOURCE | jq .Source) -> $(echo $MOUNT_SOURCE | jq .Destination)"
    done 4< <(echo $DOCKER_DATA | jq -c .Mounts[])

    BORG_USER=$(echo $DOCKER_DATA | jq '.Config.Env[]|select(startswith("BORG_USER"))' | grep -P "^BORG_USER=" | sed 's/[^=]*=//')
    BORG_PASS=$(echo $DOCKER_DATA | jq '.Config.Env[]|select(startswith("BORG_PASSWORD"))' | grep -P "^BORG_PASSWORD=" | sed 's/[^=]*=//')
    BORG_DB=$(echo $DOCKER_DATA | jq '.Config.Env[]|select(startswith("BORG_DB"))' | grep -P "^BORG_DB=" | sed 's/[^=]*=//')

    # case $DATABASE_TYPE in
    #     postgres|postgresql|psql)
    #         info "Starting backup of $CONTAINER_ID into $ARCHIVE_NAME via pg_dump"

    #         docker exec -u 0 -i -e PGPASSWORD="$BORG_PASS" $CONTAINER_ID pg_dump -Z0 -Fc --username=$BORG_USER $BORG_DB | /usr/local/bin/borg create                         \
    #             --verbose                           \
    #             --filter AME                        \
    #             --list                              \
    #             --stats                             \
    #             --show-rc                           \
    #             --compression $COMPRESSION_LEVEL    \
    #             --exclude-caches                    \
    #             ::"{hostname}-$ARCHIVE_NAME-{now}" -
    #     ;;

    #     mariadb|mysql)
    #         info "Starting backup of $CONTAINER_ID into $ARCHIVE_NAME via mysqldump"

    #         docker exec -u 0 -i $CONTAINER_ID mysqldump -u $BORG_USER --password=$BORG_PASS $BORG_DB | /usr/local/bin/borg create \
    #             --verbose                           \
    #             --filter AME                        \
    #             --list                              \
    #             --stats                             \
    #             --show-rc                           \
    #             --compression $COMPRESSION_LEVEL    \
    #             --exclude-caches                    \
    #             ::"{hostname}-$ARCHIVE_NAME-{now}" -
    #     ;;

    #     *)
    #         info "Failing to backup $CONTAINER_ID into $ARCHIVE_NAME - unknown database type $DATABASE_TYPE"
    #     ;;

    # esac

    # if [[ -n $RCLONE_ACCOUNT && -n $RCLONE_REPO ]]; then
    #     info "Uploading $ARCHIVE_NAME backups with rclone"

    #     rclone copy --progress --transfers 32 $BORG_REPO "$RCLONE_ACCOUNT:/$RCLONE_REPO/$HOSTNAME"
    # else
    #     info "Not using rclone"
    # fi

    # info "Pruning $ARCHIVE_NAME backups; maintaining $KEEP_DAILY daily, $KEEP_WEEKLY weekly, $KEEP_MONTHLY monthly, and $KEEP_YEARLY yearly backups"

    # /usr/local/bin/borg prune \
    #     --list \
    #     --prefix "{hostname}-$ARCHIVE_NAME-" \
    #     --show-rc \
    #     --keep-daily $KEEP_DAILY \
    #     --keep-weekly $KEEP_WEEKLY \
    #     --keep-monthly $KEEP_MONTHLY \
    #     --keep-yearly $KEEP_YEARLY
done 3< <(docker ps --format '{{.ID}}' --filter "name=$CONTAINER_NAME")

# # First up, we need to get two archives --
# # One for the mounts, etc
# BORG_MOUNTS_NAME=$(borg list -P $HOST-core --short --last 1)

# # And one for the database
# BORG_DATABASE_NAME=$(borg list -P $HOST-$ARCHIVE_NAME --short --last 1)

# # To restore our mounts, we need to query docker

# borg extract --dry-run --list $BORG_ARCHIVE_NAME

echo $BORG_ARCHIVE_NAME

unset BORG_REPO
unset BORG_RSH
unset BORG_PASSPHRASE