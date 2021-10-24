#!/usr/bin/env bash
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
# ARG_OPTIONAL_SINGLE(pgbackrest-type,,[Type of backup to perform with pgBackRest])
# ARG_OPTIONAL_SINGLE(database-type,,[Filter containers to backup by database type])
# ARG_OPTIONAL_SINGLE(force-type,,[Force database to restore via a certain method (Unstable!)])
# ARG_OPTIONAL_BOOLEAN(dry-run,n,[Simulate operations without any output])
# ARG_OPTIONAL_BOOLEAN(progress,P,[Show progress bar])
# ARG_OPTIONAL_BOOLEAN(list,,[List output from Borg])
# ARG_OPTIONAL_BOOLEAN(stats,s,[Show stats from Borg])
# ARG_OPTIONAL_BOOLEAN(skip-core,,[Skip core backup])
# ARG_OPTIONAL_BOOLEAN(skip-docker,,[Skip docker backup])
# ARG_OPTIONAL_BOOLEAN(skip-rclone,,[Skip rclone upload])
# ARG_OPTIONAL_BOOLEAN(accept,Y,[Accept containers to backup without input])
# ARG_OPTIONAL_BOOLEAN(wait-for-lock,,[If a lock is present, wait for other process to shut down])
# ARG_OPTIONAL_BOOLEAN(break-lock,,[If a lock is present, break it regardless of if the other process is active])
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

# First up, check for a lockfile

LOCKFILE="/tmp/dev.sibr.borg.lock"

if [[ -f $LOCKFILE ]]; then
  if [[ "$arg_break_lock" = "on" ]]; then
    echo "Breaking lockfile"
    rm $LOCKFILE
  else
    PID=$(cat $LOCKFILE)
    if [[ -f "/proc/$PID/stat" ]]; then
      echo "Borg is currently in use, waiting on $PID"

      if [[ $_arg_wait_for_lock = "off" ]]; then
        exit 1
      fi

      wait "$PID"
    fi

    echo "Breaking stale lockfile"
    rm $LOCKFILE
  fi
fi

echo $$ >$LOCKFILE
trap 'rm "$LOCKFILE"' EXIT

export BORG_REPO
export BORG_PASSPHRASE
export BORG_RSH

# If no envvar is provided, we should provide our default
test -z "${BORG_REPO// /}" && BORG_REPO='%BORG_REPO%'
test -z "${BORG_PASSPHRASE// /}" && BORG_PASSPHRASE='%BORG_PASSPHRASE%'
test -z "${BORG_RSH// /}" && BORG_RSH='%BORG_RSH%'

# If argument is present, override the environmental variable, even if it is present
test "${_arg_borg_repo// /}" && BORG_REPO=$_arg_borg_repo
test "${_arg_borg_pass// /}" && BORG_PASSPHRASE=$_arg_borg_pass
test "${_arg_borg_rsh// /}" && BORG_RSH=$_arg_borg_rsh

HOST="${_arg_host:-$(hostname)}"

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=3

COMPRESSION_LEVEL="$_arg_compression"
RCLONE_ACCOUNT="$_arg_rclone_account"
RCLONE_BUCKET="$_arg_rclone_bucket"
FORCED_TYPE="$_arg_force_type"

VERBOSE=$_arg_verbose
DRY_RUN=0
SKIP_CORE=0
SKIP_DOCKER=0
SKIP_RCLONE=0

if [[ "$_arg_dry_run" = "on" ]]; then
  DRY_RUN=1
fi

if [[ "$_arg_skip_core" = "on" ]]; then
  SKIP_CORE=1
fi

if [[ "$_arg_skip_docker" = "on" ]]; then
  SKIP_DOCKER=1
fi

if [[ "$_arg_skip_rclone" = "on" ]]; then
  SKIP_RCLONE=1
fi

FILTER_ARGS=("--filter" "label=dev.sibr.borg.name")
if [[ -n "$_arg_container" ]]; then
  FILTER_ARGS+=("--filter" "name=$_arg_container")
fi

if [[ -n "$_arg_database_type" ]]; then
  FILTER_ARGS+=("--filter" "label=dev.sibr.borg.database=$_arg_database_type")
fi

if [[ -n "$_arg_compose_file" ]]; then
  if ! COMPOSE_FILE=$(cat "$_arg_compose_file"); then
    exit $?
  fi

  echo "$COMPOSE_FILE"
else
  docker ps "${FILTER_ARGS[@]}"
fi

if [[ "$_arg_accept" = "off" ]]; then
  echo "Do you wish to back up these containers?"

  select yn in "Yes" "No"; do
    case $yn in
    Yes) break ;;
    No) exit ;;
    esac
  done
fi

# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$(date)" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

BORG_CREATE=()
BORG_PRUNE=()
RCLONE_UPLOAD=()
PGBACKREST_BACKUP=()

if [[ $VERBOSE -eq 1 ]]; then
  BORG_CREATE+=("--verbose")
  BORG_PRUNE+=("--verbose")
  RCLONE_UPLOAD+=("--verbose")
fi

if [[ $DRY_RUN -eq 1 ]]; then
  BORG_CREATE+=("--dry-run")
  BORG_PRUNE+=("--dry-run")
  RCLONE_UPLOAD+=("--dry-run")
fi

if [[ "$_arg_progress" = "on" ]]; then
  BORG_CREATE+=("--progress")
  BORG_PRUNE+=("--progress")
  RCLONE_UPLOAD+=("--progress")
fi

if [[ "$_arg_list" = "on" ]]; then
  BORG_CREATE+=("--list")
  BORG_PRUNE+=("--list")
fi

if [[ "$_arg_stats" = "on" ]]; then
  BORG_CREATE+=("--stats")
  BORG_PRUNE+=("--stats")
fi

if [[ -n "$_arg_pgbackrest_type" ]]; then
  PGBACKREST_BACKUP+=("--type=$_arg_pgbackrest_type")
fi

docker_env() {
  # shellcheck disable=SC2089
  printf -v JQ_FILTER '.Config.Env[]|select(startswith("%q"))' "$1"
  echo "$DOCKER_DATA" | jq -r "$JQ_FILTER" | grep -P "^$1=" | sed 's/[^=]*=//'
}

docker_label() {
  # shellcheck disable=SC2089
  printf -v JQ_FILTER '.Config.Labels["%q"]' "$1"
  echo "$DOCKER_DATA" | jq -r "$JQ_FILTER"
}

docker_mount() {
  # shellcheck disable=SC2089
  printf -v JQ_FILTER '.Mounts[]|select(.Destination|startswith("%q")).Source' "$1"
  echo "$DOCKER_DATA" | jq -r "$JQ_FILTER"
}

# usage: docker_file_env CONTAINER_ID VAR [DEFAULT]
#    ie: docker_file_env 'abcdef1234' 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
docker_file_env() {
  local var="$2"
  local fileVar="${var}_FILE"
  local def="${3:-}"
  local varVal
  local fileVarVal

  varVal="$(docker_env "$var")"
  fileVarVal="$(docker_env "$fileVar")"

  if [ "$varVal" ] && [ "$fileVarVal" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    return 1
  fi

  if [ "$varVal" ]; then
    echo "$varVal"
  elif [ "$fileVarVal" ]; then
    docker exec "$1" cat "$fileVarVal"
  else
    echo "$def"
  fi
}

if [[ $SKIP_CORE -eq 0 ]]; then
  info "Starting core backup for $HOSTNAME"

  # Backup the most important directories into an archive named after
  # the machine this script is currently running on:

  "$BORG" create "${BORG_CREATE[@]}" \
    --filter AME \
    --show-rc \
    --compression "$COMPRESSION_LEVEL" \
    --exclude-caches \
    --exclude '/var/lib/docker/volumes/' \
    --exclude '/srv/docker/' \
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

  if [[ $DRY_RUN -eq 0 && $SKIP_RCLONE -eq 0 ]]; then
    if [[ -n $RCLONE_ACCOUNT && -n $RCLONE_BUCKET && -n $RCLONE ]]; then
      info "Uploading backups with rclone"

      # TODO: Add rclone uploading
      "$RCLONE" copy "${RCLONE_UPLOAD[@]}" --transfers "$_arg_transfers" "$BORG_REPO" "$RCLONE_ACCOUNT:/$RCLONE_BUCKET/$HOSTNAME"
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
  while read -r -u 3 CONTAINER_ID; do
    DOCKER_DATA=$(docker inspect "$CONTAINER_ID" | jq '.[]')
    DOCKER_NAME=$(echo "$DOCKER_DATA" | jq -r .Name | cut -c2-)

    ARCHIVE_NAME=$(docker_label 'dev.sibr.borg.name')
    DATABASE_TYPE=$(docker_label 'dev.sibr.borg.database')
    BACKUP_VOLUMES=$(docker_label 'dev.sibr.borg.volumes.backup')

    if [[ -n $DATABASE_TYPE && "$DATABASE_TYPE" != "null" ]]; then
      # docker inspect 14b23ea3832f | jq '.[].Config.Env[]|select(startswith("POSTGRES_DB"))'

      BACKUP_TYPE="$DATABASE_TYPE"

      if [[ -n "$FORCED_TYPE" ]]; then
        if [[ "$_arg_accept" = "off" ]]; then
          echo "Are you SURE you wish to backup this database with a different database type (Expecting $DATABASE_TYPE, told $FORCED_TYPE)?"

          select yn in "Yes" "No" "Exit"; do
            case $yn in
            Yes)
              BACKUP_TYPE="$FORCED_TYPE"
              break
              ;;
            No)
              break
              ;;

            Exit)
              exit
              ;;
            esac
          done
        else
          echo "Restoring with $FORCED_TYPE rather than $DATABASE_TYPE"
          BACKUP_TYPE="$FORCED_TYPE"
        fi

      fi

      case $BACKUP_TYPE in
      postgres | postgresql | psql)
        BORG_USER=$(docker_file_env "$CONTAINER_ID" 'BORG_USER')
        BORG_PASS=$(docker_file_env "$CONTAINER_ID" 'BORG_PASSWORD')
        BORG_DB=$(docker_file_env "$CONTAINER_ID" 'BORG_DB')

        if [[ -n "$BORG_USER" && -n "$BORG_PASS" && -n "$BORG_DB" ]]; then
          info "Starting backup of $DOCKER_NAME into $ARCHIVE_NAME via pg_dump"

          docker exec -u 0 -e PGPASSWORD="$BORG_PASS" "$CONTAINER_ID" pg_dump -Z0 -Fc "--username=$BORG_USER" "$BORG_DB" | "$BORG" create "${BORG_CREATE[@]}" \
            --filter AME \
            --show-rc \
            --compression "$COMPRESSION_LEVEL" \
            --exclude-caches \
            ::"{hostname}-$ARCHIVE_NAME-$BACKUP_TYPE-{now}" -
        else
          info "Failed to backup $DOCKER_NAME - missing BORG_USER / BORG_PASSWORD / BORG_DB"
        fi
        ;;

      pgbackrest | backrest)
        # pgBackRest doesn't quite work in the same way as our other dumps; we want to force a backup, then do a borg backup of that volume
        BACKREST_STANZA=$(docker_file_env "$CONTAINER_ID" 'BACKREST_STANZA')
        BACKREST_DIR=$(docker_file_env "$CONTAINER_ID" 'PGBACKREST_DIR')
        BACKREST_MOUNT=$(docker_mount "$BACKREST_DIR")

        if [[ -n "$BACKREST_STANZA" && -n "$BACKREST_MOUNT" ]]; then
          info "Starting backup of $DOCKER_NAME into $ARCHIVE_NAME via pgbackrest ($BACKREST_MOUNT)"

          if docker exec -u 999 -i "$CONTAINER_ID" pgbackrest "--stanza=$BACKREST_STANZA" --log-level-console=detail "${PGBACKREST_BACKUP[@]}" backup; then
            "$BORG" create "${BORG_CREATE[@]}" \
              --filter AME \
              --show-rc \
              --compression "$COMPRESSION_LEVEL" \
              --exclude-caches \
              ::"{hostname}-$ARCHIVE_NAME-$BACKUP_TYPE-{now}" \
              "$BACKREST_MOUNT"
          fi
        else
          info "Failed to backup $DOCKER_NAME - missing BACKREST_STANZA"
        fi
        ;;

      mariadb | mysql)
        BORG_USER=$(docker_file_env "$CONTAINER_ID" 'BORG_USER')
        BORG_PASS=$(docker_file_env "$CONTAINER_ID" 'BORG_PASSWORD')
        BORG_DB=$(docker_file_env "$CONTAINER_ID" 'BORG_DB')

        if [[ -n "$BORG_USER" && -n "$BORG_PASS" && -n "$BORG_DB" ]]; then
          info "Starting backup of $DOCKER_NAME into $ARCHIVE_NAME via mysqldump"

          docker exec -u 0 "$CONTAINER_ID" mysqldump -u "$BORG_USER" "--password=$BORG_PASS" --no-tablespaces "$BORG_DB" | "$BORG" create "${BORG_CREATE[@]}" \
            --filter AME \
            --show-rc \
            --compression "$COMPRESSION_LEVEL" \
            --exclude-caches \
            ::"{hostname}-$ARCHIVE_NAME-$BACKUP_TYPE-{now}" -
        else
          info "Failed to backup $DOCKER_NAME - missing BORG_USER / BORG_PASSWORD / BORG_DB"
        fi
        ;;

      *)
        info "Failing to backup $DOCKER_NAME into $ARCHIVE_NAME - unknown database type $BACKUP_TYPE"
        ;;

      esac
    fi

    if [[ "$BACKUP_VOLUMES" = "true" ]]; then
      info "Starting backup of volumes of $DOCKER_NAME into $ARCHIVE_NAME"
      MOUNT_EXCLUSION=$(docker_label 'dev.sibr.borg.volumes.exclude')

      # MOUNTS=()
      # MOUNTS+=$(echo $DOCKER_DATA | jq -cr .Mounts[].Source)

      ARGS=("${BORG_CREATE[@]}")
      if [[ "$DATABASE_TYPE" =~ pgbackrest|backrest ]]; then
        info "Excluding pgBackRest mount"
        BACKREST_DIR=$(docker_env 'PGBACKREST_DIR')
        BACKREST_MOUNT=$(docker_mount "$BACKREST_DIR")

        ARGS+=("--exclude" "$BACKREST_MOUNT")
      fi

      if [[ -n $MOUNT_EXCLUSION ]]; then
        ARGS+=("--exclude" "$MOUNT_EXCLUSION")
      fi

      mapfile -t MOUNT_SOURCES < <(echo "$DOCKER_DATA" | jq -cr .Mounts[].Source)

      "$BORG" create "${ARGS[@]}" \
        --filter AME \
        --show-rc \
        --compression "$COMPRESSION_LEVEL" \
        --exclude-caches \
        ::"{hostname}-$ARCHIVE_NAME-volumes-{now}" \
        "${MOUNT_SOURCES[@]}"
    fi

    if [[ $DRY_RUN -eq 0 && $SKIP_RCLONE -eq 0 ]]; then
      if [[ -n $RCLONE_ACCOUNT && -n $RCLONE_BUCKET && -n $RCLONE ]]; then
        info "Uploading $ARCHIVE_NAME backups with rclone"

        "$RCLONE" copy "${RCLONE_UPLOAD[@]}" --transfers "$_arg_transfers" "$BORG_REPO" "$RCLONE_ACCOUNT:/$RCLONE_BUCKET/$HOSTNAME"
      else
        info "Not using rclone"
      fi
    fi

    if [[ -n $DATABASE_TYPE && "$DATABASE_TYPE" != "null" ]]; then
      info "Pruning $ARCHIVE_NAME database backups; maintaining $KEEP_DAILY daily, $KEEP_WEEKLY weekly, $KEEP_MONTHLY monthly, and $KEEP_YEARLY yearly backups"

      "$BORG" prune "${BORG_PRUNE[@]}" \
        --prefix "{hostname}-$ARCHIVE_NAME-$DATABASE_TYPE-" \
        --show-rc \
        --keep-daily $KEEP_DAILY \
        --keep-weekly $KEEP_WEEKLY \
        --keep-monthly $KEEP_MONTHLY \
        --keep-yearly $KEEP_YEARLY
    fi

    if [[ "$BACKUP_VOLUMES" = "true" ]]; then
      info "Pruning $ARCHIVE_NAME volumes backups; maintaining $KEEP_DAILY daily, $KEEP_WEEKLY weekly, $KEEP_MONTHLY monthly, and $KEEP_YEARLY yearly backups"

      "$BORG" prune "${BORG_PRUNE[@]}" \
        --prefix "{hostname}-$ARCHIVE_NAME-volumes-" \
        --show-rc \
        --keep-daily $KEEP_DAILY \
        --keep-weekly $KEEP_WEEKLY \
        --keep-monthly $KEEP_MONTHLY \
        --keep-yearly $KEEP_YEARLY
    fi
  done 3< <(docker ps --format '{{.ID}}' "${FILTER_ARGS[@]}")
else
  info "Skipping docker..."
fi

unset BORG_REPO
unset BORG_RSH
unset BORG_PASSPHRASE

# ] <-- needed because of Argbash
