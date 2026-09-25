#!/usr/bin/env bats
# platform: host-agnostic
# The shared viewer watcher: WATCH_ONCE runs a single iteration so we can drive it.
load test_helper
W="${BATS_TEST_DIRNAME}/../bin/porthole-recover-watch"

setup_watch() {
  mkdir -p "$STUB_DIR"
  : > "$STUB_DIR/pgrep.gone"        # pgrep stub: report the viewer ABSENT
  export RW_BIN="/some/Porthole" RW_MARKER="$WORK/lost" \
         RW_PIDFILE="$WORK/watch.pid" RW_RELAUNCH="touch $WORK/relaunched" \
         WATCH_ONCE=1
}

@test "recover-watch relaunches when the disconnect marker is present" {
  setup_watch
  : > "$RW_MARKER"                  # viewer died from a lost backend
  run "$W"
  [ "$status" -eq 0 ] || return 1
  [ -f "$WORK/relaunched" ] || return 1     # re-invoked the launcher
  [ ! -f "$RW_MARKER" ] || return 1         # consumed the marker
}

@test "recover-watch does NOT relaunch on a clean quit (no marker)" {
  setup_watch
  run "$W"
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$WORK/relaunched" ] || return 1
}

@test "recover-watch stops the container on an on-demand quit" {
  setup_watch
  export RW_ONDEMAND=1 RW_CONTAINER="viewer-gui" RW_STOP_PIDS=""
  run "$W"
  [ "$status" -eq 0 ] || return 1
  [[ "$(cat "$STUB_LOG")" == *"docker stop viewer-gui"* ]] || return 1
}

# The launcher starts the watcher and then execs itself into the viewer, so the viewer is the
# watcher's PARENT. macOS pgrep leaves out its own ancestors unless given -a, so the watcher never
# saw the viewer, took it for a Quit after 20s, and stopped Linux Signal Desktop's on-demand
# container under its open window (2026-09-24). Real pgrep, real process tree.
@test "recover-watch sees a viewer that is its own parent" {
  cp /bin/sleep "$WORK/Porthole"
  cat > "$WORK/launch" <<LAUNCH
#!/bin/sh
RW_BIN="$WORK/Porthole" RW_MARKER="$WORK/lost" RW_PIDFILE="$WORK/watch.pid" \\
RW_RELAUNCH=true RW_DEBUG="$WORK/rw.log" \\
  nohup "$W" </dev/null >/dev/null 2>&1 3>&- &
exec "$WORK/Porthole" 30
LAUNCH
  chmod +x "$WORK/launch"
  PATH=/usr/bin:/bin "$WORK/launch" </dev/null >/dev/null 2>&1 3>&- &
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    grep -q 'waited for appear' "$WORK/rw.log" 2>/dev/null && break; sleep 0.5
  done
  pkill -f "^$WORK/Porthole" || true
  grep -q 'waited for appear; present=y' "$WORK/rw.log" || { cat "$WORK/rw.log"; return 1; }
}
