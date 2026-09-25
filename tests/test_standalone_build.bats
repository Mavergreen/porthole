#!/usr/bin/env bats
# platform: host-agnostic
# Guard: porthole builds as its OWN top-level project. `shipyard-cmake -S <root> -B <tmp>`
# must configure with no product repo and no container -- the regression guard against
# re-coupling this root to a parent's project()/find_package(MavericksShipyard).
load test_helper

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  # Without shipyard-cmake nothing here can configure at all: skip rather than fail (mirrors the
  # sibling suites' exit-77 guard). msc.sh gives us SHIPYARD_SCRIPTS to point the toolchain-file
  # backstop at MavericksToolchain.cmake; it `return`s non-zero if it can't locate shipyard either,
  # which must skip the test too, never fail it.
  command -v shipyard-cmake >/dev/null 2>&1 || skip "no shipyard-cmake installed"
  . "$REPO_ROOT/build/msc.sh" || skip "msc.sh could not locate shipyard"
  # BSD mktemp (macOS 10.9) requires an explicit template.
  BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/porthole-standalone.XXXXXX")"
}

teardown() {
  # setup may skip (no shipyard-cmake / msc.sh) before BUILD_DIR is ever set; a bare unset check
  # would then exit teardown non-zero and turn the skip into a failure.
  [ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"
  true
}

@test "porthole configures as a standalone top-level project" {
  # A shipyard older than its toolchain file is found but cannot configure this project. That is a
  # stale install, not a platform limit, so say so and fail rather than skip.
  [ -f "$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake" ] || {
    echo "the shipyard at $SHIPYARD_SCRIPTS predates MavericksToolchain.cmake -- install the current shipyard pkg"; return 1; }
  run shipyard-cmake -S "$REPO_ROOT" -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake"
  [ "$status" -eq 0 ] || { echo "shipyard-cmake configure failed (status $status):"; echo "$output"; return 1; }
}
