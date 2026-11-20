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

# A clean context of exactly what the image needs -- the Dockerfile plus the assets it COPYs.
CTX=$(mktemp -d "${TMPDIR:-/tmp}/porthole-basectx.XXXXXX")
trap 'rm -rf "$CTX"' EXIT
cp "$ROOT/base/Dockerfile"          "$CTX/Dockerfile"
cp "$ROOT/menu-daemon.py"           "$CTX/porthole-menu-daemon.py"
cp "$ROOT/templates/mac-fonts.conf" "$CTX/mac-fonts.conf"
cp "$ROOT/base/porthole-standin.c"  "$CTX/porthole-standin.c"
cp "$ROOT/base/porthole-standin-ctl" "$CTX/porthole-standin-ctl"

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
# back, and the relay EXITING (status 0, not timeout's 124) once the far side closes -- the server
# echoes only after the client's EOF, then closes. A relay that compiled but mangles bytes or hangs
# would otherwise ship. The relay's status is checked on its own: in a pipeline it would be lost.
want='rc=0 p i n g \0 377 p o n g'
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
  n=0; while [ ! -S /tmp/echo.sock ]; do
    n=$((n + 1)); [ "$n" -le 50 ] || { echo "echo server never listened"; exit 1; }; sleep 0.1
  done
  printf "ping\000\377pong" > /tmp/in
  timeout 5 s6-ipcclient /tmp/echo.sock s6-ioconnect < /tmp/in > /tmp/out
  echo "rc=$?"; od -An -c /tmp/out' | tr -s ' \n' '  ' | sed 's/^ //;s/ $//')
[ "$got" = "$want" ] \
  || { echo "$0: base image: s6 relay smoke failed (want: $want; got: $got)" >&2; exit 1; }
echo "base image OK: s6 relay"

# Prove the stand-in, in the image: three concurrent connections through a stand-in hard-linked at a
# Mac application path WITH A SPACE all reach the agent FROM that one stand-in process -- the agent
# names its caller by the connecting peer's own executable, as 1Password does ("Allow <exe> to use
# SSH key") -- and that executable is the Mac path; then placement rules, the control script's start/alive/list/stop (xpra stubbed: it only
# starts the command), and SIGTERM removing the socket.
got=$(docker run --rm "$1" sh -c '
  fail() { echo "FAIL: $*"; exit 1; }
  python3 -c "
import socket, struct, threading
s = socket.socket(socket.AF_UNIX); s.bind(\"/tmp/agent.sock\"); s.listen(8)
out = open(\"/tmp/peers\", \"w\")
def serve(c):
    pid = struct.unpack(\"3i\", c.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))[0]
    out.write(\"%d\n\" % pid); out.flush()
    c.recv(16); c.sendall(b\"ok\"); c.close()
while True:
    c, _ = s.accept(); threading.Thread(target=serve, args=(c,)).start()" &
  n=0; while [ ! -S /tmp/agent.sock ]; do
    n=$((n + 1)); [ "$n" -le 50 ] || fail "agent never listened"; sleep 0.1
  done
  T=$(porthole-standin-ctl place "/Applications/Google Chrome.app") || fail "place a .app"
  [ "$T" = "/Applications/Google Chrome.app" ] || fail "place a .app printed: $T"
  [ "$(stat -c %i "$T")" = "$(stat -c %i /usr/local/bin/porthole-standin)" ] || fail "not a hard link"
  "$T" /tmp/x.sock /tmp/agent.sock &
  n=0; while [ ! -f /tmp/x.pid ]; do
    n=$((n + 1)); [ "$n" -le 50 ] || fail "stand-in never wrote its pid"; sleep 0.1
  done
  S=$(cat /tmp/x.pid)
  [ "$(stat -c %a /tmp/x.sock)" = 600 ] || fail "socket mode $(stat -c %a /tmp/x.sock)"
  [ "$(readlink /proc/$S/exe)" = "$T" ] || fail "stand-in exe is $(readlink /proc/$S/exe)"
  pids=
  for i in 1 2 3; do
    (printf hi | timeout 5 s6-ipcclient /tmp/x.sock sh -c "cat >&7; cat <&6" > /tmp/r$i) &
    pids="$pids $!"
  done
  for p in $pids; do wait "$p" || fail "a client exited $?"; done
  for i in 1 2 3; do [ "$(cat /tmp/r$i)" = ok ] || fail "connection $i got: $(cat /tmp/r$i)"; done
  [ "$(sort -u /tmp/peers)" = "$S" ] || fail "agent saw peers $(tr "\n" " " < /tmp/peers), not $S"
  [ "$(wc -l < /tmp/peers)" = 3 ] || fail "agent saw $(wc -l < /tmp/peers) connections"
  [ "$(porthole-standin-ctl place /usr/bin/ssh)" = /Mac/usr/bin/ssh ] || fail "place /usr/bin/ssh"
  porthole-standin-ctl place /Applications/../etc/x 2>/dev/null; [ $? = 2 ] || fail "place with .. not refused"
  porthole-standin-ctl place relative/x 2>/dev/null; [ $? = 2 ] || fail "place relative not refused"
  python3 -c "
import socket
s = socket.socket(socket.AF_UNIX); s.bind(\"/tmp/echo.sock\"); s.listen(1)
c, _ = s.accept(); d = b\"\"
while True:
    b = c.recv(65536)
    if not b: break
    d += b
c.sendall(d); c.close()" &
  n=0; while [ ! -S /tmp/echo.sock ]; do
    n=$((n + 1)); [ "$n" -le 50 ] || fail "echo server never listened"; sleep 0.1
  done
  "$T" /tmp/e.sock /tmp/echo.sock &
  n=0; while [ ! -f /tmp/e.pid ]; do
    n=$((n + 1)); [ "$n" -le 50 ] || fail "echo stand-in never wrote its pid"; sleep 0.1
  done
  { printf "\000\377"; head -c 300000 /dev/urandom; printf end; } > /tmp/big
  timeout 10 s6-ipcclient /tmp/e.sock s6-ioconnect < /tmp/big > /tmp/big.out \
    || fail "relay through the stand-in exited $?"
  cmp -s /tmp/big /tmp/big.out || fail "stand-in relay changed the bytes ($(wc -c < /tmp/big.out) of $(wc -c < /tmp/big))"
  kill -TERM "$(cat /tmp/e.pid)"
  # A far side that hangs up while the client stays open must not make the stand-in spin: its CPU
  # time stays flat while the half-open connection lingers.
  python3 -c "
import socket
s = socket.socket(socket.AF_UNIX); s.bind(\"/tmp/hup.sock\"); s.listen(8)
while True:
    c, _ = s.accept(); c.close()" &
  n=0; while [ ! -S /tmp/hup.sock ]; do
    n=$((n + 1)); [ "$n" -le 50 ] || fail "hangup server never listened"; sleep 0.1
  done
  "$T" /tmp/h.sock /tmp/hup.sock &
  n=0; while [ ! -f /tmp/h.pid ]; do
    n=$((n + 1)); [ "$n" -le 50 ] || fail "hangup stand-in never wrote its pid"; sleep 0.1
  done
  H=$(cat /tmp/h.pid)
  (sleep 3 | s6-ipcclient /tmp/h.sock sh -c "cat >&7" ) &
  sleep 0.5
  t0=$(awk "{print \$14 + \$15}" /proc/$H/stat); sleep 1.5; t1=$(awk "{print \$14 + \$15}" /proc/$H/stat)
  [ $((t1 - t0)) -le 10 ] || fail "stand-in spun with a half-open connection: $((t1 - t0)) ticks in 1.5 s"
  kill -TERM "$H"
  # alive trusts a pid only if it is that stand-in: a reused pid (here: sleep) is not alive.
  mkdir -p /run/user/1000/porthole-standin
  sleep 30 & Z=$!
  python3 -c "import socket; socket.socket(socket.AF_UNIX).bind(\"/run/user/1000/porthole-standin/9-9.x.sock\")"
  echo "$Z" > /run/user/1000/porthole-standin/9-9.x.pid
  ! porthole-standin-ctl alive 9-9.x || fail "alive trusted a reused pid"
  kill "$Z"; rm -f /run/user/1000/porthole-standin/9-9.x.*
  kill -TERM "$S"; sleep 0.3
  [ ! -e /tmp/x.sock ] && [ ! -e /tmp/x.pid ] || fail "SIGTERM left the socket or pid file"
  mkdir -p /tmp/stub && printf "#!/bin/sh\nshift 3\nsetsid \"\$@\" </dev/null >/dev/null 2>&1 &\n" \
    > /tmp/stub/xpra && chmod 755 /tmp/stub/xpra
  PATH=/tmp/stub:$PATH porthole-standin-ctl start 42-7.ssh-agent "$T" /tmp/agent.sock \
    || fail "ctl start"
  porthole-standin-ctl alive 42-7.ssh-agent || fail "ctl alive after start"
  [ "$(porthole-standin-ctl list)" = 42-7.ssh-agent ] || fail "ctl list: $(porthole-standin-ctl list)"
  porthole-standin-ctl stop 42-7.ssh-agent; sleep 0.3
  ! porthole-standin-ctl alive 42-7.ssh-agent || fail "alive after stop"
  [ -z "$(porthole-standin-ctl list)" ] || fail "list after stop"
  porthole-standin-ctl alive ../x 2>/dev/null; [ $? = 2 ] || fail "a SID with / not refused"
  echo standin-ok' 2>&1) || :
[ "$got" = standin-ok ] \
  || { echo "$0: base image: stand-in smoke failed: $got" >&2; exit 1; }
echo "base image OK: stand-in"
