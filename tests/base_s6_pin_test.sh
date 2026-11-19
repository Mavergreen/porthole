#!/bin/sh
# platform: host-agnostic
# The base image carries the container side of every Porthole bridge: s6-ipcclient + s6-ioconnect,
# built from the SAME skalibs/s6 commits the Mac transport is built from (SKALIBS_REF, S6_REF), so
# one Renovate PR moves both ends. socat is gone from the image: nothing in it relays with socat.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DF="$ROOT/base/Dockerfile"
BUILD="$ROOT/build/build-base-image.sh"
WF="$ROOT/.github/workflows/base-image.yml"
fail() { echo "$@" >&2; exit 1; }
DFI=$(mktemp "${TMPDIR:-/tmp}/base-s6-dfi.XXXXXX"); trap 'rm -f "$DFI"' EXIT
sed -e 's/#.*//' -e 's/@sha256:[0-9a-f]\{64\}//' "$DF" > "$DFI"

for v in SKALIBS_REF S6_REF; do
  grep -qE "^ARG $v\$" "$DFI" || fail "base/Dockerfile: no 'ARG $v' (the commit arrives as a build arg)"
  grep -qF "\${$v:?" "$DFI" || fail "base/Dockerfile: must fail closed when $v is empty (\${$v:?...})"
  grep -qF -- "--build-arg $v=" "$BUILD" || fail "build/build-base-image.sh: does not pass --build-arg $v="
  [ "$(grep -c "^ *- '$v'\$" "$WF")" -ge 2 ] \
    || fail ".github/workflows/base-image.yml: $v must be in both paths: blocks (a bump must rebuild the base)"
done
grep -qF 'https://github.com/skarnet/skalibs.git' "$DFI" || fail "base/Dockerfile: does not fetch skalibs from skarnet"
grep -qF 'https://github.com/skarnet/s6.git' "$DFI" || fail "base/Dockerfile: does not fetch s6 from skarnet"
if grep -qE '[0-9a-f]{40}' "$DFI"; then
  fail "base/Dockerfile: carries a literal commit; skalibs/s6 commits must come from SKALIBS_REF/S6_REF"
fi
for b in s6-ipcclient s6-ioconnect; do
  grep -qE "^COPY --from=[a-z0-9]+ .*/$b( |\$)" "$DFI" \
    || fail "base/Dockerfile: the final image does not COPY $b from the s6 build stage"
done
grep -qE '^COPY --from=[a-z0-9]+ .* /usr/local/bin/$' "$DFI" \
  || fail "base/Dockerfile: the s6 binaries must land in /usr/local/bin/"
if grep -qw socat "$DFI"; then
  fail "base/Dockerfile: still installs socat (the bridges relay with s6 now)"
fi
echo "base s6 pin: ok"
