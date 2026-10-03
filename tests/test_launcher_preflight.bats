#!/usr/bin/env bats
# platform: host-agnostic
# The generated launcher preflights host prerequisites via docker-machine-ctl status.
# Note: Mavericks /usr/bin/env has no -u, so we set DOCKER_HOST=/DOCKER_CONTEXT= EMPTY
# (the preflight bypass tests `[ -n "$DOCKER_HOST" ]`, so empty == unset for its purposes).
load test_helper

run_launcher() {  # $1 = ctl status word; empty DOCKER_HOST so preflight runs
  d="$(mktemp -d -t plf)"
  cat > "$d/docker-machine-ctl" <<EOF
#!/bin/sh
[ "\$1" = status ] && echo "$1"
EOF
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  cat > "$d/docker" <<'EOF'
#!/bin/sh
case "$*" in *"inspect -f"*) echo true ;; *) : ;; esac
exit 0
EOF
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  run env DOCKER_HOST= DOCKER_CONTEXT= PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  rm -rf "$d"
}

@test "launcher: no-fusion -> actionable VMware error" {
  run_launcher no-fusion
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"VMware Fusion"* ]] || return 1
}

@test "launcher: absent VM -> points at docker-machine-ctl setup" {
  run_launcher absent
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"docker-machine-ctl setup"* ]] || return 1
}

@test "launcher: Container Tools missing -> install hint" {
  d="$(mktemp -d -t plf)"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  cat > "$d/docker" <<'EOF'
#!/bin/sh
case "$*" in *"inspect -f"*) echo true ;; *) : ;; esac
exit 0
EOF
  # die() now calls osascript; include a no-op stub so the restricted PATH can't
  # reach the real /usr/bin/osascript and open a blocking GUI dialog.
  printf '#!/bin/sh\nexit 0\n' > "$d/osascript"
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  # Restricted PATH: $d (no docker-machine-ctl) + system dirs ONLY -- excludes
  # /usr/local/mavergreen/bin where real Container Tools lives, so the "missing" path is genuine.
  run env DOCKER_HOST= DOCKER_CONTEXT= PATH="$d:/usr/bin:/bin" PORTHOLE_TOOLS_DIR="$d/none" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  rm -rf "$d"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"Container Tools"* ]] || return 1
}

# A Finder double-click gets launchd's PATH (/usr/bin:/bin:/usr/sbin:/sbin), which lacks the dir
# Container Tools and the docker CLI install into; the launcher must look there itself.
@test "launcher: finds Container Tools from a Finder launch's bare PATH" {
  d="$(mktemp -d -t plf)"; tools="$d/tools"; mkdir -p "$tools"
  printf '#!/bin/sh\nexit 0\n' > "$d/osascript"
  printf '#!/bin/sh\n[ "$1" = status ] && echo no-fusion\nexit 0\n' > "$tools/docker-machine-ctl"
  chmod +x "$d"/osascript "$tools"/*
  run env DOCKER_HOST= DOCKER_CONTEXT= PATH="$d:/usr/bin:/bin:/usr/sbin:/sbin" \
      PORTHOLE_TOOLS_DIR="$tools" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  rm -rf "$d"
  [[ "$output" != *"Container Tools not found"* ]] || return 1
  [[ "$output" == *"VMware Fusion"* ]] || return 1   # it reached the ctl we planted
}

@test "launcher: explicit DOCKER_HOST bypasses preflight" {
  d="$(mktemp -d -t plf)"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  cat > "$d/docker" <<'EOF'
#!/bin/sh
case "$*" in *"inspect -f"*) echo true ;; *) : ;; esac
exit 0
EOF
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  run env DOCKER_HOST=tcp://192.0.2.1:2376 PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  rm -rf "$d"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# Errors go to the app's launch window (or stderr outside it), never a modal dialog: a dialog with
# no human to dismiss it hangs the launch. tests/stubs/osascript logs any attempt to $STUB_LOG.
@test "launcher: absent VM -> an error naming the fix, and no modal dialog" {
  run_launcher absent
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"docker-machine-ctl setup"* ]] || { echo "$output"; return 1; }
  ! grep -q 'display dialog' "$STUB_LOG" || return 1
}

# A login item starts alongside Container Tools, whose VM reads "stopped" until it is running. The
# launcher starts or waits for it rather than telling you to. The ctl stub's status comes from a file
# that its start verb (or a set number of polls) moves on.
vm_stubs() {  # $1 = first status word, $2 = status after `start`
  d="$(mktemp -d -t plf)"
  echo "$1" > "$d/state"
  cat > "$d/docker-machine-ctl" <<EOF
#!/bin/sh
case "\$1" in
  status) cat "$d/state"; n=\$(( \$(cat "$d/polls" 2>/dev/null || echo 0) + 1 )); echo \$n > "$d/polls"
          if [ -f "$d/after-polls" ] && [ "\$n" -ge "\$(cat "$d/after-polls")" ]; then cat "$d/later" > "$d/state"; fi ;;
  start) echo start >> "$d/ctl.log"; echo "$2" > "$d/state" ;;
esac
EOF
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  printf '#!/bin/sh\ncase "$*" in *"inspect -f"*) echo true ;; esac\nexit 0\n' > "$d/docker"
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"
  chmod +x "$d"/*
}
launch_vm() {
  run env DOCKER_HOST= DOCKER_CONTEXT= PATH="$d:$PATH" THUNDERBIRD_VIEWER_BIN="$d/viewer" "$@" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
}

@test "launcher: a stopped VM is started, and the launch goes on" {
  vm_stubs stopped running
  launch_vm
  [ "$status" -eq 0 ] || { echo "$output"; rm -rf "$d"; return 1; }
  [[ "$output" == *"Starting the Docker VM"* ]] || { echo "$output"; rm -rf "$d"; return 1; }
  [ "$(cat "$d/ctl.log")" = start ] || { rm -rf "$d"; return 1; }
  rm -rf "$d"
}

@test "launcher: a VM being created is waited for, not started again" {
  vm_stubs creating running
  echo running > "$d/later"; echo 2 > "$d/after-polls"
  launch_vm
  [ "$status" -eq 0 ] || { echo "$output"; rm -rf "$d"; return 1; }
  [ ! -f "$d/ctl.log" ] || { rm -rf "$d"; return 1; }
  rm -rf "$d"
}

@test "launcher: a VM that never comes up is named, after the wait" {
  vm_stubs working:start working:start
  launch_vm THUNDERBIRD_VM_WAIT=0
  [ "$status" -ne 0 ] || { echo "$output"; rm -rf "$d"; return 1; }
  [[ "$output" == *"Docker VM didn't start"* ]] || { echo "$output"; rm -rf "$d"; return 1; }
  rm -rf "$d"
}
