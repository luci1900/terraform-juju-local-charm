#!/bin/sh
# Prints the application's charm revision, config values, and each resource's
# fingerprint and upload timestamp, as a flat JSON map of strings:
#   {"charm_rev":"<n>","config:<key>":"...","fingerprint:<name>":"...","timestamp:<name>":"..."}
# Requires jq.
set -eu
cat >/dev/null
rev=$(juju status "$2" -m "$1" --format=json |
	jq -c --arg app "$2" '{charm_rev: (.applications[$app]["charm-rev"] | tostring)}')
# For a charm without resources this prints a message instead of JSON.
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
	jq -c '[.settings // {} | to_entries[] | {key: ("config:" + .key), value: (.value.value // "" | tostring)}] | from_entries')
jq -nc --argjson a "$rev" --argjson b "$res" --argjson c "$cfg" '$a + $b + $c'
