#!/bin/sh
# platform: host-agnostic
# Porthole compiles with the family's clang22 (mavergreen-conventions: "Products build with clang22 on
# every host"), at the release components/clang22/version pins, which Renovate moves.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "$@" >&2; exit 1; }
V="$ROOT/components/clang22/version"
[ -f "$V" ] || fail "components/clang22/version: missing (the clang22 pin)"
grep -qE '^22\.[0-9]+\.[0-9]+-mavericks\.[0-9]+$' "$V" \
  || fail "components/clang22/version: '$(cat "$V")' is not a clang-22 release tag (22.X.Y-mavericks.N)"
grep -qF '"/^components/clang22/version$/"' "$ROOT/.github/renovate.json" \
  || fail ".github/renovate.json: no manager for components/clang22/version"
grep -qF '"Mavergreen/clang-22"' "$ROOT/.github/renovate.json" \
  || fail ".github/renovate.json: the clang22 pin must track Mavergreen/clang-22 releases"
grep -qF 'components/clang22/version' "$ROOT/INGREDIENTS.md" \
  || fail "INGREDIENTS.md: does not declare clang22 (components/clang22/version)"
# Everything Mac-side compiles with it: the s6 transport build and CI's configure.
grep -q 'fetch_clang22.sh' "$ROOT/build/fetch-s6.sh" \
  || fail "build/fetch-s6.sh: must compile with the pinned clang22 (fetch_clang22.sh), not a PATH clang"
if grep -qE '^CC="clang ' "$ROOT/build/fetch-s6.sh"; then
  fail "build/fetch-s6.sh: still compiles with a bare PATH clang"
fi
grep -qE -- '--preset (cross|native)|MavericksClang22Toolchain\.cmake' "$ROOT/.github/workflows/release.yml" \
  || fail ".github/workflows/release.yml: configures without the clang22 toolchain (use --preset cross)"
# skarnet's Makefiles assign AR/RANLIB/STRIP with :=, so only make's command line can set them.
[ "$(grep -cE '^make .*AR="\$AR" RANLIB="\$RANLIB" STRIP=' "$ROOT/build/fetch-s6.sh")" -ge 4 ] \
  || fail "build/fetch-s6.sh: every make (build and install, skalibs and s6) must pass clang22's AR/RANLIB/STRIP"
# A clang22 bump must rebuild the transport.
grep -A6 'OUTPUT "${PORTHOLE_TRANSPORT_STAMP}"' "$ROOT/CMakeLists.txt" | grep -qF 'components/clang22/version' \
  || fail "CMakeLists.txt: the transport does not depend on components/clang22/version"
# CI restores the clang22 cache before anything (the tests included) fetches it.
WF="$ROOT/.github/workflows/release.yml"
c=$(grep -n 'Cache the pinned clang22' "$WF" | cut -d: -f1); t=$(grep -n "Run the repo's tests" "$WF" | cut -d: -f1)
[ -n "$c" ] && [ -n "$t" ] && [ "$c" -lt "$t" ] \
  || fail "release.yml: restore the clang22 cache before 'Run the repo's tests' (which fetches clang22)"
echo "clang22 pin: ok"
