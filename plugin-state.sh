#!/bin/bash
# Classify every installed third-party plugin for the update UI.
#
# Output is tab-separated and streamed one record at a time:
#   CHECK          <id>
#   <state>        <id>    <origin-url>    <detail>
#
# Stable states are CURRENT, UPDATE, LOCAL_CHANGES, LOCAL, and ERROR.

set -uo pipefail

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"

PLUGINS_DIR="${1:-$HOME/.config/omarchy/plugins}"

emit_state() {
  local state="$1"
  local id="$2"
  local url="${3:-}"
  local detail="${4:-}"
  printf '%s\t%s\t%s\t%s\n' "$state" "$id" "$url" "$detail"
}

origin_url() {
  local dir="$1"
  local url
  url=$(git -C "$dir" remote get-url origin 2>/dev/null) || return 1
  url=${url//$'\t'/ }
  url=${url//$'\r'/ }
  url=${url//$'\n'/ }
  printf '%s' "$url"
}

[[ -d $PLUGINS_DIR ]] || exit 0

for dir in "$PLUGINS_DIR"/*; do
  [[ -d $dir && -f $dir/manifest.json ]] || continue

  id="${dir##*/}"
  printf 'CHECK\t%s\n' "$id"

  # Omarchy uses symlinks for development plugins. Even when the target is a
  # Git repository, updating it here would mutate its source workspace.
  if [[ -L $dir ]]; then
    url=""
    resolved=$(realpath -e -- "$dir" 2>/dev/null || true)
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n $resolved && $resolved == "$top" ]]; then
      url=$(origin_url "$dir")
    fi
    emit_state LOCAL "$id" "$url" symlink
    continue
  fi

  # Match the public Omarchy updater: only a checkout with its own .git
  # directory is managed. Plain folders and linked worktrees stay local.
  if [[ ! -d $dir/.git ]]; then
    emit_state LOCAL "$id" "" not-git-managed
    continue
  fi

  url=$(origin_url "$dir")
  if [[ -z $url ]]; then
    emit_state LOCAL "$id" "" no-origin
    continue
  fi

  if ! head=$(git -C "$dir" rev-parse --verify HEAD 2>/dev/null); then
    emit_state LOCAL "$id" "$url" no-commits
    continue
  fi

  if ! git -C "$dir" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
    emit_state LOCAL_CHANGES "$id" "$url" detached
    continue
  fi

  if ! changes=$(git -C "$dir" status --porcelain --untracked-files=normal 2>/dev/null); then
    emit_state ERROR "$id" "$url" inspect-failed
    continue
  elif [[ -n $changes ]]; then
    emit_state LOCAL_CHANGES "$id" "$url" modified
    continue
  fi

  if ! timeout 15 git -C "$dir" fetch --quiet origin HEAD 2>/dev/null; then
    emit_state ERROR "$id" "$url" fetch-failed
    continue
  fi

  remote=$(git -C "$dir" rev-parse --verify FETCH_HEAD 2>/dev/null || true)
  if [[ -z $remote ]]; then
    emit_state ERROR "$id" "$url" invalid-fetch-head
  elif [[ $head == "$remote" ]]; then
    emit_state CURRENT "$id" "$url" equal
  elif git -C "$dir" merge-base --is-ancestor "$head" "$remote" 2>/dev/null; then
    emit_state UPDATE "$id" "$url" behind
  elif git -C "$dir" merge-base --is-ancestor "$remote" "$head" 2>/dev/null; then
    emit_state LOCAL_CHANGES "$id" "$url" ahead
  else
    emit_state LOCAL_CHANGES "$id" "$url" diverged
  fi
done
