#!/usr/bin/env bats
# platform: host-agnostic
# porthole-native-host SLUG NAME ARG...: a browser's native-messaging host for an app (1Password's
# extension), as the browser's manifest runs it: the declared files copied in as root, then the
# declared program run under the calling browser's stand-in (porthole-standin-run).

setup() {
  W="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pnh.XXXXXX")" && pwd)"
  export STATE="$W/state"; mkdir -p "$STATE"
  APPS="$W/Applications"; R="$APPS/Linux Demo.app/Contents/Resources"; mkdir -p "$R"
  cat > "$R/demo.container" <<SPEC
NAME='Linux Demo'
SLUG='demo'
CONTAINER='demo-gui'
APP_USER='demo'
APP_HOME='/home/demo'
NATIVE_HOSTS='browser'
NATIVE_HOST_browser='/opt/Demo/Host 1000:0'
NATIVE_HOST_browser_FILE='/etc/demo/allowed $W/preseeded $W/allowed'
SPEC
  printf 'Safari.app\nChromium.app\n' > "$W/preseeded"
  BIN="$W/bin"; mkdir -p "$BIN"
  cat > "$BIN/docker" <<'SH'
#!/bin/sh
case $1 in
  inspect) [ -e "$STATE/unreachable" ] && { echo "Cannot connect to the Docker daemon at tcp://192.0.2.1:2376" >&2; exit 1; }
    [ -e "$STATE/down" ] && echo false || echo true; exit 0 ;;
  exec) echo "docker $*" >> "$STATE/log"; cat > "$STATE/file.in"; exit 0 ;;
esac
SH
  cat > "$BIN/porthole-standin-run" <<'SH'
#!/bin/sh
echo "porthole-standin-run $*" >> "$STATE/log"; cat > "$STATE/host.in"
SH
  # Both Mac files read as root-owned 0644 unless a test says otherwise.
  printf '#!/bin/sh\nfor a; do f=$a; done\ncase $f in *allowed) cat "$STATE/stat" 2>/dev/null || echo "0 644" ;; *) echo "0 644" ;; esac\n' > "$BIN/stat"
  chmod 755 "$BIN"/*
  export PORTHOLE_APPS_DIRS="$APPS" DOCKER_HOST=tcp://192.0.2.1:2376 PORTHOLE_TOOLS_BIN="$BIN" PATH="$BIN:$PATH"
  HOST="${BATS_TEST_DIRNAME}/../bin/porthole-native-host"
}
teardown() { rm -rf "$W"; }

@test "runs the declared program under the browser's stand-in, with only the browser's last argument" {
  run "$HOST" demo browser /path/to/manifest.json '{ext-id}' </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qx 'porthole-standin-run demo-gui -u 1000:0 -e HOME=/home/demo -e XDG_RUNTIME_DIR=/run/user/1000 -- /opt/Demo/Host {ext-id}' "$STATE/log" \
    || { cat "$STATE/log"; return 1; }
}

@test "the file is written as root before the program runs, from each Mac source in order, comments and blanks dropped" {
  printf '# mine\n\n  Google Chrome.app  \n' > "$W/allowed"
  run "$HOST" demo browser '{id}' </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  w=$(grep -n '^docker exec -i -u 0 demo-gui sh -c ' "$STATE/log" | cut -d: -f1)
  r=$(grep -n '^porthole-standin-run' "$STATE/log" | cut -d: -f1)
  [ -n "$w" ]
  [ "$w" -lt "$r" ]
  grep -q 'mv -f "$t" "$1"' "$STATE/log"
  grep -q ' /etc/demo/allowed$' "$STATE/log"
  printf 'Safari.app\nChromium.app\nGoogle Chrome.app\n' | diff -u - "$STATE/file.in"
}

@test "the browser's stdin goes only to the program" {
  printf 'native-message' | "$HOST" demo browser '{id}'
  ! grep -q native-message "$STATE/file.in" || false
  grep -q native-message "$STATE/host.in"
}

@test "a Mac source anyone but root could write is ignored, with a note" {
  printf 'Evil.app\n' > "$W/allowed"; echo "501 644" > "$STATE/stat"
  run "$HOST" demo browser '{id}' </dev/null
  [ "$status" -eq 0 ]
  ! grep -q Evil.app "$STATE/file.in" || false
  [[ "$output" == *"ignoring $W/allowed"* ]] || false
}

@test "a root-owned Mac source writable by group or others is ignored" {
  printf 'Evil.app\n' > "$W/allowed"; echo "0 664" > "$STATE/stat"
  run "$HOST" demo browser '{id}' </dev/null
  ! grep -q Evil.app "$STATE/file.in" || false
}

@test "a missing Mac source is skipped quietly" {
  run "$HOST" demo browser '{id}' </dev/null
  [ "$status" -eq 0 ]
  printf 'Safari.app\nChromium.app\n' | diff -u - "$STATE/file.in"
}

@test "an app that isn't running is not started: it says so" {
  touch "$STATE/down"
  run "$HOST" demo browser '{id}' </dev/null
  [ "$status" -eq 1 ]
  [ "$output" = "Linux Demo isn't running; open it first." ]
  [ ! -e "$STATE/log" ]
}

@test "an undeclared host is refused" {
  run "$HOST" demo nope '{id}' </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"porthole-native-host: demo declares no native host 'nope'"* ]] || false
}

@test "a Docker VM that can't be reached is said so" {
  touch "$STATE/unreachable"
  run "$HOST" demo browser '{id}' </dev/null
  [ "$status" -eq 1 ]
  [ "$output" = "Linux Demo can't be reached: the Docker VM isn't answering (check Container Tools)." ]
}
