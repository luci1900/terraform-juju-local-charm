#!/bin/sh
# Prints charm revision, config, and resource fingerprints and timestamps:
#   {"charm_rev":"<n>","config:<key>":"...","fingerprint:<name>":"...","timestamp:<name>":"..."}
# Requires jq.
set -eu
cat >/dev/null
rev=$(juju status "$2" -m "$1" --format=json |
	jq -c --arg app "$2" '{charm_rev: (.applications[$app]["charm-rev"] | tostring)}')
# Prints a message instead of JSON when there are no resources.
res_json=$(juju resources "$2" -m "$1" --format=json 2>/dev/null)
case "$res_json" in
"{"*) ;;
*) res_json='{}' ;;
esac
res=$(echo "$res_json" |
	jq -c '[.resources // [] | .[] |
		{key: ("fingerprint:" + .name), value: .fingerprint},
		{key: ("timestamp:" + .name), value: .timestamp}] | from_entries')
cfg=$(juju config "$2" -m "$1" --format=json |
	jq -c '[(.settings // {}) + (."application-config" // {}) | to_entries[] | {key: ("config:" + .key), value: (.value.value | if . == null then "" else tostring end)}] | from_entries')
jq -nc --argjson a "$rev" --argjson b "$res" --argjson c "$cfg" '$a + $b + $c'
