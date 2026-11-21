#!/usr/bin/env bats
# platform: host-agnostic
# The launcher must prefer the engine-bundled s6-ipcserver (sibling of the porthole CLI).
load test_helper

@test "launcher: uses the s6-ipcserver bundled beside the porthole engine binary" {
  e="$(mktemp -d -t plte)"                 # fake engine bin dir: porthole + s6-ipcserver
  printf '#!/bin/sh\nexit 0\n' > "$e/porthole"
  printf '#!/bin/sh\necho "ENGINE-IPC $*" >> "%s"\nsleep 2\n' "$STUB_LOG" > "$e/s6-ipcserver"
  chmod +x "$e/porthole" "$e/s6-ipcserver"

  d="$(mktemp -d -t plt)"                   # host prereqs: running VM + docker
  cat > "$d/docker-machine-ctl" <<'EOF'
#!/bin/sh
[ "$1" = status ] && echo running
EOF
  printf '#!/bin/sh\nexit 0\n' > "$d/docker-machine"
  cat > "$d/docker" <<'EOF'
#!/bin/sh
case "$*" in *"inspect -f"*) echo true ;; *) : ;; esac
exit 0
EOF
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"
  chmod +x "$d"/*

  env DOCKER_HOST= DOCKER_CONTEXT= PATH="$d:$PATH" \
      PORTHOLE_BIN="$e/porthole" THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird" >/dev/null 2>&1 || true

  ok=
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    grep -q 'ENGINE-IPC' "$STUB_LOG" && { ok=1; break; }
    sleep 0.1
  done
  rm -rf "$e" "$d"
  [ -n "$ok" ] || { echo "engine s6-ipcserver not used: $(cat "$STUB_LOG")"; return 1; }
}

@test "launcher: the container side of both bridges is s6-ipcclient + s6-ioconnect, never socat" {
  l="${BATS_TEST_DIRNAME}/../templates/launcher.tmpl"
  grep -qF 'docker exec -i "$CONTAINER" s6-ipcclient /run/user/1000/porthole-xpra.sock s6-ioconnect' "$l" || return 1
  grep -qF 'docker exec -i "$CONTAINER" s6-ipcclient /run/user/1000/porthole-menu.sock s6-ioconnect' "$l" || return 1
  ! grep -v '^[[:space:]]*#' "$l" | grep -qw socat || { echo "launcher.tmpl still runs socat"; return 1; }
}

# Runs the thunderbird launcher with host stubs, TMPDIR=$1 and port 4999, so its pidfiles are known.
# The real /bin/ps (the suite's ps stub reports every pid dead) and no recovery watcher (the stub
# viewer exits at once, and an ondemand watcher would then stop the bridges itself).
run_launcher_in() {
  e="$(mktemp -d -t plte)"
  printf '#!/bin/sh\nexit 0\n' > "$e/porthole"
  printf '#!/bin/sh\necho "ENGINE-IPC $*" >> "%s"\nsleep 2\n' "$STUB_LOG" > "$e/s6-ipcserver"
  d="$(mktemp -d -t plt)"
  printf '#!/bin/sh\n[ "$1" = status ] && echo running\n' > "$d/docker-machine-ctl"
  printf '#!/bin/sh\nexit 0\n' > "$d/docker-machine"
  printf '#!/bin/sh\ncase "$*" in *"inspect -f"*) echo true ;; %s esac\nexit 0\n' "${2:-}" > "$d/docker"
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"
  chmod +x "$e"/* "$d"/*
  env DOCKER_HOST= DOCKER_CONTEXT= PATH="$d:/bin:$PATH" TMPDIR="$1" THUNDERBIRD_XPRA_PORT=4999 THUNDERBIRD_NO_RECOVER=1 \
      PORTHOLE_BIN="$e/porthole" THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird" >"$1/out" 2>&1 || true
  sleep 0.5
  rm -rf "$e" "$d"
}

# After an update the container's base has no socat, but a bridge started by the old launcher can
# still be alive (bridges outlive the launcher, and Quit for stayup apps). Reusing it means every
# connection fails; it must be replaced.
@test "launcher: a live bridge from before s6 is replaced, not reused" {
  t="$(mktemp -d -t pltt)"
  sleep 30 & stale=$!
  echo "$stale" > "$t/thunderbird-xpra-tunnel.4999.pid"
  run_launcher_in "$t"
  /bin/ps -p "$stale" >/dev/null 2>&1 && { kill "$stale"; rm -rf "$t"; echo "stale bridge left running"; return 1; }
  rm -rf "$t"
  grep -q 'ENGINE-IPC .*porthole-xpra.sock' "$STUB_LOG" || { echo "no new xpra bridge: $(cat "$STUB_LOG")"; return 1; }
}

@test "launcher: a live s6 bridge is reused" {
  t="$(mktemp -d -t pltt)"
  sh -c 'sleep 30; :' s6-ipcclient & cur=$!   # two commands, so sh keeps its argv
  echo "$cur" > "$t/thunderbird-xpra-tunnel.4999.pid"
  run_launcher_in "$t"
  alive=; /bin/ps -p "$cur" >/dev/null 2>&1 && alive=1
  kill "$cur" 2>/dev/null || true; rm -rf "$t"
  [ -n "$alive" ] || { echo "current bridge was killed"; return 1; }
  ! grep -q 'ENGINE-IPC .*porthole-xpra.sock' "$STUB_LOG" || { echo "a second xpra bridge started"; return 1; }
}

# A container built on a base from before s6 (a dev checkout on a cached :latest, or a recipe that
# didn't change) can't be relayed into at all. Say so, and how to fix it, instead of opening a
# viewer that never connects.
@test "launcher: a container without the s6 relay stops the launch and says to rebuild" {
  t="$(mktemp -d -t pltt)"
  run_launcher_in "$t" '*"command -v s6-ipcclient"*) exit 1 ;;'
  out="$(cat "$t/out")"; rm -rf "$t"
  [[ "$out" == *"--rebuild"* ]] || { echo "no rebuild advice: $out"; return 1; }
  ! grep -q 'ENGINE-IPC .*porthole-xpra.sock' "$STUB_LOG" || { echo "bridge started anyway"; return 1; }
}

@test "launcher: starts the engine's porthole-follow for this app, naming its spec and the viewer's pid" {
  e="$(mktemp -d -t plfe)"
  printf '#!/bin/sh\nexit 0\n' > "$e/porthole"
  printf '#!/bin/sh\nsleep 2\n' > "$e/s6-ipcserver"
  printf '#!/bin/sh\necho "FOLLOW $*" >> "%s"\n' "$STUB_LOG" > "$e/porthole-follow"
  chmod +x "$e"/*
  d="$(mktemp -d -t plf)"
  printf '#!/bin/sh\n[ "$1" = status ] && echo running\nexit 0\n' > "$d/docker-machine-ctl"
  printf '#!/bin/sh\nexit 0\n' > "$d/docker-machine"
  printf '#!/bin/sh\ncase "$*" in *"inspect -f"*) echo true ;; esac\nexit 0\n' > "$d/docker"
  printf '#!/bin/sh\necho "viewer-pid $$"\n' > "$d/viewer"
  chmod +x "$d"/*
  out=$(env DOCKER_HOST= DOCKER_CONTEXT= PATH="$d:$PATH" PORTHOLE_BIN="$e/porthole" THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird" 2>/dev/null) || true
  ok=
  for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q '^FOLLOW ' "$STUB_LOG" && { ok=1; break; }; sleep 0.1; done
  rm -rf "$e" "$d"
  [ -n "$ok" ] || { echo "no follower: $(cat "$STUB_LOG")"; return 1; }
  vpid=${out##*viewer-pid }
  grep -qx "FOLLOW .*/thunderbird.container $vpid" "$STUB_LOG" || { cat "$STUB_LOG"; echo "viewer $vpid"; return 1; }
}
