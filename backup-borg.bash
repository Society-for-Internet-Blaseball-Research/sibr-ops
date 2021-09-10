#!/bin/bash

# Each backup we perform has three important stages -- perform, upload, then prune.
# We perform a few backups, one under {hostname}-core for the core data, and then one for each database we need to back up

HOSTNAME=$(hostname)

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=3

COMPRESSION_LEVEL="zstd,11"
RCLONE_ACCOUNT="b2"
RCLONE_REPO="sibr-dual-backup"

# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$(date)" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

backup() {
    info "Starting core backup for $HOSTNAME"

    # Backup the most important directories into an archive named after
    # the machine this script is currently running on:

    /usr/local/bin/borg create \
        --verbose \
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
        /root \
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

    /usr/local/bin/borg prune \
        --list \
        --prefix '{hostname}-core-' \
        --show-rc \
        --keep-daily $KEEP_DAILY \
        --keep-weekly $KEEP_WEEKLY \
        --keep-monthly $KEEP_MONTHLY \
        --keep-yearly $KEEP_YEARLY

    core_prune_exit=$?

    # Now we need to back up the individual databases

    while read -r -u 3 CONTAINER_ID ; do
        DOCKER_DATA=$(docker inspect $CONTAINER_ID | jq '.[]')
        DOCKER_NAME=$(echo $DOCKER_DATA | jq -r .Name | cut -c2-)

        ARCHIVE_NAME=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.name\"])
        DATABASE_TYPE=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.database\"])
        BACKUP_VOLUMES=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.volumes.backup\"])

        if [[ -n $DATABASE_TYPE ]]; then
            # docker inspect 14b23ea3832f | jq '.[].Config.Env[]|select(startswith("POSTGRES_DB"))'

            BORG_USER=$(echo $DOCKER_DATA | jq '.Config.Env[]|select(startswith("BORG_USER"))' | grep -P "^BORG_USER=" | sed 's/[^=]*=//')
            BORG_PASS=$(echo $DOCKER_DATA | jq '.Config.Env[]|select(startswith("BORG_PASSWORD"))' | grep -P "^BORG_PASSWORD=" | sed 's/[^=]*=//')
            BORG_DB=$(echo $DOCKER_DATA | jq '.Config.Env[]|select(startswith("BORG_DB"))' | grep -P "^BORG_DB=" | sed 's/[^=]*=//')

            case $DATABASE_TYPE in
                postgres|postgresql|psql)
                    info "Starting backup of $CONTAINER_ID into $ARCHIVE_NAME via pg_dump"

                    docker exec -u 0 -i -e PGPASSWORD="$BORG_PASS" $CONTAINER_ID pg_dump -Z0 -Fc --username=$BORG_USER $BORG_DB | /usr/local/bin/borg create                         \
                        --verbose                           \
                        --filter AME                        \
                        --list                              \
                        --stats                             \
                        --show-rc                           \
                        --compression $COMPRESSION_LEVEL    \
                        --exclude-caches                    \
                        ::"{hostname}-$ARCHIVE_NAME-$DATABASE_TYPE-{now}" -
                ;;

                mariadb|mysql)
                    info "Starting backup of $CONTAINER_ID into $ARCHIVE_NAME via mysqldump"

                    docker exec -u 0 -i $CONTAINER_ID mysqldump -u $BORG_USER --password=$BORG_PASS $BORG_DB | /usr/local/bin/borg create \
                        --verbose                           \
                        --filter AME                        \
                        --list                              \
                        --stats                             \
                        --show-rc                           \
                        --compression $COMPRESSION_LEVEL    \
                        --exclude-caches                    \
                        ::"{hostname}-$ARCHIVE_NAME-$DATABASE_TYPE-{now}" -
                ;;

                *)
                    info "Failing to backup $CONTAINER_ID into $ARCHIVE_NAME - unknown database type $DATABASE_TYPE"
                ;;

            esac
        fi
        
        if [[ $BACKUP_VOLUMES == "true" ]]; then
            info "Starting backup of volumes of $CONTAINER_ID into $ARCHIVE_NAME"
            MOUNT_EXCLUSION=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.volumes.exclude\"])

            MOUNTS=(echo $DOCKER_DATA | jq -cr .Mounts[].Source)

            if [[ -n $MOUNT_EXCLUSION ]]; then
                /usr/local/bin/borg create \
                    --verbose \
                    --filter AME \
                    --list \
                    --stats \
                    --show-rc \
                    --compression $COMPRESSION_LEVEL \
                    --exclude-caches \
                    --exclude "$MOUNT_EXCLUSION" \
                    ::"{hostname}-$ARCHIVE_NAME-volumes-{now}" \
                    "${MOUNTS[@]}"
            else
                /usr/local/bin/borg create \
                    --verbose \
                    --filter AME \
                    --list \
                    --stats \
                    --show-rc \
                    --compression $COMPRESSION_LEVEL \
                    --exclude-caches \
                    ::"{hostname}-$ARCHIVE_NAME-volumes-{now}" \
                    "${MOUNTS[@]}"
            fi
        fi

        if [[ -n $RCLONE_ACCOUNT && -n $RCLONE_REPO ]]; then
            info "Uploading $ARCHIVE_NAME backups with rclone"

            rclone copy --progress --transfers 32 $BORG_REPO "$RCLONE_ACCOUNT:/$RCLONE_REPO/$HOSTNAME"
        else
            info "Not using rclone"
        fi

        info "Pruning $ARCHIVE_NAME backups; maintaining $KEEP_DAILY daily, $KEEP_WEEKLY weekly, $KEEP_MONTHLY monthly, and $KEEP_YEARLY yearly backups"

        /usr/local/bin/borg prune \
            --list \
            --prefix "{hostname}-$ARCHIVE_NAME-" \
            --show-rc \
            --keep-daily $KEEP_DAILY \
            --keep-weekly $KEEP_WEEKLY \
            --keep-monthly $KEEP_MONTHLY \
            --keep-yearly $KEEP_YEARLY
    done 3< <(docker ps --format '{{.ID}}' --filter "label=dev.sibr.borg.database")
}

# Backup to our local repo
export BORG_PASSPHRASE=''
export BORG_RSH=''
export BORG_REPO=''
backup

# Backup to our local remote repo
#export BORG_REPO='/storage/borgclone'
#backup

# Now, sync with rclone
#rclone sync --transfers 32 --progress $BORG_REPO "b2:/sibr-dual-backup/$HOSTNAME"

unset BORG_REPO
unset BORG_RSH
unset BORG_PASSPHRASE