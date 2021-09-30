#!/bin/bash
#
# m4_ignore(
echo "WARNING - This is just a script template, not the script (yet) - pass it to 'argbash' to fix this." >&2
exit 11  
#)
# ARG_OPTIONAL_SINGLE(host,H,[Override the default host for this script])
# ARG_OPTIONAL_SINGLE(container,,[Filter containers to restore])
# ARG_OPTIONAL_SINGLE(force-type,,[Force database to restore via a certain method (Unstable!)])
# ARG_OPTIONAL_BOOLEAN(dry-run,n,[Simulate operations without any output])
# ARG_OPTIONAL_BOOLEAN(progress,P,[Show progress bar])
# ARG_OPTIONAL_BOOLEAN(list,,[List contents when restoring])
# ARG_OPTIONAL_BOOLEAN(stats,s,[Show stats from Borg])
# ARG_OPTIONAL_BOOLEAN(clean-databases,,[Clean the database prior to restoration])
# ARG_OPTIONAL_BOOLEAN(skip-mounts,,[Skip mount restoration])
# ARG_OPTIONAL_BOOLEAN(skip-databases,,[Skip database restoration])
# ARG_OPTIONAL_BOOLEAN(accept,Y,[Accept containers to restore without input])
# ARG_OPTIONAL_BOOLEAN(wait-for-lock,,[If a lock is present, wait for other process to shut down])
# ARG_OPTIONAL_BOOLEAN(break-lock,,[If a lock is present, break it regardless of if the other process is active])
# ARG_OPTIONAL_BOOLEAN(force-tmp,,[Force database restoration to use a temporary file])
# ARG_OPTIONAL_BOOLEAN(skip-tmp,,[Force database restoration to skip using a temporary file])
# ARG_OPTIONAL_BOOLEAN(keep-tmp,,[Keep the temporary file after restoring from it])
# ARG_OPTIONAL_SINGLE(borg-repo,,[Override the default borg repository])
# ARG_OPTIONAL_SINGLE(borg-pass,,[Override the default borg passphrase])
# ARG_OPTIONAL_SINGLE(borg-rsh,,[Override the default borg remote shell command])
# ARG_HELP([Restore a volume and/or database from a borg backup])
# ARG_USE_PROGRAM([borg], [BORG], [Borg needs to be installed!],[Borg program location])
# ARG_USE_PROGRAM([docker], [DOCKER], [Docker needs to be installed!], [Docker program location])
# ARG_USE_PROGRAM([jq], [JQ], [jq needs to be installed!], [jq program location])
# ARGBASH_GO

# [ <-- needed because of Argbash

LOCKFILE="/tmp/dev.sibr.borg.lock"

if [[ -f $LOCKFILE ]]; then
    if [[ "$arg_break_lock" = "on" ]]; then
        echo "Breaking lockfile"
        rm $LOCKFILE
    else
        PID=$(cat $LOCKFILE)
        if [[ -f "/proc/$PID/stat" ]]; then
            if [[ $_arg_wait_for_lock = "off" ]]; then
                echo "Borg is currently in use, waiting on $PID"
                exit 1
            fi

            wait $PID
        fi

        echo "Breaking stale lockfile"
        rm $LOCKFILE
    fi
fi

echo $$ > $LOCKFILE

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
test "${_arg_borg_repo// }" && BORG_REPO="$_arg_borg_repo"
test "${_arg_borg_pass// }" && BORG_PASSPHRASE="$_arg_borg_pass"
test "${_arg_borg_rsh// }" && BORG_RSH="$_arg_borg_rsh"
HOST="${_arg_host:-$(hostname)}"
CONTAINER_NAME="$_arg_container"
FORCED_TYPE="$_arg_force_type"

COMPRESSION_LEVEL="$_arg_compression"
RCLONE_ACCOUNT="$_arg_rclone_account"
RCLONE_BUCKET="$_arg_rclone_bucket"

VERBOSE=$_arg_verbose
DRY_RUN=0
SKIP_MOUNTS=0
SKIP_DATABASES=0
KEEP_TMP=0

if [[ "$_arg_dry_run" = "on" ]]; then
    DRY_RUN=1
fi

if [[ "$_arg_skip_mounts" = "on" ]]; then
    SKIP_MOUNTS=1
fi

if [[ "$_arg_skip_databases" = "on" ]]; then
    SKIP_DATABASES=1
fi

if [[ "$_arg_keep_tmp" = "on" ]]; then
    KEEP_TMP=1
fi

FILTER_ARGS=("--filter" "label=dev.sibr.borg.name")
if [[ -n "$_arg_container" ]]; then
    FILTER_ARGS+=("--filter" "name=$_arg_container")
fi

if [[ -n "$_arg_database_type" ]]; then
    FILTER_ARGS+=("--filter" "label=dev.sibr.borg.database=$_arg_database_type")
fi

"$DOCKER" ps "${FILTER_ARGS[@]}"

if [[ "$_arg_accept" = "off" ]]; then
    echo "Do you wish to restore these containers?"

    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No ) exit;;
        esac
    done
fi

BORG_EXTRACT=()
DOCKER_EXEC=()
PG_RESTORE=()
MYSQL=()

if [[ $VERBOSE -eq 1 ]]; then
    BORG_EXTRACT+=("--verbose")
    PG_RESTORE+=("--verbose")
fi

if [[ $DRY_RUN -eq 1 ]]; then
    BORG_EXTRACT+=("--dry-run")
fi

if [[ "$_arg_progress" = "on" ]]; then
    BORG_EXTRACT+=("--progress")
fi

if [[ "$_arg_list" = "on" ]]; then
    BORG_EXTRACT+=("--list")
    # PG_RESTORE+=("--list")
fi

# if [[ "$_arg_stats" = "on" ]]; then
#     BORG_EXTRACT+=("--stats")
# fi

if [[ "$_arg_clean_databases" = "on" ]]; then
    PG_RESTORE+=("--clean")
fi


docker_env() {
    printf -v JQ_FILTER '.Config.Env[]|select(startswith("%q"))' "$1"
    echo "$DOCKER_DATA" | "$JQ" -r $JQ_FILTER | grep -P "^$1=" | sed 's/[^=]*=//'
}

docker_label() {
    printf -v JQ_FILTER '.Config.Labels["%q"]' "$1"
    echo "$DOCKER_DATA" | "$JQ" -r $JQ_FILTER
}

docker_mount() {
    printf -v JQ_FILTER '.Mounts[]|select(.Destination|startswith("%q")).Source' "$1"
    echo "$DOCKER_DATA" | "$JQ" -r $JQ_FILTER
}

get_dependents() {
    while read -r -u 10 DEP_CONTAINER_ID ; do
        local NAME=$("$DOCKER" inspect $DEP_CONTAINER_ID | "$JQ" -r '.[].Config.Labels["dev.sibr.borg.name"]')

        DEPENDENT_CONTAINERS+=("$DEP_CONTAINER_ID")
        if [[ -n $NAME && "$NAME" != "null" ]]; then
            get_dependents "$NAME"
        fi
    done 10< <("$DOCKER" ps --format '{{.ID}}' --filter "label=dev.sibr.borg.depends_on=$1")
}

suspend_dependents() {
    if [[ ${#DEPENDENT_CONTAINERS[@]} -gt 0 ]]; then
        info "Suspending dependent containers"
        "$DOCKER" pause "${DEPENDENT_CONTAINERS[@]}"
    fi
}

resume_dependents() {
    if [[ ${#DEPENDENT_CONTAINERS[@]} -gt 0 ]]; then
        info "Resuming dependent containers"
        "$DOCKER" unpause "${DEPENDENT_CONTAINERS[@]}"
    fi
}

while read -r -u 3 CONTAINER_ID ; do
    STARTING_DIR=$(pwd)

    DOCKER_DATA=$("$DOCKER" inspect $CONTAINER_ID | "$JQ" '.[]')
    DOCKER_NAME=$(echo $DOCKER_DATA | "$JQ" -r .Name | cut -c2-)

    ARCHIVE_NAME=$(docker_label 'dev.sibr.borg.name')
    DATABASE_TYPE=$(docker_label 'dev.sibr.borg.database')
    BACKUP_VOLUMES=$(docker_label 'dev.sibr.borg.volumes.backup')

    # Get containers that are dependent on this one

    DEPENDENT_CONTAINERS=()
    get_dependents $ARCHIVE_NAME

    suspend_dependents
    trap resume_dependents EXIT

    if [[ "$BACKUP_VOLUMES" = "true" && $SKIP_MOUNTS -eq 0 ]]; then
        #Step 0. Figure out our stack name -- com.docker.stack.namespace
        STACK_NAME=$(docker_label 'com.docker.stack.namespace')

        echo "Restoring $DOCKER_NAME ($STACK_NAME) mounts"

        # Step 1. Get the Borg archive
        VOLUMES_ARCHIVE=$("$BORG" list -P $HOST-$ARCHIVE_NAME-volumes --short --last 1)

        if [[ -n $VOLUMES_ARCHIVE ]]; then
            while read -r -u 4 MOUNT_DATA ; do
                MOUNT_SOURCE=$(echo $MOUNT_DATA | "$JQ" -r .Source)
                DIR=$(echo $MOUNT_SOURCE | rev | cut -d'/' -f2- | rev)  # Trim the file/dir name, in case we're dealing with a bind mount + file

                # Step 2. Navigate to the source
                cd $DIR

                # Step 3. Figure out the **common root** - stack names may change upon redeploy, so we shouldn't rely on them
                COMMON_ROOT=$(echo $MOUNT_SOURCE | sed -e "s|.*$$STACK_NAME||")

                "$BORG" extract "${BORG_EXTRACT[@]}" --strip-components $(echo $DIR | grep -o "/" | wc -l) "::$VOLUMES_ARCHIVE" "re:$(echo $COMMON_ROOT | cut -c2-)"
            done 4< <(echo $DOCKER_DATA | "$JQ" -c .Mounts[])
        else
            info "No volume archive found"
        fi
    fi

    if [[ -n $DATABASE_TYPE && "$DATABASE_TYPE" != "null" && $SKIP_DATABASES -eq 0 ]]; then
        BORG_USER=$(docker_env 'BORG_USER')
        BORG_PASS=$(docker_env 'BORG_PASSWORD')
        BORG_DB=$(docker_env 'BORG_DB')

        RESTORE_TYPE="$DATABASE_TYPE"

        if [[ -n "$FORCED_TYPE" ]]; then
            if [[ "$_arg_accept" = "off" ]]; then
                echo "Are you SURE you wish to restore this database with a different database type (Expecting $DATABASE_TYPE, told $FORCED_TYPE)?"

                select yn in "Yes" "No" "Exit"; do
                    case $yn in
                        Yes ) 
                            RESTORE_TYPE="$FORCED_TYPE"
                            break
                            ;;
                        No ) 
                            break
                            ;;

                        Exit )
                            exit
                            ;;
                    esac
                done
            else
                echo "Restoring with $FORCED_TYPE rather than $DATABASE_TYPE"
                RESTORE_TYPE="$FORCED_TYPE"
            fi

        fi

        DATABASE_ARCHIVE=$("$BORG" list -P "$HOST-$ARCHIVE_NAME-$RESTORE_TYPE" --short --last 1)
        if [[ -n $DATABASE_ARCHIVE ]]; then
            case $RESTORE_TYPE in
                postgres|postgresql|psql)
                    # Check if we have enough space to use a tmp file
                    DATABASE_ARCHIVE_SIZE=$("$BORG" info --json ::$DATABASE_ARCHIVE | "$JQ" .archives[].stats.original_size)
                    FREE_SPACE=$(df -B1 -P $(echo $DOCKER_DATA | "$JQ" -r .GraphDriver.Data.MergedDir) | awk 'NR==2 {print $4}')

                    ARCHIVE_DIR="/tmp/sibr"
                    ARCHIVE_LOCATION="$ARCHIVE_DIR/stdin"

                    TMP_SIZE=$("$DOCKER" exec -u 0 "$CONTAINER_ID" du -bP "$ARCHIVE_LOCATION" | cut -f1)
                    TMP_EXISTS=0
                    if [[ $TMP_SIZE =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
                        if [[ $TMP_SIZE -ge $DATABASE_ARCHIVE_SIZE ]]; then
                            TMP_EXISTS=1
                        fi
                    fi

                    CREATE_TMP=0

                    if [[ "$_arg_force_tmp" = "on" ]]; then
                        CREATE_TMP=1
                    elif [[ "$_arg_skip_tmp" = "off" && $TMP_EXISTS -eq 0 && $DATABASE_ARCHIVE_SIZE =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then 
                        TMP_AVAILABLE=$(( $FREE_SPACE - $DATABASE_ARCHIVE_SIZE - ($DATABASE_ARCHIVE_SIZE / 2) )) #Bash doesn't support floating point maths

                        if [[ $TMP_AVAILABLE -gt 10000000000 ]]; then
                            CREATE_TMP=1;
                        fi
                    fi

                    if [[ $CREATE_TMP -eq 1 || $TMP_EXISTS -eq 1 ]]; then
                        info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME ($CONTAINER_ID) via pg_restore + $ARCHIVE_LOCATION"

                        "$DOCKER" exec -u 0 "$CONTAINER_ID" mkdir -p "$ARCHIVE_DIR"

                        if [[ $TMP_EXISTS -eq 0 ]]; then
                            # few ways of extracting out a file -
                            # 1. Use a pipe to extract from borg to stdout, then into docker dd
                            # This is ~170 MB/s
                            # "$BORG" extract --stdout "${BORG_EXTRACT[@]}" ::$DATABASE_ARCHIVE | "$DOCKER" exec -u 0 -i "$CONTAINER_ID" dd "of=$ARCHIVE_LOCATION"
                            # 2. Use a pipe to extract a tar from borg to stdout, pass to docker cp
                            # This is ~310 MB/s
                            # "$BORG" export-tar "::$DATABASE_ARCHIVE" - | pv -s $DATABASE_ARCHIVE_SIZE | "$DOCKER" cp - $CONTAINER_ID:$ARCHIVE_DIR"
                            # 3. Extract to tmp folder in docker directly (Not the ~best~ idea, but should work)
                            # This is slightly slower than the above, from the looks of it
                            # cd "$(echo $DOCKER_DATA | "$JQ" -r .GraphDriver.Data.MergedDir)$ARCHIVE_DIR" && "$BORG" extract "::$DATABASE_ARCHIVE" --progress

                            if command -v pv &> /dev/null
                            then
                                "$BORG" export-tar "::$DATABASE_ARCHIVE" - | pv -s $DATABASE_ARCHIVE_SIZE | "$DOCKER" cp - "$CONTAINER_ID:$ARCHIVE_DIR"
                            else
                                "$BORG" export-tar "::$DATABASE_ARCHIVE" - | "$DOCKER" cp - "$CONTAINER_ID:$ARCHIVE_DIR"
                            fi


                            # "$BORG" extract --stdout "${BORG_EXTRACT[@]}" ::$DATABASE_ARCHIVE | "$DOCKER" exec -u 0 -i "$CONTAINER_ID" dd "of=$ARCHIVE_LOCATION"
                        fi
                        
                        # https://stackoverflow.com/a/34271562
                        printf -v PG_RESTORE_ARGS '%q ' "${PG_RESTORE[@]}"

                        "$DOCKER" exec -u 0 -e PGPASSWORD="$BORG_PASS" "$CONTAINER_ID" pg_restore "--username=$BORG_USER" "--dbname=$BORG_DB" "${PG_RESTORE[@]}" --jobs=$(nproc --all) "$ARCHIVE_LOCATION"

                        sleep 5

                        if [[ $KEEP_TMP -eq 0 ]]; then
                            "$DOCKER" exec -u 0 "$CONTAINER_ID" rm "$ARCHIVE_LOCATION"
                        elif [[ -z $("$DOCKER" ps --filter "id=$CONTAINER_ID" --format '{{.ID}}') ]]; then
                            info "Removing tmp file as container has been shut down"

                            # We have to use a manual dir remove since the container is down

                            rm "$(echo $DOCKER_DATA | "$JQ" -r .GraphDriver.Data.MergedDir)$ARCHIVE_LOCATION"
                        fi
                    else
                        info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME via pg_restore"

                        # https://stackoverflow.com/a/34271562
                        printf -v PG_RESTORE_ARGS '%q ' "${PG_RESTORE[@]}"

                        "$BORG" extract --stdout "${BORG_EXTRACT[@]}" ::$DATABASE_ARCHIVE | "$DOCKER" exec -u 0 -i -e PGPASSWORD="$BORG_PASS" $CONTAINER_ID pg_restore "${PG_RESTORE[@]}" --username="$BORG_USER" --dbname="$BORG_DB"
                    fi
                ;;

                pgbackrest|backrest)
                    # This is the most complicated of our restore options --

                    BACKREST_STANZA=$(docker_env 'BACKREST_STANZA')
                    BACKREST_DIR=$(docker_env 'PGBACKREST_DIR')
                    BACKREST_MOUNT=$(docker_mount "$BACKREST_DIR")

                    if [[ -n "$BACKREST_STANZA" && -n "$BACKREST_MOUNT" ]]; then
                        PGBACKREST_LOCK="/tmp/dev.sibr.docker.lock"

                        info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME via pgBackRest"

                        # First up, we need to create a lock file in our container, and stop the psql instance
                        "$DOCKER" exec -u 999 $CONTAINER_ID sh -c "touch $PGBACKREST_LOCK && pg_ctl stop"

                        # Then, we need to extract our archive into BACKREST_MOUNT
                        DIR=$(echo $BACKREST_MOUNT | rev | cut -d'/' -f2- | rev)  # Trim the file/dir name, in case we're dealing with a bind mount + file

                        # Step 2. Navigate to the source
                        cd $DIR

                        # Step 3. Figure out the **common root** - stack names may change upon redeploy, so we shouldn't rely on them
                        COMMON_ROOT=$(echo $BACKREST_MOUNT | sed -e "s|.*$$STACK_NAME||")

                        "$BORG" extract "${BORG_EXTRACT[@]}" --strip-components $(echo $DIR | grep -o "/" | wc -l) "::$DATABASE_ARCHIVE"
                        # Then, we need to proc a restore

                        # "${PGBACKREST_RESTORE[@]}"
                        "$DOCKER" exec -u 999 $CONTAINER_ID pgbackrest "--stanza=$BACKREST_STANZA" --delta --log-level-console=detail restore

                        # Then, delete the lock file, and allow the container to restart

                        "$DOCKER" exec -u 999 $CONTAINER_ID rm "$PGBACKREST_LOCK"
                    else
                        info "Failed to backup $DOCKER_NAME - missing BACKREST_STANZA / PGBACKREST_DIR"
                    fi
                ;;

                mariadb|mysql)
                    info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME via mysql"

                   "$BORG" extract --stdout "${BORG_EXTRACT[@]}" ::$DATABASE_ARCHIVE | "$DOCKER" exec -i -u 0 $CONTAINER_ID mysql "${MYSQL[@]}" -u $BORG_USER --password=$BORG_PASS $BORG_DB
                ;;

                *)
                    info "Failing to restore $ARCHIVE_NAME into $DOCKER_NAME - unknown database type $RESTORE_TYPE"
                ;;

            esac
        else
            info "No database archive found"
        fi
    fi

    resume_dependents
    trap - EXIT

    cd $STARTING_DIR
done 3< <("$DOCKER" ps --format '{{.ID}}' "${FILTER_ARGS[@]}")

unset BORG_REPO
unset BORG_RSH
unset BORG_PASSPHRASE

rm $LOCKFILE

# ] <-- needed because of Argbash