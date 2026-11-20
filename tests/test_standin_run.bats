#!/usr/bin/env bats
# platform: host-agnostic
# porthole-standin-run: run one program in the container as the child of its caller's stand-in (a
# browser helper checks its parent's executable). docker, porthole-caller are stubs; docker records
# each call's argv, one call per line, elements joined by '|', and which call read stdin.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  W="$(mktemp -d "${TMPDIR:-/tmp}/standin-run.XXXXXX")"
  export STATE="$W/state"; mkdir -p "$STATE"
  BIN="$W/bin"; mkdir -p "$BIN"
  cp "$ROOT/bin/porthole-standin-run" "$BIN/"
  cat > "$BIN/docker" <<'SH'
#!/bin/sh
line=""; for a in "$@"; do line="$line|$a"; done
printf '%s\n' "$line" >> "$STATE/docker.log"
case "$*" in
  *" porthole-standin-ctl place "*)
    [ -e "$STATE/place_fail" ] && { echo "place refused" >&2; exit 2; }
    for a in "$@"; do last=$a; done; echo "$last" ;;
  *" --run "*) in=$(cat); printf 'RUN-READ:%s\n' "$in" >> "$STATE/docker.log"; echo helper-output ;;
esac
SH
  cat > "$BIN/porthole-caller" <<'SH'
#!/bin/sh
[ -e "$STATE/refuse" ] && { echo "porthole-caller: process 9: gone or unreadable" >&2; exit 1; }
[ "$1" = pid ] || exit 9
printf '123-456\t/Applications/Google Chrome.app\n'
SH
  chmod 755 "$BIN"/*
  RUN="$BIN/porthole-standin-run"
}

teardown() { rm -rf "$W"; }

@test "an unidentifiable caller is refused with the reason, and docker is never called" {
  : > "$STATE/refuse"
  run env PATH="/usr/bin:/bin" "$RUN" c1 -u 1000:0 -- /opt/x '{id}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"porthole-standin-run: refused: porthole-caller: process 9: gone or unreadable"* ]] || false
  [ ! -e "$STATE/docker.log" ]
}

@test "places the stand-in as root, then runs the program under it -- every path one argv element" {
  out=$(printf 'from-browser' | env PATH="$BIN:/usr/bin:/bin" "$RUN" c1 -u 1000:0 -e HOME=/h -e 'X=a b' -- /opt/x '{id}')
  [ "$out" = helper-output ]   # place's output is the target, never the browser's stream
  diff -u - "$STATE/docker.log" <<'EOF2'
|exec|-u|0|c1|porthole-standin-ctl|place|/Applications/Google Chrome.app
|exec|-i|-u|1000:0|-e|HOME=/h|-e|X=a b|c1|/Applications/Google Chrome.app|--run|/opt/x|{id}
RUN-READ:from-browser
EOF2
}

@test "place fails: exit 1 and nothing runs" {
  : > "$STATE/place_fail"
  run env PATH="$BIN:/usr/bin:/bin" "$RUN" c1 -- /opt/x
  [ "$status" -eq 1 ]
  ! grep -q -- '--run' "$STATE/docker.log" || false
}

@test "a usage error is refused before anything else" {
  run env PATH="$BIN:/usr/bin:/bin" "$RUN" c1 /opt/x
  [ "$status" -eq 100 ]
  [ ! -e "$STATE/docker.log" ]
}

@test "options with no -- and no program are refused, not looped over" {
  env PATH="$BIN:/usr/bin:/bin" "$RUN" c1 -u 1000:0 2>/dev/null & pid=$!
  n=0; while kill -0 $pid 2>/dev/null && [ $n -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
  if kill -0 $pid 2>/dev/null; then kill -9 $pid; echo "looped"; return 1; fi
  wait $pid || st=$?
  [ "${st:-0}" -eq 100 ]
}

@test "a relative path to it, with CDPATH set, still finds its sibling porthole-caller" {
  mkdir -p "$W/d"; ln -s "$BIN/docker" "$W/d/docker"
  out=$(cd "$W" && printf x | CDPATH="$W" PATH="$W/d:/usr/bin:/bin" bin/porthole-standin-run c1 -- /opt/x 2>&1)
  [ "$out" = helper-output ] || { echo "$out"; return 1; }
}
