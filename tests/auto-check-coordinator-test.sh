#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

SCRIPTDIR="$TMP/scriptdir"
mkdir -p -- "$SCRIPTDIR"
cp -- "$ROOT/auto-check-coordinator.sh" "$SCRIPTDIR/"
chmod +x "$SCRIPTDIR/auto-check-coordinator.sh"

CALLS="$TMP/calls.log"
: > "$CALLS"

# Stands in for plugin-state.sh: records that it ran, takes long enough that
# a second, concurrent coordinator invocation is guaranteed to still find
# the lock held, and prints one fixed, recognizable result line.
cat > "$SCRIPTDIR/plugin-state.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$\$" >> "$CALLS"
sleep 0.4
printf 'UPDATE\tfixture\thttps://example.invalid/fixture.git\tbehind\n'
EOF
chmod +x "$SCRIPTDIR/plugin-state.sh"

export XDG_RUNTIME_DIR="$TMP/xdg"
mkdir -p -- "$XDG_RUNTIME_DIR"

PLUGINS_DIR="$TMP/plugins"
mkdir -p -- "$PLUGINS_DIR"

EXPECTED=$'UPDATE\tfixture\thttps://example.invalid/fixture.git\tbehind'

# Two "monitors" ticking their auto-check timer at effectively the same
# moment. The second is staggered by 50ms - well under the stub's 400ms
# hold time - so it deterministically finds the lock already taken instead
# of racing for it, making this a real leader/follower run rather than a
# coin flip.
"$SCRIPTDIR/auto-check-coordinator.sh" "$PLUGINS_DIR" > "$TMP/out1" 2>"$TMP/err1" &
pid1=$!
sleep 0.05
"$SCRIPTDIR/auto-check-coordinator.sh" "$PLUGINS_DIR" > "$TMP/out2" 2>"$TMP/err2" &
pid2=$!
wait "$pid1"
wait "$pid2"

call_count=$(wc -l < "$CALLS")
if [[ $call_count -ne 1 ]]; then
  printf 'FAIL: expected plugin-state.sh to run exactly once for 2 concurrent monitors, ran %s times\n' "$call_count" >&2
  cat "$CALLS" >&2
  exit 1
fi

for f in out1 out2; do
  if [[ $(cat "$TMP/$f") != "$EXPECTED" ]]; then
    printf 'FAIL: %s did not receive the leader'"'"'s result\n' "$f" >&2
    printf 'got: %q\n' "$(cat "$TMP/$f")" >&2
    cat "$TMP/err1" "$TMP/err2" >&2
    exit 1
  fi
done

# A lock directory left behind by a process that no longer exists (e.g.
# Panel.qml's checkWatchdog SIGKILLing a coordinator mid-run, which skips
# any EXIT trap) must not wedge every future auto-check.
: > "$CALLS"
LOCK="$XDG_RUNTIME_DIR/omaplug/auto-check.lock"
mkdir -p -- "$LOCK"
printf '999999\n' > "$LOCK/pid"

OUT=$("$SCRIPTDIR/auto-check-coordinator.sh" "$PLUGINS_DIR")
if [[ $OUT != "$EXPECTED" ]]; then
  printf 'FAIL: stale lock (dead pid) blocked a fresh check instead of being reclaimed\n' >&2
  printf 'got: %q\n' "$OUT" >&2
  exit 1
fi
[[ $(wc -l < "$CALLS") -eq 1 ]] || {
  printf 'FAIL: stale-lock recovery did not actually run plugin-state.sh\n' >&2
  exit 1
}
[[ -d $LOCK ]] && {
  printf 'FAIL: lock directory left behind after a successful run\n' >&2
  exit 1
}

printf 'auto-check-coordinator-test: ok\n'
