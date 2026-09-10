#!/bin/bash

set -euo pipefail

id=${1:?plugin id required}
action=${2:-disable}
config=$(omarchy-shell shell listShellConfig)

if [[ $action == disable ]]; then
  while IFS=$'\t' read -r host widgets; do
    [[ -n $host ]] || continue
    omarchy bar set "$host" widgets "$widgets" --json
  done < <(jq -r --arg id "$id" '
    .bar.layout // {} | to_entries[] | .value[]
    | select((.widgets | type) == "array" and (.widgets | index($id)) != null)
    | [.id, (.widgets | map(select(. != $id)))] | @tsv
  ' <<< "$config")
  exec omarchy plugin disable "$id"
fi

exec omarchy plugin "$action" "$id"
