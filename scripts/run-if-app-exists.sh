#!/bin/sh
# Runs the command only if the application exists, so destroy doesn't fail
# when it was removed outside Terraform.
#
# Usage: run-if-app-exists.sh <command> [args...]
# Reads JUJU, MODEL and APP from the environment.
set -eu

e=$(sh "$(dirname "$0")/app-exists.sh" "$JUJU" "$MODEL" "$APP" </dev/null)
[ "$e" = '{"exists":"false"}' ] && exit 0
exec "$@"
