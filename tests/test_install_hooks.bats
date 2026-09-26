#!/usr/bin/env bats
# platform: host-agnostic
# Porthole's installer hooks. Porthole runs every app in a container, so it is the one product that
# requires Container Tools; the presets require only Porthole.
REPO="$BATS_TEST_DIRNAME/.."
setup() { WORK="$(mktemp -d "${TMPDIR:-/tmp}/porthole-hooks.XXXXXX")"; }
teardown() { rm -rf "$WORK"; }

@test "preinstall refuses a volume without Container Tools, naming it" {
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/preinstall-hook.sh"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"Porthole needs Container Tools for Mavericks installed first"* ]] || { echo "$output"; return 1; }
}

@test "preinstall asks to update an old Container Tools rather than to install one" {
  mkdir -p "$WORK/v/usr/local/bin"; : > "$WORK/v/usr/local/bin/docker-machine"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/preinstall-hook.sh"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"update Container Tools for Mavericks to 20260727-mavericks.30 or later"* ]] || { echo "$output"; return 1; }
}

@test "preinstall accepts a volume with Container Tools, and reads only that volume" {
  mkdir -p "$WORK/v/usr/local/mavergreen/container-tools"; : > "$WORK/v/usr/local/mavergreen/container-tools/mavergreen.plist"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/preinstall-hook.sh"
  [ "$status" -eq 0 ]
}

@test "the package runs the preinstall hook" {
  grep -q -- '--preinstall-hook "$HERE/preinstall-hook.sh"' "$REPO/packaging/macos/build_pkg.sh"
}
