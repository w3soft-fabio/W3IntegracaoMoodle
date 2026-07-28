#!/usr/bin/env bash

set -u

command_name="${1:-}"
shift || true

case "$command_name" in
  ps)
    printf '%s\n' ${FAKE_DOCKER_CONTAINERS:-}
    ;;
  inspect)
    if [[ "$*" == *".State.Running"* ]]; then
      printf '%s\n' true
    elif [[ "$*" == *".Config.Labels"* ]]; then
      printf '%s\n' tenant
    else
      exit 1
    fi
    ;;
  exec)
    exit "${FAKE_DOCKER_EXEC_STATUS:-0}"
    ;;
  *)
    exit 1
    ;;
esac
