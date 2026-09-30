#!/bin/sh
# Removes the application, if it still exists, and waits until it's gone.
# remove-application returns early, so like the provider this waits for
# "not found", retrying any other error.
#
# Usage: remove-app.sh
# Reads JUJU, MODEL, APP, WAIT (true or false) and REMOVAL_TIMEOUT (seconds)
# from the environment.
set -eu

here=$(dirname "$0")
sh "$here/run-if-app-exists.sh" "$JUJU" remove-application "$APP" -m "$MODEL" --no-prompt
[ "$WAIT" = true ] || exit 0

deadline=$(($(date +%s) + REMOVAL_TIMEOUT))
while [ "$(date +%s)" -lt "$deadline" ]; do
	e=$(sh "$here/app-exists.sh" "$JUJU" "$MODEL" "$APP" </dev/null 2>/dev/null) || e=
	[ "$e" = '{"exists":"false"}' ] && exit 0
	sleep 2
done
echo "Unable to complete application \"$APP\" deletion: timed out after ${REMOVAL_TIMEOUT}s" >&2
exit 1
