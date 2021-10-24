#!/usr/bin/env bash

export BORG_REPO
export BORG_PASSPHRASE
export BORG_RSH

# If no envvar is provided, we should provide our default
test -z "${BORG_REPO// /}" && BORG_REPO='%BORG_REPO%'
test -z "${BORG_PASSPHRASE// /}" && BORG_PASSPHRASE='%BORG_PASSPHRASE%'
test -z "${BORG_RSH// /}" && BORG_RSH='%BORG_RSH%'

borg "$@"

unset BORG_REPO
unset BORG_RSH
unset BORG_PASSPHRASE