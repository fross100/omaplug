#!/bin/bash

set -euo pipefail

id=${1:?plugin id required}
action=${2:-disable}
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* ]] || exit 2
[[ $action == disable || $action == enable ]] || exit 2
config=$(omarchy-shell shell listShellConfig)

if [[ $action == disable ]]; then
  changes=$(jq -er --arg id "$id" '
    if type != "object" then error("invalid config") else . end
    | (.bar.layout // {})
    | if type != "object" then error("invalid layout") else . end
    | [to_entries[] | .value
        | if type != "array" then error("invalid section") else .[] end
        | select(type == "object")
        | select((.widgets | type) == "array" and (.widgets | index($id)) != null)
        | [.id, (.widgets | map(select(. != $id)) | tojson)] | @tsv]
    | join("\n")
  ' <<< "$config")
  while IFS=$'\t' read -r host widgets; do
    [[ -n $host ]] || continue
    omarchy bar set "$host" widgets "$widgets" --json
  done <<< "$changes"
  exec omarchy plugin disable "$id"
fi

exec omarchy plugin "$action" "$id"
