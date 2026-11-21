#!/usr/bin/env bats
# platform: host-agnostic
# Generated launcher: check_gui_resources() advisory nudge for Retina VM resources.
# Consumes Task 1's docker-machine-ctl resource-status interface via PORTHOLE_RESOURCE_CTL.
# Mavericks: no `env -u`; set empty vars. HOME points into temp dir so once/day stamp is isolated.
load test_helper

# ---------------------------------------------------------------------------
# Helper: create a minimal launcher environment and run thunderbird.
#
# $1 = what the resource-ctl prints on `resource-status` (multi-line ok; default "unknown")
# $2 = exit code for resource-ctl resource-status (default 0)
#
# Sets PORTHOLE_RESOURCE_CTL to a fresh stub in a temp dir.
# Sets DOCKER_HOST so the VM preflight is bypassed (not what we are testing here).
# Writes the output to <dir>/res-out; the stub cats it. Exit code is embedded in stub.
# ---------------------------------------------------------------------------
run_thunderbird_res() {
  _res_exit="${2:-0}"
  d="$(mktemp -d -t res)"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; chmod +x "$d/$b"; done
  cat > "$d/docker" <<'EOF'
#!/bin/sh
printf 'docker %s\n' "$*" >> "$(dirname "$0")/docker-calls"
case "$*" in *"inspect -f"*) echo true ;; *) : ;; esac
exit 0
EOF
  cat > "$d/docker-machine-ctl" <<'EOF'
#!/bin/sh
[ "$1" = status ] && { echo running; exit 0; }
exit 0
EOF
  printf '%s\n' "${1:-unknown}" > "$d/res-out"
  # Embed exit code and dir at stub-creation time (heredoc expands $_res_exit and $d).
  # $1 and $0 in the stub are escaped so they evaluate at stub run time.
  cat > "$d/resource-ctl" <<STUB
#!/bin/sh
[ "\$1" = resource-status ] && { cat "$d/res-out"; exit $_res_exit; }
printf 'Usage: resource-ctl\\n' >&2; exit 2
STUB
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  _saved_d="$d"
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      PORTHOLE_RESOURCE_CTL="$d/resource-ctl" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  # Keep docker-calls accessible to callers that need it, but clean up after assertions.
  _docker_calls="$d/docker-calls"
  rm -rf "$d"
}

# ---------------------------------------------------------------------------
# 1. Low resources (1024 MiB / 1 vCPU): advice fires, viewer still invoked.
# ---------------------------------------------------------------------------
@test "launcher: 1024 MiB/1 vCPU produces advice containing '2 GiB' and 'two vCPUs'" {
  run_thunderbird_res $'memory_mib=1024\nvcpus=1\nsource=vmx'
  [ "$status" -eq 0 ] || { echo "exit $status: $output"; return 1; }
  [[ "$output" == *"2 GiB"* ]] || { echo "FAIL: missing '2 GiB' in output: $output"; return 1; }
  [[ "$output" == *"two vCPUs"* ]] || { echo "FAIL: missing 'two vCPUs' in output: $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked: $output"; return 1; }
}

# ---------------------------------------------------------------------------
# 2. At baseline (2048 MiB / 2 vCPUs): no nudge.
# ---------------------------------------------------------------------------
@test "launcher: 2048 MiB/2 vCPUs at baseline produces no low-resource nudge" {
  run_thunderbird_res $'memory_mib=2048\nvcpus=2\nsource=driver'
  [ "$status" -eq 0 ] || { echo "exit $status: $output"; return 1; }
  [[ "$output" != *"2 GiB"* ]] || { echo "FAIL: unexpected resource nudge in: $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked: $output"; return 1; }
}

# ---------------------------------------------------------------------------
# 3. Above baseline (4096 MiB / 2 vCPUs): no nudge.
# ---------------------------------------------------------------------------
@test "launcher: 4096 MiB/2 vCPUs above baseline produces no low-resource nudge" {
  run_thunderbird_res $'memory_mib=4096\nvcpus=2\nsource=vmx'
  [ "$status" -eq 0 ] || { echo "exit $status: $output"; return 1; }
  [[ "$output" != *"2 GiB"* ]] || { echo "FAIL: unexpected resource nudge in: $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked: $output"; return 1; }
}

# ---------------------------------------------------------------------------
# 4. Older ctl (exits 2 with usage text): launch succeeds, no false resource claim.
# ---------------------------------------------------------------------------
@test "launcher: older ctl returning usage/2 launches successfully without resource claim" {
  run_thunderbird_res "Usage: docker-machine-ctl" 2
  [ "$status" -eq 0 ] || { echo "exit $status: $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked: $output"; return 1; }
  [[ "$output" != *"two vCPUs"* ]] || { echo "FAIL: false resource claim in: $output"; return 1; }
}

# ---------------------------------------------------------------------------
# 5. Missing ctl (not on PATH, PORTHOLE_RESOURCE_CTL not set): launch succeeds.
# ---------------------------------------------------------------------------
@test "launcher: missing resource ctl launches successfully" {
  d="$(mktemp -d -t res)"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; chmod +x "$d/$b"; done
  cat > "$d/docker" <<'EOF'
#!/bin/sh
case "$*" in *"inspect -f"*) echo true ;; *) : ;; esac
exit 0
EOF
  # No docker-machine-ctl: preflight bypassed via DOCKER_HOST; resource check finds nothing.
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  rm -rf "$d"
  [ "$status" -eq 0 ] || { echo "exit $status: $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked: $output"; return 1; }
}

# ---------------------------------------------------------------------------
# 6. 'unknown' output: launch succeeds, no false resource claim.
# ---------------------------------------------------------------------------
@test "launcher: 'unknown' resource-status output launches successfully" {
  run_thunderbird_res "unknown"
  [ "$status" -eq 0 ] || { echo "exit $status: $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked: $output"; return 1; }
  [[ "$output" != *"two vCPUs"* ]] || { echo "FAIL: false resource claim in: $output"; return 1; }
}

# ---------------------------------------------------------------------------
# 7. Malformed / extra values: launch succeeds, no false resource claim.
# ---------------------------------------------------------------------------
@test "launcher: malformed resource-status output launches successfully" {
  run_thunderbird_res $'memory_mib=abc\nvcpus=1\nsource=vmx'
  [ "$status" -eq 0 ] || { echo "exit $status: $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked: $output"; return 1; }
  [[ "$output" != *"two vCPUs"* ]] || { echo "FAIL: false resource claim on malformed: $output"; return 1; }
}

@test "launcher: extra lines in resource-status output launch successfully" {
  run_thunderbird_res $'memory_mib=1024\nvcpus=1\nsource=vmx\nextra=line'
  [ "$status" -eq 0 ] || { echo "exit $status: $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked: $output"; return 1; }
}

# ---------------------------------------------------------------------------
# 8. Nudge fires only once per day (second run within the same day is silent).
# ---------------------------------------------------------------------------
@test "launcher: low-resource advice fires only once per day" {
  d="$(mktemp -d -t res)"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; chmod +x "$d/$b"; done
  cat > "$d/docker" <<'EOF'
#!/bin/sh
case "$*" in *"inspect -f"*) echo true ;; *) : ;; esac
exit 0
EOF
  cat > "$d/docker-machine-ctl" <<'EOF'
#!/bin/sh
[ "$1" = status ] && { echo running; exit 0; }
exit 0
EOF
  printf 'memory_mib=1024\nvcpus=1\nsource=vmx\n' > "$d/res-out"
  cat > "$d/resource-ctl" <<STUB
#!/bin/sh
[ "\$1" = resource-status ] && { cat "$d/res-out"; exit 0; }
printf 'Usage: resource-ctl\\n' >&2; exit 2
STUB
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  # First run: advice expected.
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      PORTHOLE_RESOURCE_CTL="$d/resource-ctl" THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  _first="$output"
  # Second run same HOME: nudge marker exists -> silence.
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      PORTHOLE_RESOURCE_CTL="$d/resource-ctl" THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  _second="$output"
  rm -rf "$d"
  [[ "$_first" == *"2 GiB"* ]] || { echo "FAIL: first run missing advice: $_first"; return 1; }
  [[ "$_second" != *"2 GiB"* ]] || { echo "FAIL: second run should not repeat advice: $_second"; return 1; }
}

# ---------------------------------------------------------------------------
# 9. No docker stop/rm/recreate/machine-resource edits during resource check.
# ---------------------------------------------------------------------------
@test "launcher: check_gui_resources does not invoke docker stop, rm, or recreate" {
  d="$(mktemp -d -t res)"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; chmod +x "$d/$b"; done
  cat > "$d/docker" <<'EOF'
#!/bin/sh
printf 'docker %s\n' "$*" >> "$(dirname "$0")/docker-calls"
case "$*" in *"inspect -f"*) echo true ;; *) : ;; esac
exit 0
EOF
  cat > "$d/docker-machine-ctl" <<'EOF'
#!/bin/sh
[ "$1" = status ] && { echo running; exit 0; }
exit 0
EOF
  printf 'memory_mib=1024\nvcpus=1\nsource=vmx\n' > "$d/res-out"
  cat > "$d/resource-ctl" <<STUB
#!/bin/sh
[ "\$1" = resource-status ] && { cat "$d/res-out"; exit 0; }
printf 'Usage: resource-ctl\\n' >&2; exit 2
STUB
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      PORTHOLE_RESOURCE_CTL="$d/resource-ctl" THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  _rc="$status"
  if grep -qE '^docker (stop|rm|run|create)' "$d/docker-calls" 2>/dev/null; then
    echo "FAIL: destructive docker call found:"
    cat "$d/docker-calls"
    rm -rf "$d"; return 1
  fi
  rm -rf "$d"
  [ "$_rc" -eq 0 ] || { echo "exit $_rc"; return 1; }
}
