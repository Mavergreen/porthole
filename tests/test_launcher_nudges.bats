#!/usr/bin/env bats
# platform: host-agnostic
# Generated launcher: the xpra-compat nudge, and no staleness nudge (releases rebuild apps at install).
# Mavericks: no `env -u`; set empty vars. HOME points into the temp dir so the
# once/day nudge marker is isolated per test (no cross-run suppression).
load test_helper

run_thunderbird() {  # $1 = image Created timestamp; DOCKER_HOST set -> preflight bypassed
  d="$(mktemp -d "${TMPDIR:-/tmp}/pln.XXXXXX")"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  cat > "$d/docker" <<EOF
#!/bin/sh
case "\$*" in
  *"image inspect -f"*) printf '%s\n' "\${CREATED:-}" ;;
  *"inspect -f"*) echo true ;;
  *) : ;;
esac
exit 0
EOF
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  run env DOCKER_HOST=tcp://192.0.2.1:2376 CREATED="$1" HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  rm -rf "$d"
}

# Each preset release rebuilds its app at install, so an old image is no reason to ask for --rebuild.
@test "launcher: an old container is not nudged" {
  run_thunderbird "2000-01-01T00:00:00.000000000Z"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" != *"days old"* ]] || { echo "$output"; return 1; }
}

@test "launcher --rebuild delegates a fresh build to porthole up --rebuild" {
  # The launcher no longer builds the image itself -- Porthole's `up` is the single creator, so
  # --rebuild must pass THROUGH to `porthole up --rebuild <spec>` (the porthole stub logs it).
  d="$(mktemp -d "${TMPDIR:-/tmp}/pln.XXXXXX")"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  printf '#!/bin/sh\ncase "$*" in *"inspect -f"*) echo true ;; *) : ;; esac\nexit 0\n' > "$d/docker"
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"
  chmod +x "$d"/*
  run env DOCKER_HOST=tcp://192.0.2.1:2376 PORTHOLE_LOG="$d/plog" HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird" --rebuild
  st=$status
  grep -q 'up --rebuild .*thunderbird.container' "$d/plog" || { echo plog:; cat "$d/plog" 2>/dev/null; rm -rf "$d"; return 1; }
  rm -rf "$d"
  [ "$st" -eq 0 ] || return 1
}

run_thunderbird_xpra() {  # $1 = `xpra --version` output; DOCKER_HOST set -> preflight bypassed
  d="$(mktemp -d "${TMPDIR:-/tmp}/plx.XXXXXX")"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  cat > "$d/docker" <<EOF
#!/bin/sh
case "\$*" in
  *"xpra --version"*) printf '%s\n' "\${XV:-}" ;;
  *"image inspect -f"*) echo 2999-01-01T00:00:00Z ;;
  *"inspect -f"*) echo true ;;
  *) : ;;
esac
exit 0
EOF
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  run env DOCKER_HOST=tcp://192.0.2.1:2376 XV="$1" HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  rm -rf "$d"
}

# Both cases derive from XPRA_VERSION, the one place the pin lives: a hardcoded version here would
# fail its own CI on the next xpra bump and block the very PR that is supposed to carry it.
xpra_pin_mm() { tr -d '[:space:]' < "${BATS_TEST_DIRNAME}/../XPRA_VERSION" | cut -d. -f1,2; }

@test "launcher: matching xpra major.minor is silent" {
  run_thunderbird_xpra "xpra v$(xpra_pin_mm).0-r0"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" != *"rebuild"* ]] || return 1
}

@test "launcher: mismatched xpra major.minor nudges to rebuild" {
  # One minor BELOW the pin, whatever the pin is now.
  _mm="$(xpra_pin_mm)"
  run_thunderbird_xpra "xpra v${_mm%.*}.$(( ${_mm##*.} - 1 )).0-r0"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"--rebuild"* ]] || return 1
}

# Stand-ins name each Mac caller at its own path, in a private namespace; a container that can't make
# one is said once a day in the launch log, and the app still starts. $1 = what --check does.
run_thunderbird_ns() {
  d="$(mktemp -d "${TMPDIR:-/tmp}/pls.XXXXXX")"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  cat > "$d/docker" <<EOF2
#!/bin/sh
case "\$*" in
  *"porthole-standin-at --check"*) $1 ;;
  *"image inspect -f"*) echo 2999-01-01T00:00:00Z ;;
  *"inspect -f"*) echo true ;;
  *) : ;;
esac
exit 0
EOF2
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  ns_output=$output ns_status=$status
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  ns_again=$output
  rm -rf "$d"
}
NS_MSG='porthole-standin-at: caller identity is unavailable: this container cannot create user namespaces (unshare: Operation not permitted)'

@test "launcher: a container without user namespaces is said once, and the app still starts" {
  run_thunderbird_ns "echo '$NS_MSG' >&2; exit 3"
  [ "$ns_status" -eq 0 ] || { echo "$ns_output"; return 1; }
  [[ "$ns_output" == *"thunderbird: $NS_MSG"* ]] || { echo "$ns_output"; return 1; }
  [[ "$ns_output" == *"viewer-exec"* ]] || { echo "$ns_output"; return 1; }
  [[ "$ns_again" != *"caller identity"* ]] || { echo "$ns_again"; return 1; }
}

@test "launcher: a container that can make stand-ins is silent about them" {
  run_thunderbird_ns "exit 0"
  [ "$ns_status" -eq 0 ] || { echo "$ns_output"; return 1; }
  [[ "$ns_output" != *"caller identity"* ]] || { echo "$ns_output"; return 1; }
}

@test "launcher: an image older than porthole-standin-at is silent about it" {
  run_thunderbird_ns "echo 'exec: porthole-standin-at: not found' >&2; exit 127"
  [ "$ns_status" -eq 0 ] || { echo "$ns_output"; return 1; }
  [[ "$ns_output" != *"porthole-standin-at"* ]] || { echo "$ns_output"; return 1; }
}

@test "launcher: a throttled standin-ns nudge on second launch does not abort the launcher" {
  d="$(mktemp -d "${TMPDIR:-/tmp}/pls.XXXXXX")"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  cat > "$d/docker" <<EOF2
#!/bin/sh
case "\$*" in
  *"porthole-standin-at --check"*) echo '$NS_MSG' >&2; exit 3 ;;
  *"image inspect -f"*) echo 2999-01-01T00:00:00Z ;;
  *"inspect -f"*) echo true ;;
  *) : ;;
esac
exit 0
EOF2
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  # First launch: nudge fires, stamp written.
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  [ "$status" -eq 0 ] || { echo "FAIL first launch exit $status: $output"; rm -rf "$d"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked first launch: $output"; rm -rf "$d"; return 1; }
  # Second launch same HOME: stamp exists, standin-ns nudge throttled -- must NOT abort under set -eu.
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  rm -rf "$d"
  [ "$status" -eq 0 ] || { echo "FAIL second launch exit $status (throttled standin nudge aborted launcher): $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked second launch: $output"; return 1; }
}

@test "launcher: a throttled xpra nudge on second launch does not abort the launcher" {
  _mm="$(xpra_pin_mm)"
  _bad_mm="${_mm%.*}.$(( ${_mm##*.} - 1 ))"
  d="$(mktemp -d "${TMPDIR:-/tmp}/plx.XXXXXX")"
  for b in socat docker-machine open; do printf '#!/bin/sh\nexit 0\n' > "$d/$b"; done
  cat > "$d/docker" <<EOF
#!/bin/sh
case "\$*" in
  *"xpra --version"*) printf 'xpra v${_bad_mm}.0-r0\n' ;;
  *"image inspect -f"*) echo 2999-01-01T00:00:00Z ;;
  *"inspect -f"*) echo true ;;
  *) : ;;
esac
exit 0
EOF
  chmod +x "$d"/*
  printf '#!/bin/sh\necho "viewer-exec $*"\n' > "$d/viewer"; chmod +x "$d/viewer"
  # First launch: nudge fires, stamp written.
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  [ "$status" -eq 0 ] || { echo "FAIL first launch exit $status: $output"; rm -rf "$d"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked first launch: $output"; rm -rf "$d"; return 1; }
  # Second launch same HOME: stamp exists, nudge throttled -- must NOT abort under set -eu.
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$d/home" PATH="$d:$PATH" \
      THUNDERBIRD_VIEWER_BIN="$d/viewer" \
      "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird"
  rm -rf "$d"
  [ "$status" -eq 0 ] || { echo "FAIL second launch exit $status (throttled nudge aborted launcher): $output"; return 1; }
  [[ "$output" == *"viewer-exec"* ]] || { echo "FAIL: viewer not invoked second launch: $output"; return 1; }
}
