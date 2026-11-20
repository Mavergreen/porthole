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
echo "clang22 pin: ok"
