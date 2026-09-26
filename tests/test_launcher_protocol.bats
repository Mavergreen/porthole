#!/usr/bin/env bats
# The generated launcher under the viewer (PORTHOLE_PROTOCOL=1): JSON on stdout, answers on stdin.
load test_helper
ENGINE="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

app() {  # a materialized-style root around the generated thunderbird launcher
  R="$WORK/app/Contents/Resources"; mkdir -p "$R/bin" "$WORK/app/Contents/MacOS" "$WORK/presets/thunderbird/share/porthole/presets"
  cp "$ENGINE/examples/bin/thunderbird" "$R/bin/"; cp "$ENGINE/bin/porthole-say.sh" "$R/bin/"
  printf "SLUG='thunderbird'\nCONTAINER=thunderbird-gui\nIMAGE=mavericks-thunderbird\n" > "$R/thunderbird.container"
  : > "$WORK/presets/thunderbird/share/porthole/presets/thunderbird.conf"
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$WORK/app/Contents/MacOS/Porthole"; chmod +x "$WORK/app/Contents/MacOS/Porthole"
  export PORTHOLE_PRESETS_GLOB="$WORK/presets/*/share/porthole/presets" HOME="$WORK/home"
}
launch() {  # stdin = answers
  run env PORTHOLE_PROTOCOL=1 DOCKER_HOST=tcp://192.0.2.1:2376 THUNDERBIRD_NO_RECOVER=1 \
      PORTHOLE_READY_TRIES=1 "$R/bin/thunderbird"
}

@test "under the viewer the launcher ends with ready, not by exec'ing the viewer" {
  app; launch </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *'{"t":"ready","socket":"'*'thunderbird-xpra.sock"'* ]] || return 1
  [[ "$output" != *"viewer-exec"* ]] || return 1
}

@test "a launch says what it's doing from its first line, so its window is never blank" {
  app; launch </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  first=$(printf '%s\n' "$output" | grep '^{' | head -n 1)
  [[ "$first" == '{"t":"step","text":"Checking Container Tools"}' ]] || { echo "$output"; return 1; }
  [[ "$output" == *'{"t":"step","text":"Starting Linux Thunderbird"}'*'"t":"ready"'* ]] || { echo "$output"; return 1; }
}

@test "a healthy launch doesn't go looking for a full disk" {
  app; launch </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! grep -q '^docker logs' "$STUB_LOG" || return 1
  [ "$(grep -c '^docker exec .*python3' "$STUB_LOG")" -eq 1 ] || return 1
}

@test "the viewer hears the launcher end even while its bridges keep running" {
  app; export S6_STUB_SLEEP=8
  t0=$(date +%s)
  out=$(env PORTHOLE_PROTOCOL=1 DOCKER_HOST=tcp://192.0.2.1:2376 THUNDERBIRD_NO_RECOVER=1 PORTHOLE_READY_TRIES=1 "$R/bin/thunderbird" 2>/dev/null </dev/null)
  [ $(( $(date +%s) - t0 )) -lt 5 ] || return 1
  [[ "$out" == *'"t":"ready"'* ]] || return 1
}

@test "every stdout line under the viewer is a protocol message" {
  app
  out=$(env PORTHOLE_PROTOCOL=1 DOCKER_HOST=tcp://192.0.2.1:2376 THUNDERBIRD_NO_RECOVER=1 PORTHOLE_READY_TRIES=1 "$R/bin/thunderbird" 2>/dev/null </dev/null)
  printf '%s\n' "$out" | while IFS= read -r l; do case "$l" in '{"t":'*) ;; *) echo "stray: $l"; exit 1 ;; esac; done
}

@test "a failure is an error message, not a dialog" {
  app; export PORTHOLE_BIN="$WORK/failing-porthole"
  printf '#!/bin/sh\necho "boom detail" >&2\nexit 1\n' > "$PORTHOLE_BIN"; chmod +x "$PORTHOLE_BIN"
  launch </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *'"t":"error"'*'boom detail'* ]] || return 1
  ! grep -q osascript "$STUB_LOG" || return 1
}

@test "an error porthole up already reported (exit 3) is not reported twice" {
  app; export PORTHOLE_BIN="$WORK/short-porthole"
  printf '#!/bin/sh\necho %s\nexit 3\n' "'{\"t\":\"error\",\"text\":\"short\",\"detail\":\"\"}'" > "$PORTHOLE_BIN"; chmod +x "$PORTHOLE_BIN"
  launch </dev/null
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '"t":"error"')" -eq 1 ]
}

@test "an orphaned volume gets asked about; Delete removes it" {
  app
  printf 'oldapp-gui-data oldapp\nthunderbird-gui-data thunderbird\n' > "$STUB_DIR/docker-volumes"
  launch <<'EOF'
{"t":"answer","id":"orphan-oldapp-gui-data","choice":"Delete"}
EOF
  [[ "$output" == *'{"t":"ask","id":"orphan-oldapp-gui-data"'* ]] || return 1
  [[ "$output" != *'orphan-thunderbird'* ]] || return 1
  grep -q '^docker volume rm oldapp-gui-data$' "$STUB_LOG"
}

@test "Keep is remembered; Ask later is not" {
  app
  printf 'oldapp-gui-data oldapp\n' > "$STUB_DIR/docker-volumes"
  launch <<'EOF'
{"t":"answer","id":"orphan-oldapp-gui-data","choice":"Keep"}
EOF
  grep -qx oldapp-gui-data "$HOME/Library/Application Support/Mavergreen/Porthole/kept-data"
  launch </dev/null
  [[ "$output" != *'"t":"ask"'* ]] || return 1
  ! grep -q '^docker volume rm' "$STUB_LOG" || return 1
}

@test "a container crash-looping on a full disk is reported as such" {
  app; echo 'OSError: [Errno 28] No space left on device' > "$STUB_DIR/docker-logs"
  printf '1\n' > "$STUB_DIR/docker-exec-fails"
  launch </dev/null
  [[ "$output" == *'"t":"error"'*'out of disk space'* ]] || return 1
}

@test "the orphan question names the uninstalled app and how much data it left" {
  app; printf 'oldapp-gui-data oldapp\n' > "$STUB_DIR/docker-volumes"
  printf 'Linux Old App\t1.2 GB\n' > "$STUB_DIR/describe-data"
  launch </dev/null
  [[ "$output" == *'"text":"Linux Old App was uninstalled; its data uses 1.2 GB. Keep it, or delete it?"'* ]] || { echo "$output"; return 1; }
}

@test "an unmeasured orphan is still asked about, without a size" {
  app; printf 'oldapp-gui-data oldapp\n' > "$STUB_DIR/docker-volumes"
  printf 'oldapp\t\n' > "$STUB_DIR/describe-data"
  launch </dev/null
  [[ "$output" == *'"text":"oldapp was uninstalled; its data is still here. Keep it, or delete it?"'* ]] || { echo "$output"; return 1; }
}

@test "a kept volume is matched exactly, not as a pattern" {
  app; printf 'old.app-data oldapp\n' > "$STUB_DIR/docker-volumes"
  mkdir -p "$HOME/Library/Application Support/Mavergreen/Porthole"
  echo 'oldXapp-data' > "$HOME/Library/Application Support/Mavergreen/Porthole/kept-data"   # would match old.app-data as a regex
  launch </dev/null
  [[ "$output" == *'"id":"orphan-old.app-data"'* ]] || { echo "$output"; return 1; }
}
