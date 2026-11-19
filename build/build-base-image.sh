#!/bin/sh
# platform: host-agnostic
# Build the shared Porthole BASE image (ghcr.io/mavergreen/porthole-base).
#
# The ONE place the base build context is assembled and the xpra pin is read, so the CI job that
# PROVES a pin bump (.github/workflows/base-image.yml, on any PR touching base/**) and the release
# job that also PUSHES it cannot drift apart. Pushing stays with the caller: this script only builds.
#
#   usage: build-base-image.sh TAG [TAG...]     e.g. build-base-image.sh ghcr.io/…/porthole-base:latest
#
# Linux + a working `docker build` (CI runs it on ubuntu-latest for the amd64 image). Never runs on
# a 10.9 box, but stays POSIX sh like the rest of build/.
set -eu
[ $# -ge 1 ] || { echo "usage: $0 TAG [TAG...]" >&2; exit 64; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# The xpra pin. base/Dockerfile has no default for it and fails closed on an empty one, so a typo
# here cannot quietly produce an image with whatever xpra happened to be newest.
PIN="$ROOT/XPRA_VERSION"
[ -f "$PIN" ] || { echo "$0: no $PIN" >&2; exit 1; }
XPRA_VERSION=$(tr -d '[:space:]' < "$PIN")
[ -n "$XPRA_VERSION" ] || { echo "$0: $PIN is empty" >&2; exit 1; }

# The skalibs/s6 commits: the first field of line 1 of each REF file (the rest is the "# vA.B.C.D"
# tag Renovate tracks). The same pins the Mac transport is built from (build/fetch-s6.sh).
ref() {
  [ -f "$ROOT/$1" ] || { echo "$0: no $ROOT/$1" >&2; exit 1; }
  r=$(awk 'NR==1{print $1}' "$ROOT/$1")
  [ -n "$r" ] || { echo "$0: $ROOT/$1 is empty" >&2; exit 1; }
  printf '%s' "$r"
}
SKALIBS_REF=$(ref SKALIBS_REF)
S6_REF=$(ref S6_REF)

# A clean context of exactly what the image needs -- the Dockerfile plus the two assets it COPYs.
CTX=$(mktemp -d "${TMPDIR:-/tmp}/porthole-basectx.XXXXXX")
trap 'rm -rf "$CTX"' EXIT
cp "$ROOT/base/Dockerfile"          "$CTX/Dockerfile"
cp "$ROOT/menu-daemon.py"           "$CTX/porthole-menu-daemon.py"
cp "$ROOT/templates/mac-fonts.conf" "$CTX/mac-fonts.conf"

TAGS=""
for t in "$@"; do TAGS="$TAGS -t $t"; done
echo "base image: xpra $XPRA_VERSION, tags:$TAGS"
# Word-splitting $TAGS is deliberate (one -t per tag); image refs contain no spaces.
# shellcheck disable=SC2086
docker build --build-arg "XPRA_VERSION=$XPRA_VERSION" \
  --build-arg SKALIBS_REF="$SKALIBS_REF" --build-arg S6_REF="$S6_REF" $TAGS "$CTX"

# Prove the pin took. `docker build` succeeds as long as apt resolved SOMETHING, and the failure this
# guards against is precisely an install that silently resolved to a different version.
got=$(docker run --rm "$1" dpkg-query -W -f '${Version}' xpra)
[ "$got" = "$XPRA_VERSION" ] \
  || { echo "$0: built image has xpra $got, expected $XPRA_VERSION" >&2; exit 1; }
echo "base image OK: xpra $got"

# Prove the bridges' relay, in the image: binary bytes (a NUL, a 0xff) through a real Unix socket and
# back, and the client exiting once the far side closes (the server echoes only after the client's
# EOF, then closes). A relay that compiled but mangles bytes or hangs would otherwise ship.
want='p   i   n   g  \0 377   p   o   n   g'
got=$(docker run --rm "$1" sh -c '
  python3 -c "
import socket
s = socket.socket(socket.AF_UNIX); s.bind(\"/tmp/echo.sock\"); s.listen(1)
c, _ = s.accept(); d = b\"\"
while True:
    b = c.recv(4096)
    if not b: break
    d += b
c.sendall(d); c.close()" &
  while [ ! -S /tmp/echo.sock ]; do sleep 0.1; done
  printf "ping\000\377pong" | timeout 5 s6-ipcclient /tmp/echo.sock s6-ioconnect | od -An -c' | tr -s ' ' | sed 's/^ //;s/ $//')
[ "$got" = "$(printf '%s' "$want" | tr -s ' ')" ] \
  || { echo "$0: base image: s6 relay smoke failed (got: $got)" >&2; exit 1; }
echo "base image OK: s6 relay"
