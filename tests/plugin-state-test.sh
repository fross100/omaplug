#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

PLUGINS="$TMP/plugins"
SEED="$TMP/seed"
REMOTE="$TMP/origin.git"
mkdir -p -- "$PLUGINS"

git init --bare -q "$REMOTE"
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
git init -q -b main "$SEED"
git -C "$SEED" config user.name "Omaplug Tests"
git -C "$SEED" config user.email "omaplug-tests@example.invalid"
printf '{"id":"fixture"}\n' > "$SEED/manifest.json"
git -C "$SEED" add manifest.json
git -C "$SEED" commit -qm "initial"
git -C "$SEED" remote add origin "$REMOTE"
git -C "$SEED" push -q -u origin main

# Keep one checkout at the initial commit. It becomes behind after the second
# upstream commit, and a local commit on a copy of it creates a divergence.
git clone -q "$REMOTE" "$PLUGINS/behind"
git clone -q "$REMOTE" "$PLUGINS/diverged"

printf '{"id":"fixture","version":2}\n' > "$SEED/manifest.json"
git -C "$SEED" add manifest.json
git -C "$SEED" commit -qm "upstream update"
git -C "$SEED" push -q

git clone -q "$REMOTE" "$PLUGINS/current"
git clone -q "$REMOTE" "$PLUGINS/dirty"
git clone -q "$REMOTE" "$PLUGINS/ahead"
git clone -q "$REMOTE" "$PLUGINS/fetch-error"
git clone -q "$REMOTE" "$PLUGINS/detached"

printf '\n' >> "$PLUGINS/dirty/manifest.json"
git -C "$PLUGINS/detached" checkout -q --detach

git -C "$PLUGINS/ahead" config user.name "Omaplug Tests"
git -C "$PLUGINS/ahead" config user.email "omaplug-tests@example.invalid"
printf '{"id":"fixture","version":3}\n' > "$PLUGINS/ahead/manifest.json"
git -C "$PLUGINS/ahead" add manifest.json
git -C "$PLUGINS/ahead" commit -qm "local commit"

git -C "$PLUGINS/diverged" config user.name "Omaplug Tests"
git -C "$PLUGINS/diverged" config user.email "omaplug-tests@example.invalid"
printf '{"id":"fixture","local":true}\n' > "$PLUGINS/diverged/manifest.json"
git -C "$PLUGINS/diverged" add manifest.json
git -C "$PLUGINS/diverged" commit -qm "divergent local commit"

git -C "$PLUGINS/fetch-error" remote set-url origin "$TMP/missing.git"

mkdir -p -- "$PLUGINS/plain" "$PLUGINS/no-origin"
printf '{"id":"plain"}\n' > "$PLUGINS/plain/manifest.json"
printf '{"id":"no-origin"}\n' > "$PLUGINS/no-origin/manifest.json"
git init -q "$PLUGINS/no-origin"
git -C "$PLUGINS/no-origin" config user.name "Omaplug Tests"
git -C "$PLUGINS/no-origin" config user.email "omaplug-tests@example.invalid"
git -C "$PLUGINS/no-origin" add manifest.json
git -C "$PLUGINS/no-origin" commit -qm "local plugin"
ln -s -- "$PLUGINS/current" "$PLUGINS/symlinked"

OUTPUT=$($ROOT/plugin-state.sh "$PLUGINS")

state_for() {
  local id="$1"
  awk -F '\t' -v id="$id" '$1 != "CHECK" && $2 == id { print $1 }' <<< "$OUTPUT"
}

detail_for() {
  local id="$1"
  awk -F '\t' -v id="$id" '$1 != "CHECK" && $2 == id { print $4 }' <<< "$OUTPUT"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ $actual != "$expected" ]]; then
    printf 'FAIL: %s: expected %q, got %q\n' "$label" "$expected" "$actual" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
  fi
}

assert_eq CURRENT "$(state_for current)" current
assert_eq UPDATE "$(state_for behind)" behind
assert_eq LOCAL_CHANGES "$(state_for dirty)" dirty
assert_eq modified "$(detail_for dirty)" dirty-detail
assert_eq LOCAL_CHANGES "$(state_for detached)" detached
assert_eq detached "$(detail_for detached)" detached-detail
assert_eq LOCAL_CHANGES "$(state_for ahead)" ahead
assert_eq ahead "$(detail_for ahead)" ahead-detail
assert_eq LOCAL_CHANGES "$(state_for diverged)" diverged
assert_eq diverged "$(detail_for diverged)" diverged-detail
assert_eq LOCAL "$(state_for plain)" plain
assert_eq LOCAL "$(state_for no-origin)" no-origin
assert_eq LOCAL "$(state_for symlinked)" symlinked
assert_eq ERROR "$(state_for fetch-error)" fetch-error

current_url=$(awk -F '\t' '$1 == "CURRENT" && $2 == "current" { print $3 }' <<< "$OUTPUT")
assert_eq "$REMOTE" "$current_url" origin-url-without-trailing-space

printf 'plugin-state-test: ok\n'
