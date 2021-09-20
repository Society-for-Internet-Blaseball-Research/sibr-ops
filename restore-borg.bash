#!/bin/bash
#
# m4_ignore(
echo "WARNING - This is just a script template, not the script (yet) - pass it to 'argbash' to fix this." >&2
exit 11  
#)
# ARG_OPTIONAL_SINGLE(host,H,[Override the default host for this script])
# ARG_OPTIONAL_SINGLE(container,,[Filter containers to restore])
# ARG_OPTIONAL_BOOLEAN(dry-run,n,[Simulate operations without any output])
# ARG_OPTIONAL_BOOLEAN(progress,P,[Show progress bar])
# ARG_OPTIONAL_BOOLEAN(list,,[List contents when restoring])
# ARG_OPTIONAL_BOOLEAN(stats,s,[Show stats from Borg])
# ARG_OPTIONAL_BOOLEAN(clean-databases,,[Clean the database prior to restoration])
# ARG_OPTIONAL_BOOLEAN(skip-mounts,,[Skip mount restoration])
# ARG_OPTIONAL_BOOLEAN(skip-databases,,[Skip database restoration])
# ARG_OPTIONAL_BOOLEAN(accept,Y,[Accept containers to restore without input])
# ARG_OPTIONAL_SINGLE(borg-repo,,[Override the default borg repository])
# ARG_OPTIONAL_SINGLE(borg-pass,,[Override the default borg passphrase])
# ARG_OPTIONAL_SINGLE(borg-rsh,,[Override the default borg remote shell command])
# ARG_HELP([Restore a volume and/or database from a borg backup])
# ARG_USE_PROGRAM([borg], [BORG], [Borg needs to be installed!],[Borg program location])
# ARG_USE_PROGRAM([docker], [DOCKER], [Docker needs to be installed!], [Docker program location])
# ARG_USE_PROGRAM([jq], [JQ], [jq needs to be installed!], [jq program location])
# ARGBASH_GO

# [ <-- needed because of Argbash

export BORG_REPO
export BORG_PASSPHRASE
export BORG_RSH

# If no envvar is provided, we should provide our default
test -z "${BORG_REPO// }" && BORG_REPO="%BORG_REPO%"
test -z "${BORG_PASSPHRASE// }" && BORG_PASSPHRASE="%BORG_PASSPHRASE%"
test -z "${BORG_RSH// }" && BORG_RSH="%BORG_RSH%"

# If argument is present, override the environmental variable, even if it is present
test "${_arg_borg_repo// }" && BORG_REPO="$_arg_borg_repo"
test "${_arg_borg_pass// }" && BORG_PASSPHRASE="$_arg_borg_pass"
test "${_arg_borg_rsh// }" && BORG_RSH="$_arg_borg_rsh"
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
SKIP_MOUNTS=0
SKIP_DATABASES=0

if [[ "$_arg_dry_run" = "on" ]]; then
    DRY_RUN=1
fi

if [[ "$_arg_skip_mounts" = "on" ]]; then
    SKIP_MOUNTS=1
fi

if [[ "$_arg_skip_databases" = "on" ]]; then
    SKIP_DATABASES=1
fi

"$DOCKER" ps  --filter "label=dev.sibr.borg.name" --filter "name=$CONTAINER_NAME"

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
    PG_RESTORE+=("--list")
fi

if [[ "$_arg_stats" = "on" ]]; then
    BORG_EXTRACT+=("--stats")
fi

if [[ "$_arg_clean_databases" = "on" ]]; then
    PG_RESTORE+=("--clean")
fi


while read -r -u 3 CONTAINER_ID ; do
    STARTING_DIR=$(pwd)

    DOCKER_DATA=$("$DOCKER" inspect $CONTAINER_ID | "$JQ" '.[]')
    DOCKER_NAME=$(echo $DOCKER_DATA | "$JQ" -r .Name | cut -c2-)

    ARCHIVE_NAME=$(echo $DOCKER_DATA | "$JQ" -r .Config.Labels[\"dev.sibr.borg.name\"])
    DATABASE_TYPE=$(echo $DOCKER_DATA | "$JQ" -r .Config.Labels[\"dev.sibr.borg.database\"])
    BACKUP_VOLUMES=$(echo $DOCKER_DATA | "$JQ" -r .Config.Labels[\"dev.sibr.borg.volumes.backup\"])

    if [[ "$BACKUP_VOLUMES" = "true" && $SKIP_MOUNTS -eq 0 ]]; then        
        #Step 0. Figure out our stack name -- com.docker.stack.namespace
        STACK_NAME=$(echo $DOCKER_DATA | "$JQ" -r .Config.Labels[\"com.docker.stack.namespace\"])

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

                "$BORG" extract "${BORG_EXTRACT[@]}" $BORG_ARCHIVE_NAME --strip-components $(echo $DIR | grep -o "/" | wc -l) "::$VOLUMES_ARCHIVE" "re:$(echo $COMMON_ROOT | cut -c2-)"

            done 4< <(echo $DOCKER_DATA | "$JQ" -c .Mounts[])
        else
            info "No volume archive found"
        fi
    fi

    if [[ -n $DATABASE_TYPE && "$DATABASE_TYPE" != "null" && $SKIP_DATABASES -eq 0 ]]; then
        BORG_USER=$(echo $DOCKER_DATA | "$JQ" -r '.Config.Env[]|select(startswith("BORG_USER"))' | grep -P "^BORG_USER=" | sed 's/[^=]*=//')
        BORG_PASS=$(echo $DOCKER_DATA | "$JQ" -r '.Config.Env[]|select(startswith("BORG_PASSWORD"))' | grep -P "^BORG_PASSWORD=" | sed 's/[^=]*=//')
        BORG_DB=$(echo $DOCKER_DATA | "$JQ" -r '.Config.Env[]|select(startswith("BORG_DB"))' | grep -P "^BORG_DB=" | sed 's/[^=]*=//')

        DATABASE_ARCHIVE=$("$BORG" list -P $HOST-$ARCHIVE_NAME-$DATABASE_TYPE --short --last 1)
        if [[ -n $DATABASE_ARCHIVE ]]; then
            case $DATABASE_TYPE in
                postgres|postgresql|psql)
                    # Check if we have enough space to use a tmp file
                    DATABASE_ARCHIVE_SIZE=$("$BORG" info --json ::$DATABASE_ARCHIVE | "$JQ" .archives[].stats.original_size)
                    FREE_SPACE=$(df -B1 -P $(echo $DOCKER_DATA | "$JQ" -r .GraphDriver.Data.MergedDir) | awk 'NR==2 {print $4}')

                    CREATE_TMP=0

                    if [[ $DATABASE_ARCHIVE_SIZE =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then 
                        TMP_AVAILABLE=$(( $FREE_SPACE - ($DATABASE_ARCHIVE_SIZE * 1.25) ))

                        if [[ $TMP_AVAILABLE -gt 10000000000 ]]; then
                            CREATE_TMP=1;
                        fi
                    fi

                    if [[ $CREATE_TMP -eq 1 ]]; then
                        info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME via pg_restore + tmpfile"

                        "$BORG" extract --stdout "${BORG_EXTRACT[@]}" ::$DATABASE_ARCHIVE | "$DOCKER" exec -u 0 -i $CONTAINER_ID dd of=/tmp/pg_archive

                        "$DOCKER" exec -u 0 -e PGPASSWORD="$BORG_PASS" $CONTAINER_ID pg_restore --username=$BORG_USER --dbname=$BORG_DB "${PG_RESTORE[@]}" --jobs=$(nproc --all) /tmp/pg_archive
                        "$DOCKER" exec -u 0 rm /tmp/pg_archive
                    else
                        info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME via pg_restore"

                        "$BORG" extract --stdout "${BORG_EXTRACT[@]}" ::$DATABASE_ARCHIVE | "$DOCKER" exec -u 0 -i -e PGPASSWORD="$BORG_PASS" $CONTAINER_ID pg_restore "${PG_RESTORE[@]}" --username=$BORG_USER --dbname=$BORG_DB
                    fi
                ;;

                mariadb|mysql)
                    info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME via mysql"

                   "$BORG" extract --stdout "${BORG_EXTRACT[@]}" ::$DATABASE_ARCHIVE | "$DOCKER" exec -u 0 $CONTAINER_ID mysql "${MYSQL[@]}" -u $BORG_USER --password=$BORG_PASS $BORG_DB
                ;;

                *)
                    info "Failing to restore $ARCHIVE_NAME into $DOCKER_NAME - unknown database type $DATABASE_TYPE"
                ;;

            esac
        else
            info "No database archive found"
        fi
    fi

    cd $STARTING_DIR
done 3< <("$DOCKER" ps --format '{{.ID}}' --filter "label=dev.sibr.borg.name" --filter "name=$CONTAINER_NAME") # Alternatively, we could use  --filter "label=dev.sibr.borg.name=$CCONTAINER_NAME"

unset BORG_REPO
unset BORG_RSH
unset BORG_PASSPHRASE

# ] <-- needed because of Argbash