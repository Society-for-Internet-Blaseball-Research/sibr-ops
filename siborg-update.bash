#!/usr/bin/env bash

OPS_DIR='/usr/local/bin'
COMPLETION_DIR='/etc/bash_completion.d'

mkdir -p "$OPS_DIR"
mkdir -p "$COMPLETION_DIR"

rm -rf sibr-ops
git clone https://github.com/Society-for-Internet-Blaseball-Research/sibr-ops.git
cd sibr-ops || exit
cp siborg-update.bash "$OPS_DIR/siborg-update"

BORG_REPO="$1"
BORG_PASSPHRASE="$2"
BORG_RSH="$3"

for i in *.m4; do
    [ -f "$i" ] || break

    OUTPUT="$OPS_DIR/siborg-${i%.m4}"

    argbash "$i" -o "$OUTPUT"
    argbash "$i" --type completion --strip all -o "$COMPLETION_DIR/siborg-${i%.m4}.sh"

    PATTERN="$BORG_REPO" perl -pi.bak -e "s/%BORG_REPO%/\$ENV{PATTERN}/" "$OUTPUT"
    PATTERN="$BORG_PASSPHRASE" perl -pi.bak -e "s/%BORG_PASSPHRASE%/\$ENV{PATTERN}/" "$OUTPUT"
    PATTERN="$BORG_RSH" perl -pi.bak -e "s/%BORG_RSH%/\$ENV{PATTERN}/" "$OUTPUT"

    chmod 700 "$OUTPUT"
done

for i in *.bash; do
    [ -f "$i" ] || break

    OUTPUT="$OPS_DIR/${i%.bash}"

    cp "$i" "$OUTPUT"

    chmod 700 "$OUTPUT"
done

cd .. || exit
rm -rf sibr-ops