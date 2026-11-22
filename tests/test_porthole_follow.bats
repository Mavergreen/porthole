#!/usr/bin/env bats
# platform: macOS-only -- drives bin/porthole-follow, a macOS-only script (BSD stat, its Mac sockets)
# porthole-follow SPEC VIEWER_PID: while the app's viewer runs, each declared socket is served on the
# Mac exactly while the app serves it in its container (1Password's SSH agent exists while "Use the
# SSH agent" is ticked), and is gone when the viewer is.

setup() {
  W="$(mktemp -d "${TMPDIR:-/tmp}/pfol.XXXXXX")"
  export STATE="$W/state" HOME="$W/home" TMPDIR="$W/tmp"; mkdir -p "$STATE" "$HOME" "$TMPDIR"
  cat > "$W/demo.container" <<'SPEC'
NAME='Linux Demo'
SLUG='demo'
CONTAINER='demo-gui'
APP_USER='demo'
APP_HOME='/home/demo'
APP_BIN='demo'
SOCKETS='ssh-agent'
SOCKET_ssh_agent='/home/demo/agent.sock ~/.demo/agent.sock'
SPEC
  BIN="$W/bin"; mkdir -p "$BIN"
  cat > "$BIN/docker" <<'SH'
#!/bin/sh
# docker exec [-u U] CONTAINER test -S PATH | other
for a in "$@"; do last=$a; done
case "$*" in
  *"test -S"*)
    [ -e "$STATE/dockerfail" ] && { echo "error during connect: i/o timeout" >&2; exit 1; }
    [ -e "$STATE/present" ] && echo yes || echo no ;;
  *) exit 0 ;;
esac
SH
  cat > "$BIN/s6-ipcserver" <<'SH'
#!/bin/sh
echo "$*" >> "$STATE/served.log"
: > "$3"
trap 'exit 0' TERM
while :; do sleep 0.1; done
SH
  printf '#!/bin/sh\nexit 0\n' > "$BIN/osascript"
  chmod 755 "$BIN"/*
  sleep 600 </dev/null >/dev/null 2>&1 3>&- & VIEWER=$!
  export PATH="$BIN:$PATH" PORTHOLE_FOLLOW_SECS=0.2 DOCKER_HOST=tcp://192.0.2.1:2376 PORTHOLE_FOLLOW_BIN="$BIN"
  FOLLOW="${BATS_TEST_DIRNAME}/../bin/porthole-follow"
  MAC="$HOME/.demo/agent.sock"
}
teardown() {
  kill "$VIEWER" 2>/dev/null || :
  [ -f "$W/pids" ] && kill $(cat "$W/pids") 2>/dev/null || :
  [ -f "$W/follow.pid" ] && kill "$(cat "$W/follow.pid")" 2>/dev/null || :
  sleep 0.3; rm -rf "$W"
}
start_follow() { "$FOLLOW" "$W/demo.container" "$VIEWER" </dev/null >"$W/follow.out" 2>&1 3>&- & echo $! > "$W/follow.pid"; }
until_() { n=0; until eval "$1"; do n=$((n + 1)); [ $n -le 40 ] || return 1; sleep 0.1; done; }

@test "the Mac socket appears when the app serves its socket, and goes when it stops" {
  start_follow
  sleep 0.6; [ ! -e "$MAC" ]
  : > "$STATE/present"
  until_ '[ -e "$MAC" ]'
  grep -q -- "-a 0600 $MAC .*porthole-standin-bridge demo-gui ssh-agent /home/demo/agent.sock" "$STATE/served.log"
  [ "$(stat -f %Lp "$HOME/.demo")" = 700 ]
  rm "$STATE/present"
  until_ '[ ! -e "$MAC" ]'
  [ "$(wc -l < "$STATE/served.log" | tr -d ' ')" = 1 ]
}

@test "when the viewer exits, the Mac socket goes and the follower exits" {
  : > "$STATE/present"; start_follow
  until_ '[ -e "$MAC" ]'
  kill "$VIEWER"
  until_ '[ ! -e "$MAC" ]'
  until_ '! kill -0 "$(cat "$W/follow.pid")" 2>/dev/null'
  until_ '! pgrep -f "s6-ipcserver -a 0600 $MAC" >/dev/null'
}

@test "a second follower for the same app exits at once" {
  start_follow; sleep 0.3
  run "$FOLLOW" "$W/demo.container" "$VIEWER"
  [ "$status" -eq 0 ]
  kill -0 "$(cat "$W/follow.pid")"
}

@test "a leftover Mac socket from a crash is replaced when the app serves again" {
  mkdir -p "$HOME/.demo"; : > "$MAC"
  : > "$STATE/present"; start_follow
  until_ '[ -s "$STATE/served.log" ]'
}

@test "SIGTERM stops serving and removes the Mac socket" {
  : > "$STATE/present"; start_follow
  until_ '[ -e "$MAC" ]'
  kill -TERM "$(cat "$W/follow.pid")"
  until_ '[ ! -e "$MAC" ]'
}

@test "a relaunched viewer's follower takes over from one still finishing for the old viewer" {
  : > "$STATE/present"
  PORTHOLE_FOLLOW_SECS=30 start_follow            # slow to notice its viewer is gone
  until_ '[ -e "$MAC" ]'
  old=$(cat "$W/follow.pid")
  sleep 600 </dev/null >/dev/null 2>&1 3>&- & V2=$!; echo "$V2" >> "$W/pids"
  "$FOLLOW" "$W/demo.container" "$V2" </dev/null >/dev/null 2>&1 3>&- & new=$!; echo "$new $old" >> "$W/pids"
  until_ '! kill -0 "$old" 2>/dev/null'
  kill -0 "$new"
  until_ '[ -e "$MAC" ]'
  kill "$new" "$V2" 2>/dev/null || :
}

@test "two followers started at once for the same viewer leave one" {
  "$FOLLOW" "$W/demo.container" "$VIEWER" </dev/null >/dev/null 2>&1 3>&- & a=$!
  "$FOLLOW" "$W/demo.container" "$VIEWER" </dev/null >/dev/null 2>&1 3>&- & b=$!; echo "$a $b" >> "$W/pids"
  sleep 1
  n=0; kill -0 "$a" 2>/dev/null && n=$((n + 1)); kill -0 "$b" 2>/dev/null && n=$((n + 1))
  kill "$a" "$b" 2>/dev/null || :
  [ "$n" -eq 1 ]
}

@test "a moment Docker can't be reached leaves the Mac socket served" {
  : > "$STATE/present"; start_follow
  until_ '[ -e "$MAC" ]'
  : > "$STATE/dockerfail"; sleep 0.8
  [ -e "$MAC" ]
  [ "$(wc -l < "$STATE/served.log" | tr -d ' ')" = 1 ]
}
