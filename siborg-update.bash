#!/usr/bin/env bash

OPS_DIR='/usr/local/bin'
COMPLETION_DIR='/etc/bash_completion.d'

mkdir -p "$OPS_DIR"
mkdir -p "$COMPLETION_DIR"

rm -rf sibr-ops
git clone https://github.com/Society-for-Internet-Blaseball-Research/sibr-ops.git
cd sibr-ops || exit
cp update-borg-scripts.bash "$OPS_DIR/update-borg-scripts"

BORG_REPO="$1"
BORG_PASSPHRASE="$2"
BORG_RSH="$3"

for i in *.m4; do
    [ -f "$i" ] || break

    OUTPUT="$OPS_DIR/siborg-${i%.m4}"

    argbash "$i" -o "$OUTPUT"
    argbash "$i" --type completion --strip all -o "$COMPLETION_DIR/siborg-${i%.m4}.sh"

    PATTERN="$BORG_REPO" perl -pi.bak -e "s/%BORG_REPO%/\$ENV{PATTERN}/" "$OUTPUT_FILE"
    PATTERN="$BORG_PASSPHRASE" perl -pi.bak -e "s/%BORG_PASSPHRASE%/\$ENV{PATTERN}/" "$OUTPUT_FILE"
    PATTERN="$BORG_RSH" perl -pi.bak -e "s/%BORG_RSH%/\$ENV{PATTERN}/" "$OUTPUT_FILE"
done

for i in *.bash; do
    [ -f "$i" ] || break

    cp "$i" "$OPS_DIR/${i%.bash}"
done

rm -rf sibr-ops