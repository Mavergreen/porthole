#!/usr/bin/env bats
# platform: host-agnostic
# porthole-cli SLUG NAME ARG...: run an app's declared CLI (1Password's `op`) in its container, as a
# native CLI talks to its running app: nothing started behind the user's back, everything passed through.

setup() {
  W="$(mktemp -d "${TMPDIR:-/tmp}/pcli.XXXXXX")"
  export STATE="$W/state"; mkdir -p "$STATE"
  APPS="$W/Applications"; R="$APPS/Linux Demo.app/Contents/Resources"; mkdir -p "$R"
  cat > "$R/demo.container" <<'SPEC'
NAME='Linux Demo'
SLUG='demo'
CONTAINER='demo-gui'
APP_USER='demo'
APP_HOME='/home/demo'
EXTRA_ENV='A=1 B=two'
CLI='op'
CLI_op='/usr/bin/op'
CLI_USER_op=''
SPEC
  BIN="$W/bin"; mkdir -p "$BIN"
  cat > "$BIN/docker" <<'SH'
#!/bin/sh
case $1 in
  inspect) [ -e "$STATE/unreachable" ] && { echo "error during connect: Get http://192.0.2.1:2376: i/o timeout" >&2; exit 1; }
    [ -e "$STATE/running" ] && echo true || echo false; exit 0 ;;
  exec)
    n=$(cat "$STATE/n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$STATE/n"
    for a in "$@"; do printf '[%s]' "$a"; done >> "$STATE/exec.log"; echo >> "$STATE/exec.log"
    if [ -e "$STATE/conn_fail_once" ] && [ "$n" = 1 ]; then echo "error during connect: i/o timeout" >&2; exit 1; fi
    [ -e "$STATE/app_says_refused" ] && { echo "[ERROR] connection refused by the server" >&2; exit 1; }
    printf 'out\000bytes'; exit 7 ;;
esac
SH
  chmod 755 "$BIN/docker"
  export PORTHOLE_APPS_DIRS="$APPS" DOCKER_HOST=tcp://192.0.2.1:2376
  CLI="${BATS_TEST_DIRNAME}/../bin/porthole-cli"
}
teardown() { rm -rf "$W"; }

@test "an undeclared CLI is refused" {
  : > "$STATE/running"
  run env PATH="$BIN:$PATH" "$CLI" demo nope x
  [ "$status" -eq 2 ]
  [[ "$output" == *"porthole-cli: demo declares no CLI 'nope'"* ]]
  [ ! -e "$STATE/exec.log" ]
}

@test "an app that isn't running is not started: it says so" {
  run env PATH="$BIN:$PATH" "$CLI" demo op whoami
  [ "$status" -eq 1 ]
  [ "$output" = "Linux Demo isn't running; open it first." ]
  [ ! -e "$STATE/exec.log" ]
}

@test "runs the program as the app's user with its environment, each argument intact" {
  : > "$STATE/running"
  run env PATH="$BIN:$PATH" "$CLI" demo op item get 'a b' "it's" '$HOME' </dev/null
  [ "$(cat "$STATE/exec.log")" = "[exec][-i][-u][demo][-e][HOME=/home/demo][-e][XDG_RUNTIME_DIR=/run/user/1000][-e][A=1][-e][B=two][demo-gui][/usr/bin/op][item][get][a b][it's][\$HOME]" ]
}

@test "stdout bytes and the exit status pass through" {
  : > "$STATE/running"
  run sh -c 'PATH="$1:$PATH" "$2" demo op read x > "$3" </dev/null' _ "$BIN" "$CLI" "$W/out"
  [ "$status" -eq 7 ]
  printf 'out\000bytes' | cmp -s - "$W/out"
}

@test "a Docker connection error is retried once" {
  : > "$STATE/running"; : > "$STATE/conn_fail_once"
  run env PATH="$BIN:$PATH" "$CLI" demo op whoami </dev/null
  [ "$status" -eq 7 ]
  [ "$(wc -l < "$STATE/exec.log" | tr -d ' ')" = 2 ]
}

@test "the program's own failure is never run again, even when it mentions a connection" {
  : > "$STATE/running"; : > "$STATE/app_says_refused"
  run env PATH="$BIN:$PATH" "$CLI" demo op item create x </dev/null
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$STATE/exec.log" | tr -d ' ')" = 1 ]
}

@test "a Docker VM that can't be reached is said so, not that the app isn't running" {
  : > "$STATE/unreachable"
  run env PATH="$BIN:$PATH" "$CLI" demo op whoami </dev/null
  [ "$status" -eq 1 ]
  [ "$output" = "Linux Demo can't be reached: the Docker VM isn't answering (check Container Tools)." ]
}
