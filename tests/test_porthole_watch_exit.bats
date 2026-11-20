#!/usr/bin/env bats
# platform: macOS-only
# porthole-watch-exit: one watcher per application instance, which runs a command when that
# instance exits (here: stops its container stand-in), and never holds the caller's fds.

setup_file() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  OUT="$BATS_FILE_TMPDIR"
  CC="${CC:-clang}"
  $CC -Wall -Werror -I"$ROOT/standin" -o "$OUT/porthole-watch-exit" \
    "$ROOT/standin/porthole-watch-exit.c" "$ROOT/standin/caller_walk.c"
  # The instance id of exactly one process (not its top-level application): <pid>-<start second>.
  cat > "$OUT/idof.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include "caller_walk.h"
int main(int c, char **v) { struct proc_info p; (void)c;
  if (proc_lookup_live(atoi(v[1]), &p, NULL)) return 1; printf("%s-%ld\n", v[1], p.start_sec); return 0; }
C
  $CC -I"$ROOT/standin" -o "$OUT/idof" "$OUT/idof.c" "$ROOT/standin/caller_walk.c"
}

setup() {
  OUT="$BATS_FILE_TMPDIR"
  W="$(mktemp -d "${TMPDIR:-/tmp}/watch-exit.XXXXXX")"
  LOCK="$W/x.watch"
}

teardown() { rm -rf "$W"; }

ran_count() { [ -f "$W/ran" ] && wc -l < "$W/ran" | tr -d ' ' || echo 0; }

wait_ran() { # up to 5 s for the command to have run $1 times
  n=0; while [ "$(ran_count)" -lt "$1" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
}

@test "the command runs once, after the instance exits" {
  sleep 1 & pid=$!
  id=$("$OUT/idof" $pid)
  "$OUT/porthole-watch-exit" "$LOCK" "$id" -- sh -c 'echo ran >> "$0"' "$W/ran"
  [ "$(ran_count)" = 0 ]
  wait $pid
  wait_ran 1
  sleep 0.3
  [ "$(ran_count)" = 1 ]
}

@test "a second watcher on the same lock returns at once and the command still runs once" {
  sleep 1 & pid=$!
  id=$("$OUT/idof" $pid)
  "$OUT/porthole-watch-exit" "$LOCK" "$id" -- sh -c 'echo ran >> "$0"' "$W/ran"
  "$OUT/porthole-watch-exit" "$LOCK" "$id" -- sh -c 'echo ran >> "$0"' "$W/ran"
  wait $pid
  wait_ran 1
  sleep 0.5
  [ "$(ran_count)" = 1 ]
}

@test "an instance that is already gone runs the command now, with its status" {
  sleep 0 & pid=$!
  id=$("$OUT/idof" $$); id="${id%-*}-1"   # a live pid with the wrong start second
  run "$OUT/porthole-watch-exit" "$LOCK" "$id" -- sh -c 'echo ran >> "$0"; exit 3' "$W/ran"
  [ "$status" -eq 3 ]
  [ "$(ran_count)" = 1 ]
  [ ! -e "$LOCK" ]
}

@test "it returns at once and holds no inherited fds while the instance lives" {
  sleep 5 & pid=$!
  id=$("$OUT/idof" $pid)
  start=$(date +%s)
  out=$("$OUT/porthole-watch-exit" "$LOCK" "$id" -- true)
  end=$(date +%s)
  kill $pid
  [ $((end - start)) -le 1 ]
}

@test "the lock file is gone after the command ran" {
  sleep 1 & pid=$!
  id=$("$OUT/idof" $pid)
  "$OUT/porthole-watch-exit" "$LOCK" "$id" -- sh -c 'echo ran >> "$0"' "$W/ran"
  [ -e "$LOCK" ]
  wait $pid
  wait_ran 1
  n=0; while [ -e "$LOCK" ] && [ $n -lt 20 ]; do sleep 0.1; n=$((n + 1)); done
  [ ! -e "$LOCK" ]
}
