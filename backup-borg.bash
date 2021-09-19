#!/bin/bash
#
# m4_ignore(
echo "WARNING - This is just a script template, not the script (yet) - pass it to 'argbash' to fix this." >&2
exit 11  
#)
# ARG_OPTIONAL_SINGLE(host,H,[Override the default host for this script])
# ARG_OPTIONAL_SINGLE(container,,[Filter containers to backup])
# ARG_OPTIONAL_SINGLE(compression,C,[Compression level for the backups],[zstd,11])
# ARG_OPTIONAL_SINGLE(rclone-account,,[Account to use for backing up with rclone],[b2])
# ARG_OPTIONAL_SINGLE(rclone-bucket,,[Bucket to use for backing up with rclone],[sibr-dual-backup])
# ARG_OPTIONAL_SINGLE(transfers,,[Number of file transfers to run in parallel],[32])
# ARG_OPTIONAL_BOOLEAN(dry-run,n,[Simulate operations without any output])
# ARG_OPTIONAL_BOOLEAN(progress,P,[Show progress bar])
# ARG_OPTIONAL_BOOLEAN(list,,[List output from Borg])
# ARG_OPTIONAL_BOOLEAN(stats,s,[Show stats from Borg])
# ARG_OPTIONAL_BOOLEAN(skip-core,,[Skip core backup])
# ARG_OPTIONAL_BOOLEAN(skip-docker,,[Skip docker backup])
# ARG_OPTIONAL_SINGLE(borg-repo,,[Override the default borg repository])
# ARG_OPTIONAL_SINGLE(borg-pass,,[Override the default borg passphrase])
# ARG_OPTIONAL_SINGLE(borg-rsh,,[Override the default borg remote shell command])
# ARG_HELP([Restore a volume and/or database from a borg backup])
# ARG_USE_PROGRAM([borg], [BORG], [Borg needs to be installed!],[Borg program location])
# ARG_USE_PROGRAM([rclone], [RCLONE],,[rclone program location])
# ARG_VERBOSE([v])
# ARGBASH_GO

# [ <-- needed because of Argbash

# Each backup we perform has three important stages -- perform, upload, then prune.
# We perform a few backups, one under {hostname}-core for the core data, and then one for each database we need to back up

# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$(date)" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

export BORG_REPO
export BORG_PASSPHRASE
export BORG_RSH

# If no envvar is provided, we should provide our default
test -z "${BORG_REPO// }" && BORG_REPO='%BORG_REPO%'
test -z "${BORG_PASSPHRASE// }" && BORG_PASSPHRASE='%BORG_PASSPHRASE%'
test -z "${BORG_RSH// }" && BORG_RSH='%BORG_RSH%'

# If argument is present, override the environmental variable, even if it is present
test "${_arg_borg_repo// }" && BORG_REPO=$_arg_borg_repo
test "${_arg_borg_pass// }" && BORG_PASSPHRASE=$_arg_borg_pass
test "${_arg_borg_rsh// }" && BORG_RSH=$_arg_borg_rsh

HOST="${_arg_host:-$(hostname)}"
CONTAINER_NAME="$_arg_container"

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=3

COMPRESSION_LEVEL="$_arg_compression"
RCLONE_ACCOUNT="$_arg_rclone_account"
RCLONE_BUCKET="$_arg_rclone_bucket"

VERBOSE=$_arg_verbose
DRY_RUN=0
SKIP_CORE=0
SKIP_DOCKER=0

if [[ "$_arg_dry_run" = "on" ]]; then
    DRY_RUN=1
fi

if [[ "$_arg_skip_core" = "on" ]]; then
    SKIP_CORE=1
fi

if [[ "$_arg_skip_docker" = "on" ]]; then
    SKIP_DOCKER=1
fi

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

BORG_CREATE=()
BORG_PRUNE=()
RCLONE_UPLOAD=()

if [[ $VERBOSE -eq 1 ]]; then
    BORG_CREATE+="--verbose"
    BORG_PRUNE+="--verbose"
    RCLONE_UPLOAD+="--verbose"
fi

if [[ $DRY_RUN -eq 1 ]]; then
    BORG_CREATE+="--dry-run"
    BORG_PRUNE+="--dry-run"
    RCLONE_UPLOAD+="--dry-run"
fi

if [[ "$_arg_progress" = "on" ]]; then
    BORG_CREATE+="--progress"
    BORG_PRUNE+="--progress"
    RCLONE_UPLOAD+="--progress"
fi

if [[ "$_arg_list" = "on" ]]; then
    BORG_CREATE+="--list"
    BORG_PRUNE+="--list"
fi

if [[ "$_arg_stats" = "on" ]]; then
    BORG_CREATE+="--stats"
    BORG_PRUNE+="--stats"
fi

if [[ $SKIP_CORE -eq 0 ]]; then
    info "Starting core backup for $HOSTNAME"

    # Backup the most important directories into an archive named after
    # the machine this script is currently running on:

    "$BORG" create "${BORG_CREATE[@]}" \
        --filter AME \
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

    if [[ $DRY_RUN -eq 0 ]]; then
        if [[ -n $RCLONE_ACCOUNT && -n $RCLONE_BUCKET && -n $RCLONE ]]; then
            info "Uploading backups with rclone"

            # TODO: Add rclone uploading
            "$RCLONE" copy "${RCLONE_UPLOAD[@]}" --transfers $_arg_transfers $BORG_REPO "$RCLONE_ACCOUNT:/$RCLONE_BUCKET/$HOSTNAME"
        else
            info "Not using rclone"
        fi
    fi

    info "Pruning core backups; maintaining $KEEP_DAILY daily, $KEEP_WEEKLY weekly, $KEEP_MONTHLY monthly, and $KEEP_YEARLY yearly backups"

    # Use the `prune` subcommand to maintain x daily, y weekly and z monthly
    # archives of THIS machine. The '{hostname}-core-' prefix is very important to
    # limit prune's operation to this machine's archives and not apply to
    # other machines' archives also:

    "$BORG" prune "${BORG_PRUNE[@]}" \
        --prefix '{hostname}-core-' \
        --show-rc \
        --keep-daily $KEEP_DAILY \
        --keep-weekly $KEEP_WEEKLY \
        --keep-monthly $KEEP_MONTHLY \
        --keep-yearly $KEEP_YEARLY
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

                    docker exec -u 0 -e PGPASSWORD="$BORG_PASS" $CONTAINER_ID pg_dump -Z0 -Fc --username=$BORG_USER $BORG_DB | "$BORG" create "${BORG_CREATE[@]}" \
                        --filter AME                        \
                        --show-rc                           \
                        --compression $COMPRESSION_LEVEL    \
                        --exclude-caches                    \
                        ::"{hostname}-$ARCHIVE_NAME-$DATABASE_TYPE-{now}" -
                ;;

                mariadb|mysql)
                    info "Starting backup of $DOCKER_NAME into $ARCHIVE_NAME via mysqldump"

                    docker exec -u 0 $CONTAINER_ID mysqldump -u $BORG_USER --password=$BORG_PASS --no-tablespaces $BORG_DB | "$BORG" create "${BORG_CREATE[@]}" \
                        --filter AME                        \
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
                "$BORG" create "${BORG_CREATE[@]}" \
                    --filter AME \
                    --show-rc \
                    --compression $COMPRESSION_LEVEL \
                    --exclude-caches \
                    --exclude "$MOUNT_EXCLUSION" \
                    ::"{hostname}-$ARCHIVE_NAME-volumes-{now}" \
                    $(echo $DOCKER_DATA | jq -cr .Mounts[].Source)
            else
                "$BORG" create "${BORG_CREATE[@]}" \
                    --filter AME \
                    --show-rc \
                    --compression $COMPRESSION_LEVEL \
                    --exclude-caches \
                    ::"{hostname}-$ARCHIVE_NAME-volumes-{now}" \
                    $(echo $DOCKER_DATA | jq -cr .Mounts[].Source)
            fi
        fi

        if [[ $DRY_RUN -eq 0 ]]; then
            if [[ -n $RCLONE_ACCOUNT && -n $RCLONE_BUCKET && -n $RCLONE ]]; then
                info "Uploading $ARCHIVE_NAME backups with rclone"

                "$RCLONE" copy "${RCLONE_UPLOAD[@]}" --transfers $_arg_transfers $BORG_REPO "$RCLONE_ACCOUNT:/$RCLONE_BUCKET/$HOSTNAME"
            else
                info "Not using rclone"
            fi
        fi

        info "Pruning $ARCHIVE_NAME backups; maintaining $KEEP_DAILY daily, $KEEP_WEEKLY weekly, $KEEP_MONTHLY monthly, and $KEEP_YEARLY yearly backups"

        if [[ -n $DATABASE_TYPE && "$DATABASE_TYPE" != "null" ]]; then
            "$BORG" prune "${BORG_PRUNE[@]}" \
                --prefix "{hostname}-$ARCHIVE_NAME-$DATABASE_TYPE-" \
                --show-rc \
                --keep-daily $KEEP_DAILY \
                --keep-weekly $KEEP_WEEKLY \
                --keep-monthly $KEEP_MONTHLY \
                --keep-yearly $KEEP_YEARLY
        fi

        if [[ "$BACKUP_VOLUMES" = "true" ]]; then
            "$BORG" prune "${BORG_PRUNE[@]}" \
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

# ] <-- needed because of Argbash