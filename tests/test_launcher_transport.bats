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
