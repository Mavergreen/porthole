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

configure() {
  # A shipyard older than its toolchain file is found but cannot configure this project. That is a
  # stale install, not a platform limit, so say so and fail rather than skip.
  [ -f "$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake" ] || {
    echo "the shipyard at $SHIPYARD_SCRIPTS predates MavericksToolchain.cmake -- install the current shipyard pkg"; return 1; }
  run shipyard-cmake -S "$REPO_ROOT" -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/cmake/MavericksClang22Toolchain.cmake" \
    -DMAVERICKS_CLANG22_PIN="$REPO_ROOT/components/clang22" "$@"
}

@test "porthole configures as a standalone top-level project, with the pinned clang22" {
  configure
  [ "$status" -eq 0 ] || { echo "shipyard-cmake configure failed (status $status):"; echo "$output"; return 1; }
  root="$(sh "$SHIPYARD_SCRIPTS/fetch_clang22.sh" "$REPO_ROOT/components/clang22" 2>/dev/null)"
  # A toolchain file's compiler is not cached; CMake records what detection ran here.
  grep -qF "set(CMAKE_OBJC_COMPILER \"$root/bin/clang\")" "$BUILD_DIR"/CMakeFiles/*/CMakeOBJCCompiler.cmake \
    || { echo "OBJC compiler is not the pinned clang22 ($root/bin/clang):"; grep -h 'set(CMAKE_OBJC_COMPILER ' "$BUILD_DIR"/CMakeFiles/*/CMakeOBJCCompiler.cmake; return 1; }
  grep -qF "set(CMAKE_C_COMPILER \"$root/bin/clang\")" "$BUILD_DIR"/CMakeFiles/*/CMakeCCompiler.cmake \
    || { echo "C compiler is not the pinned clang22 ($root/bin/clang):"; grep -h 'set(CMAKE_C_COMPILER ' "$BUILD_DIR"/CMakeFiles/*/CMakeCCompiler.cmake; return 1; }
}

@test "a compiler other than the pinned clang22 is refused at configure" {
  configure -DCMAKE_OBJC_COMPILER=/usr/bin/clang
  [ "$status" -ne 0 ] || { echo "configure accepted /usr/bin/clang"; return 1; }
  echo "$output" | grep -q "pinned clang22" || { echo "$output"; return 1; }
}

@test "a relative MAVERICKS_CLANG22_PIN still configures (try_compile runs elsewhere)" {
  cd "$REPO_ROOT"
  run shipyard-cmake -S "$REPO_ROOT" -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/cmake/MavericksClang22Toolchain.cmake" \
    -DMAVERICKS_CLANG22_PIN=components/clang22
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a build dir whose detected compiler is no longer the pinned clang22 refuses to reconfigure" {
  configure
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # Model a pin change on a reused build dir: CMake keeps the compiler it detected before (here the same
  # binary under another path, as the installed clang22 vs the fetched pin would be).
  root="$(sh "$SHIPYARD_SCRIPTS/fetch_clang22.sh" "$REPO_ROOT/components/clang22" 2>/dev/null)"
  mkdir -p "$BUILD_DIR/other/bin"; ln -s "$root/bin/clang" "$BUILD_DIR/other/bin/clang"
  for f in "$BUILD_DIR"/CMakeFiles/*/CMakeOBJCCompiler.cmake; do
    sed -i.bak "s#set(CMAKE_OBJC_COMPILER \"$root/bin/clang\")#set(CMAKE_OBJC_COMPILER \"$BUILD_DIR/other/bin/clang\")#" "$f"
  done
  configure
  [ "$status" -ne 0 ] || { echo "reconfigure accepted a compiler other than $root/bin/clang"; return 1; }
  echo "$output" | grep -q "delete the build directory" || { echo "$output"; return 1; }
}
