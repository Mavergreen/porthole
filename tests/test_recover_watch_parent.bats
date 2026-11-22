#!/usr/bin/env bats
# platform: macOS-only -- real BSD pgrep, whose -a includes its own ancestors (GNU pgrep's -a means something else)
# The launcher starts the watcher and then execs itself into the viewer, so the viewer is the
# watcher's PARENT. macOS pgrep leaves out its own ancestors unless given -a, so the watcher never
# saw the viewer, took it for a Quit after 20s, and stopped Linux Signal Desktop's on-demand
# container under its open window (2026-09-24). Real pgrep, real process tree.
load test_helper
W="${BATS_TEST_DIRNAME}/../bin/porthole-recover-watch"

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
