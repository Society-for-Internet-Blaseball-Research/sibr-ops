#!/bin/bash

export BORG_PASSPHRASE=''
export BORG_REPO=''
export BORG_RSH=''

# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$(date)" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

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

if [[ -z "${HOST// }" ]]; then
    echo "No host provided"
    exit 1
fi

if [[ -z "${CONTAINER_NAME// }" ]]; then
    echo "No container name provided"
    exit 1
fi

echo "Do you wish to restore the following containers? "

docker ps --filter "name=$CONTAINER_NAME"

select yn in "Yes" "No"; do
    case $yn in
        Yes ) break;;
        No ) exit;;
    esac
done


while read -r -u 3 CONTAINER_ID ; do
    STARTING_DIR=$(pwd)

    DOCKER_DATA=$(docker inspect $CONTAINER_ID | jq '.[]')
    DOCKER_NAME=$(echo $DOCKER_DATA | jq -r .Name | cut -c2-)

    ARCHIVE_NAME=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.name\"])
    DATABASE_TYPE=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.database\"])
    BACKUP_VOLUMES=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"dev.sibr.borg.volumes.backup\"])

    if [[ "$BACKUP_VOLUMES" = "true" ]]; then        
        #Step 0. Figure out our stack name -- com.docker.stack.namespace
        STACK_NAME=$(echo $DOCKER_DATA | jq -r .Config.Labels[\"com.docker.stack.namespace\"])

        echo "Restoring $DOCKER_NAME ($STACK_NAME) mounts"

        # Step 1. Get the Borg archive
        VOLUMES_ARCHIVE=$(borg list -P $HOST-$ARCHIVE_NAME-volumes --short --last 1)

        if [[ -n $VOLUMES_ARCHIVE ]]; then
            while read -r -u 4 MOUNT_DATA ; do
                MOUNT_SOURCE=$(echo $MOUNT_DATA | jq -r .Source)
                DIR=$(echo $MOUNT_SOURCE | rev | cut -d'/' -f2- | rev)  # Trim the file/dir name, in case we're dealing with a bind mount + file

                # Step 2. Navigate to the source
                cd $DIR

                # Step 3. Figure out the **common root** - stack names may change upon redeploy, so we shouldn't rely on them
                COMMON_ROOT=$(echo $MOUNT_SOURCE | sed -e "s|.*$$STACK_NAME||")

                borg extract --progress --list $BORG_ARCHIVE_NAME --strip-components $(echo $DIR | grep -o "/" | wc -l) "::$VOLUMES_ARCHIVE" "re:$(echo $COMMON_ROOT | cut -c2-)"

            done 4< <(echo $DOCKER_DATA | jq -c .Mounts[])
        else
            info "No volume archive found"
        fi
    fi

    if [[ -n $DATABASE_TYPE && "$DATABASE_TYPE" != "null" ]]; then
        BORG_USER=$(echo $DOCKER_DATA | jq -r '.Config.Env[]|select(startswith("BORG_USER"))' | grep -P "^BORG_USER=" | sed 's/[^=]*=//')
        BORG_PASS=$(echo $DOCKER_DATA | jq -r '.Config.Env[]|select(startswith("BORG_PASSWORD"))' | grep -P "^BORG_PASSWORD=" | sed 's/[^=]*=//')
        BORG_DB=$(echo $DOCKER_DATA | jq -r '.Config.Env[]|select(startswith("BORG_DB"))' | grep -P "^BORG_DB=" | sed 's/[^=]*=//')

        DATABASE_ARCHIVE=$(borg list -P $HOST-$ARCHIVE_NAME-$DATABASE_TYPE --short --last 1)
        if [[ -n $DATABASE_ARCHIVE ]]; then
            case $DATABASE_TYPE in
                postgres|postgresql|psql)
                    # Check if we have enough space to use a tmp file
                    DATABASE_ARCHIVE_SIZE=$(borg info --json ::$DATABASE_ARCHIVE | jq .archives[].stats.original_size)
                    FREE_SPACE=$(df -B1 -P $(echo $DOCKER_DATA | jq -r .GraphDriver.Data.MergedDir) | awk 'NR==2 {print $4}')

                    CREATE_TMP=0

                    if [[ $DATABASE_ARCHIVE_SIZE =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then 
                        TMP_AVAILABLE=$(( $FREE_SPACE - ($DATABASE_ARCHIVE_SIZE * 1.25) ))

                        if [[ $TMP_AVAILABLE -gt 10000000000 ]]; then
                            CREATE_TMP=1;
                        fi
                    fi

                    if [[ $CREATE_TMP -eq 1 ]]; then
                        info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME via pg_restore + tmpfile"

                        borg extract --stdout ::$DATABASE_ARCHIVE | docker exec -u 0 -i $CONTAINER_ID dd of=/tmp/pg_archive

                        docker exec -u 0 -e PGPASSWORD="$BORG_PASS" $CONTAINER_ID sh -c "pg_restore --username=$BORG_USER --dbname=$BORG_DB --clean --verbose --jobs=$(nproc --all) /tmp/pg_archive && rm /tmp/pg_archive"
                    else
                        info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME via pg_restore"

                        borg extract --stdout ::$DATABASE_ARCHIVE | docker exec -u 0 -i -e PGPASSWORD="$BORG_PASS" $CONTAINER_ID pg_restore --clean --verbose --username=$BORG_USER --dbname=$BORG_DB
                    fi
                ;;

                mariadb|mysql)
                    info "Starting restore of $ARCHIVE_NAME into $DOCKER_NAME via mysql"

                    borg extract --stdout ::$DATABASE_ARCHIVE | docker exec -u 0 $CONTAINER_ID mysql -u $BORG_USER --password=$BORG_PASS $BORG_DB
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
done 3< <(docker ps --format '{{.ID}}' --filter "name=$CONTAINER_NAME") # Alternatively, we could use  --filter "label=dev.sibr.borg.name=$CCONTAINER_NAME"

unset BORG_REPO
unset BORG_RSH
unset BORG_PASSPHRASE