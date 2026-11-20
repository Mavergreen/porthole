#!/usr/bin/env bats
# platform: host-agnostic
# porthole-standin-bridge, per bridged connection: name the Mac application (porthole-caller), make
# sure its stand-in runs in the container (once, under a lock, sweeping orphans), start its exit
# watcher, and relay to the stand-in. docker, porthole-caller, s6-setlock and porthole-watch-exit
# are stubs here; docker records each call's argv, one call per line, elements joined by '|'.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  W="$(mktemp -d "${TMPDIR:-/tmp}/standin-bridge.XXXXXX")"
  export STATE="$W/state"; mkdir -p "$STATE"
  export TMPDIR="$W/tmp"; mkdir -p "$TMPDIR"
  BIN="$W/bin"; mkdir -p "$BIN"
  cp "$ROOT/bin/porthole-standin-bridge" "$BIN/"
  cat > "$BIN/docker" <<'SH'
#!/bin/sh
line=""; for a in "$@"; do line="$line|$a"; done
printf '%s\n' "$line" >> "$STATE/docker.log"
# docker exec [-i] [-u U] CONTAINER porthole-standin-ctl CMD ...
shift; [ "$1" = -i ] && shift; [ "$1" = -u ] && shift 2; shift
[ "$1" = porthole-standin-ctl ] || exit 0
case $2 in
  alive) [ -e "$STATE/alive.$3" ] ;;
  list) cat "$STATE/list" 2>/dev/null; exit 0 ;;
  place) [ -e "$STATE/place_fail" ] && { echo "place refused" >&2; exit 2; }; echo "$3" ;;
  start) sleep 0.2; : > "$STATE/alive.$3" ;;
  stop) rm -f "$STATE/alive.$3" ;;
esac
SH
  cat > "$BIN/porthole-caller" <<'SH'
#!/bin/sh
case $1 in
  peer) [ -e "$STATE/refuse" ] && { echo "porthole-caller: process 9: gone or unreadable" >&2; exit 1; }
        printf '123-456\t/Applications/Google Chrome.app\n' ;;
  alive) [ ! -e "$STATE/dead.$2" ] ;;
esac
SH
  cat > "$BIN/s6-setlock" <<'SH'
#!/bin/sh
lock=$1; shift
until mkdir "$lock.d" 2>/dev/null; do sleep 0.05; done
"$@"; rc=$?
rmdir "$lock.d"
exit $rc
SH
  cat > "$BIN/porthole-watch-exit" <<'SH'
#!/bin/sh
line=""; for a in "$@"; do line="$line|$a"; done
printf '%s\n' "$line" >> "$STATE/watch.log"
SH
  chmod 755 "$BIN"/*
  BRIDGE="$BIN/porthole-standin-bridge"
  TO=/home/onepassword/.1password/agent.sock
}

teardown() { rm -rf "$W"; }

calls() { grep -c "$1" "$STATE/docker.log" 2>/dev/null || true; }

@test "an unidentifiable caller is refused with the reason, and docker is never called" {
  : > "$STATE/refuse"
  run env PATH="/usr/bin:/bin" "$BRIDGE" c1 ssh-agent "$TO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"porthole-standin-bridge: refused: porthole-caller: process 9: gone or unreadable"* ]]
  [ ! -e "$STATE/docker.log" ]
}

@test "a live stand-in: only the alive check, then the relay" {
  : > "$STATE/alive.123-456.ssh-agent"
  run env PATH="$BIN:/usr/bin:/bin" "$BRIDGE" c1 ssh-agent "$TO"
  [ "$status" -eq 0 ]
  diff -u - "$STATE/docker.log" <<'EOF2'
|exec|-u|1000|c1|porthole-standin-ctl|alive|123-456.ssh-agent
|exec|-i|-u|1000|c1|s6-ipcclient|/run/user/1000/porthole-standin/123-456.ssh-agent.sock|s6-ioconnect
EOF2
  [ ! -e "$STATE/watch.log" ]
}

@test "a first connection places, starts, watches, then relays -- the app path one argv element" {
  run env PATH="$BIN:/usr/bin:/bin" "$BRIDGE" c1 ssh-agent "$TO"
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qxF '|exec|-u|0|c1|porthole-standin-ctl|place|/Applications/Google Chrome.app' "$STATE/docker.log"
  grep -qxF "|exec|-u|1000|c1|porthole-standin-ctl|start|123-456.ssh-agent|/Applications/Google Chrome.app|$TO" "$STATE/docker.log"
  tail -1 "$STATE/docker.log" | grep -qxF '|exec|-i|-u|1000|c1|s6-ipcclient|/run/user/1000/porthole-standin/123-456.ssh-agent.sock|s6-ioconnect'
  grep -qxF "|$TMPDIR/porthole-standin/c1/123-456.ssh-agent.watch|123-456|--|docker|exec|-u|1000|c1|porthole-standin-ctl|stop|123-456.ssh-agent" "$STATE/watch.log"
}

@test "place fails: refused, no start, no relay" {
  : > "$STATE/place_fail"
  run env PATH="$BIN:/usr/bin:/bin" "$BRIDGE" c1 ssh-agent "$TO"
  [ "$status" -eq 1 ]
  [ "$(calls '|start|')" = 0 ]
  [ "$(calls s6-ipcclient)" = 0 ]
  [ ! -e "$STATE/watch.log" ]
}

@test "creating a stand-in sweeps a listed stand-in whose instance is dead, and keeps a live one" {
  printf '77-1.ssh-agent\n88-2.browser\n' > "$STATE/list"
  : > "$STATE/dead.77-1"
  run env PATH="$BIN:/usr/bin:/bin" "$BRIDGE" c1 ssh-agent "$TO"
  [ "$status" -eq 0 ]
  grep -qxF '|exec|-u|1000|c1|porthole-standin-ctl|stop|77-1.ssh-agent' "$STATE/docker.log"
  [ "$(calls '|stop|88-2.browser')" = 0 ]
}

@test "concurrent first connections create once" {
  for i in 1 2 3; do
    env PATH="$BIN:/usr/bin:/bin" "$BRIDGE" c1 ssh-agent "$TO" > "$W/out$i" 2>&1 &
  done
  wait
  [ "$(calls '|place|')" = 1 ]
  [ "$(calls '|start|')" = 1 ]
  [ "$(calls s6-ipcclient)" = 3 ]
  [ "$(wc -l < "$STATE/watch.log" | tr -d ' ')" = 1 ]
}

@test "its siblings are found beside it before PATH" {
  : > "$STATE/refuse"
  mkdir "$W/other"; printf '#!/bin/sh\necho WRONG >&2; exit 9\n' > "$W/other/porthole-caller"
  chmod 755 "$W/other/porthole-caller"
  run env PATH="$W/other:$BIN:/usr/bin:/bin" "$BRIDGE" c1 ssh-agent "$TO"
  [ "$status" -eq 1 ]
  [[ "$output" != *WRONG* ]]
}

@test "nothing but the relay writes to the connection (stdout)" {
  : > "$STATE/noisy"
  sed -i.bak 's/^  start) sleep 0.2;/  start) [ -e "$STATE\/noisy" ] \&\& echo NOISE; sleep 0.2;/' "$BIN/docker"
  printf '#!/bin/sh\necho WATCHNOISE\n' > "$BIN/porthole-watch-exit"
  env PATH="$BIN:/usr/bin:/bin" "$BRIDGE" c1 ssh-agent "$TO" > "$W/stdout" 2> "$W/stderr"
  grep -q NOISE "$BIN/docker"
  [ ! -s "$W/stdout" ]
}
