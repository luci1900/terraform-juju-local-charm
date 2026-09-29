#!/bin/sh
# External data source program: prints {"exists":"true"|"false"} for an
# application. Any failure other than "application not found" is an error,
# so a transient problem never looks like a missing application.
#
# Usage: app-exists.sh <juju-binary> <model-uuid> <app-name>
set -u

juju="$1"
model="$2"
app="$3"

# The external data source writes its query to stdin. It isn't used.
cat >/dev/null

if out=$("$juju" show-application "$app" -m "$model" --format=json 2>&1); then
	echo '{"exists":"true"}'
	exit 0
fi

case "$out" in
*"application \"$app\" not found"* | *"application $app not found"*)
	echo '{"exists":"false"}'
	exit 0
	;;
*"model"*"not found"*)
	controller=$("$juju" switch 2>/dev/null | cut -d: -f1)
	echo "$out" >&2
	echo "Model $model was not found on controller \"$controller\" (the juju CLI's current controller)." >&2
	echo "If the juju provider is configured for a different controller, run: juju switch <controller>" >&2
	exit 1
	;;
esac

echo "$out" >&2
exit 1
