#!/usr/bin/env bash

BORG_FUNC="$1"
shift

case $BORG_FUNC in

help)
  cat <<EOF
Usage:
  siborg <command> [flags]
  siborg swarm <command> [flags]

Required arguments:
  <command>
    help - show this message
    update
    backup
    restore
EOF
  ;;

update) siborg-update "$@" ;;

backup) siborg-backup-containers "$@" ;;
restore) siborg-restore-containers "$@" ;;

swarm)
  BORG_FUNC="$1"
  shift

  case $BORG_FUNC in
  backup) siborg-backup-swarm "$@" ;;
  restore) siborg-restore-swarm "$@" ;;
  *) echo "Unknown swarm command $BORG_FUNC" ;;
  esac

  ;;

*)
  echo "Unknown command $BORG_FUNC"
  ;;

esac
