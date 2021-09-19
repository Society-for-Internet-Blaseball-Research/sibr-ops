#!/bin/bash

# Each backup we perform has three important stages -- perform, upload, then prune.
# We perform a few backups, one under {hostname}-core for the core data, and then one for each database we need to back up

export BORG_PASSPHRASE=''
export BORG_RSH=''
export BORG_REPO=''

showHelp() {
# `cat << EOF` This means that cat should stop reading when EOF is detected
cat << EOF  
Usage: backup-borg  [--skip_core] [--skip_docker]
                    [--borg_repo <repository>] [--borg_passphrase <passphrase>] [--borg_rsh <remote shell>] 
                    [--host <hostname>] [--compression <compression level>] 
                    [--container_name <container name>] [--verbose] [--dry_run] [-hv]
Back up volumes and databases

-h,     --help                  Display help

-v,     --verbose               Run scripts in verbose mode.

EOF
# EOF is found above and hence cat command stops reading. This is equivalent to echo but much neater when printing out.
}

# $@ is all command line parameters passed to the script.
# -o is for short options like -v
# -l is for long options with double dash like --version
# the comma separates different long options
# -a is for long options with single dash like -version
options=$(getopt -l "help,,skip_core,skip_docker,borg_repo:,borg_passphrase:,borg_rsh:,host:,hostname:,compression:,container_name:,verbose,dry_run" -o "hv" -- "$@")

# set --:
# If no arguments follow this option, then the positional parameters are unset. Otherwise, the positional parameters 
# are set to the arguments, even if some of them begin with a ‘-’.
eval set -- "$options"

HOSTNAME=$(hostname)
CONTAINER_NAME=''

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=3

COMPRESSION_LEVEL="zstd,11"
RCLONE_ACCOUNT="b2"
RCLONE_REPO="sibr-dual-backup"

VERBOSE=0
DRY_RUN=0
SKIP_CORE=0
SKIP_DOCKER=0

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
        --skip_core)
            SKIP_CORE=1
            ;;
        --skip_docker)
            SKIP_DOCKER=1
            ;;
        --borg_repo)
            shift
            export BORG_REPO=$1
            ;;
        --borg_passphrase)
            shift
            export BORG_PASSPHRASE=$1
            ;;
        --borg_rsh)
            shift
            export BORG_RSH=$1
            ;;
        --host|--hostname)
            shift
            HOSTNAME=$1
            ;;
        --compression)
            shift
            COMPRESSION_LEVEL=$1
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

echo "Do you wish to back up the following containers?"

docker ps  --filter "label=dev.sibr.borg.name" --filter "name=$CONTAINER_NAME"

select yn in "Yes" "No"; do
    case $yn in
        Yes ) break;;
        No ) exit;;
    esac
done

# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$(date)" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

ARGS=()

if [[ $VERBOSE -eq 1 ]]; then
    ARGS+="--verbose"
fi

if [[ $DRY_RUN -eq 1 ]]; then
    ARGS+="--dry-run"
fi

if [[ $SKIP_CORE -eq 0 ]]; then
    info "Starting core backup for $HOSTNAME"

    # Backup the most important directories into an archive named after
    # the machine this script is currently running on:

    /usr/local/bin/borg create "${args[@]}" \
        --filter AME \
        --list \
        --stats \
        --show-rc \
        --compression $COMPRESSION_LEVEL \
        --exclude-caches \
        --exclude '/var/lib/docker/volumes/' \
        --exclude '/srv/docker/mediawiki*/db_data' \
        --exclude '/srv/docker/mediawiki*/db_backups' \
        --exclude '/srv/docker/matomo/db' \
        --exclude '/srv/docker/councilwiki/db_data' \
        --exclude '/srv/docker/glolfwiki/db_data' \
        --exclude '/srv/docker/datablase/nginx/cache' \
        --exclude '/var/lib/docker/volumes/netdata_netdatacache' \
        --exclude '/var/cache' \
        --exclude '/home/*/.cache/*' \
        --exclude '/var/tmp/*' \
        --exclude '/storage/restic' \
        --exclude '/storage/borg*' \
        ::'{hostname}-core-{now}' \
        /var \
        /srv \
        /etc \
        /storage

    core_backup_exit=$?

    if [[ -n $RCLONE_ACCOUNT && -n $RCLONE_REPO ]]; then
        info "Uploading backups with rclone"

        # TODO: Add rclone uploading
        rclone copy --progress --transfers 32 $BORG_REPO "$RCLONE_ACCOUNT:/$RCLONE_REPO/$HOSTNAME"
    else
        info "Not using rclone"
    fi

    info "Pruning core backups; maintaining $KEEP_DAILY daily, $KEEP_WEEKLY weekly, $KEEP_MONTHLY monthly, and $KEEP_YEARLY yearly backups"

    # Use the `prune` subcommand to maintain x daily, y weekly and z monthly
    # archives of THIS machine. The '{hostname}-core-' prefix is very important to
    # limit prune's operation to this machine's archives and not apply to
    # other machines' archives also:

    /usr/local/bin/borg prune "${args[@]}" \
        --list \
        --prefix '{hostname}-core-' \
        --show-rc \
        --keep-daily $KEEP_DAILY \
        --keep-weekly $KEEP_WEEKLY \
        --keep-monthly $KEEP_MONTHLY \
        --keep-yearly $KEEP_YEARLY

    core_prune_exit=$?
else
    info "Skipping core..."
fi

# Now we need to back up the individual databases

if [[ $SKIP_DOCKER -eq 0 ]]; then

    while read -r -u 3 CONTAINER_ID ; do
        DOCKER_DATA=$(docker inspect $CONTAINER_ID | jq '.[]')
        DOCKER_NAME=$(echo $DOCKER_DATA | jq -r .Name | cut -c2-)

        ARCHIVE_NAME=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.name\"])
        DATABASE_TYPE=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.database\"])
        BACKUP_VOLUMES=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.volumes.backup\"])

        if [[ -n $DATABASE_TYPE && "$DATABASE_TYPE" != "null" ]]; then
            # docker inspect 14b23ea3832f | jq '.[].Config.Env[]|select(startswith("POSTGRES_DB"))'

            BORG_USER=$(echo $DOCKER_DATA | jq -r '.Config.Env[]|select(startswith("BORG_USER"))' | grep -P "^BORG_USER=" | sed 's/[^=]*=//')
            BORG_PASS=$(echo $DOCKER_DATA | jq -r '.Config.Env[]|select(startswith("BORG_PASSWORD"))' | grep -P "^BORG_PASSWORD=" | sed 's/[^=]*=//')
            BORG_DB=$(echo $DOCKER_DATA | jq -r '.Config.Env[]|select(startswith("BORG_DB"))' | grep -P "^BORG_DB=" | sed 's/[^=]*=//')

            case $DATABASE_TYPE in
                postgres|postgresql|psql)
                    info "Starting backup of $DOCKER_NAME into $ARCHIVE_NAME via pg_dump"

                    docker exec -u 0 -e PGPASSWORD="$BORG_PASS" $CONTAINER_ID pg_dump -Z0 -Fc --username=$BORG_USER $BORG_DB | /usr/local/bin/borg create "${args[@]}" \
                        --filter AME                        \
                        --list                              \
                        --stats                             \
                        --show-rc                           \
                        --compression $COMPRESSION_LEVEL    \
                        --exclude-caches                    \
                        ::"{hostname}-$ARCHIVE_NAME-$DATABASE_TYPE-{now}" -
                ;;

                mariadb|mysql)
                    info "Starting backup of $DOCKER_NAME into $ARCHIVE_NAME via mysqldump"

                    docker exec -u 0 $CONTAINER_ID mysqldump -u $BORG_USER --password=$BORG_PASS --no-tablespaces $BORG_DB | /usr/local/bin/borg create "${args[@]}" \
                        --filter AME                        \
                        --list                              \
                        --stats                             \
                        --show-rc                           \
                        --compression $COMPRESSION_LEVEL    \
                        --exclude-caches                    \
                        ::"{hostname}-$ARCHIVE_NAME-$DATABASE_TYPE-{now}" -
                ;;

                *)
                    info "Failing to backup $DOCKER_NAME into $ARCHIVE_NAME - unknown database type $DATABASE_TYPE"
                ;;

            esac
        fi
        
        if [[ "$BACKUP_VOLUMES" = "true" ]]; then
            info "Starting backup of volumes of $DOCKER_NAME into $ARCHIVE_NAME"
            MOUNT_EXCLUSION=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.volumes.exclude\"])

            # MOUNTS=()
            # MOUNTS+=$(echo $DOCKER_DATA | jq -cr .Mounts[].Source)

            if [[ -n $MOUNT_EXCLUSION ]]; then
                /usr/local/bin/borg create "${args[@]}" \
                    --filter AME \
                    --list \
                    --stats \
                    --show-rc \
                    --compression $COMPRESSION_LEVEL \
                    --exclude-caches \
                    --exclude "$MOUNT_EXCLUSION" \
                    ::"{hostname}-$ARCHIVE_NAME-volumes-{now}" \
                    $(echo $DOCKER_DATA | jq -cr .Mounts[].Source)
            else
                /usr/local/bin/borg create "${args[@]}" \
                    --filter AME \
                    --list \
                    --stats \
                    --show-rc \
                    --compression $COMPRESSION_LEVEL \
                    --exclude-caches \
                    ::"{hostname}-$ARCHIVE_NAME-volumes-{now}" \
                    $(echo $DOCKER_DATA | jq -cr .Mounts[].Source)
            fi
        fi

        if [[ -n $RCLONE_ACCOUNT && -n $RCLONE_REPO ]]; then
            info "Uploading $ARCHIVE_NAME backups with rclone"

            rclone copy --progress --transfers 32 $BORG_REPO "$RCLONE_ACCOUNT:/$RCLONE_REPO/$HOSTNAME"
        else
            info "Not using rclone"
        fi

        info "Pruning $ARCHIVE_NAME backups; maintaining $KEEP_DAILY daily, $KEEP_WEEKLY weekly, $KEEP_MONTHLY monthly, and $KEEP_YEARLY yearly backups"

        if [[ -n $DATABASE_TYPE && "$DATABASE_TYPE" != "null" ]]; then
            /usr/local/bin/borg prune "${args[@]}" \
                --list \
                --prefix "{hostname}-$ARCHIVE_NAME-$DATABASE_TYPE-" \
                --show-rc \
                --keep-daily $KEEP_DAILY \
                --keep-weekly $KEEP_WEEKLY \
                --keep-monthly $KEEP_MONTHLY \
                --keep-yearly $KEEP_YEARLY
        fi

        if [[ "$BACKUP_VOLUMES" = "true" ]]; then
            /usr/local/bin/borg prune "${args[@]}" \
                --list \
                --prefix "{hostname}-$ARCHIVE_NAME-volumes-" \
                --show-rc \
                --keep-daily $KEEP_DAILY \
                --keep-weekly $KEEP_WEEKLY \
                --keep-monthly $KEEP_MONTHLY \
                --keep-yearly $KEEP_YEARLY
        fi
    done 3< <(docker ps --format '{{.ID}}' --filter "name=$CONTAINER_NAME" --filter "label=dev.sibr.borg.name")
else
    info "Skipping docker..."
fi

unset BORG_REPO
unset BORG_RSH
unset BORG_PASSPHRASE