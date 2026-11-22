#!/bin/sh
# platform: host-agnostic -- drives docker; the containers it checks are Linux
# standin_ns_test.sh IMAGE | --local -- porthole-standin-at puts a stand-in at the Mac path itself.
#
# Starts IMAGE the way `porthole up` starts an app's container (--init, seccomp=unconfined) and
# checks each placement from OUTSIDE the stand-in's namespace, where 1Password looks: the stand-in's
# exe reads the Mac path, and the container's own files are unchanged. A second container, started
# with Docker's default seccomp, shows the failure is loud and specific.
#
# --local builds a throwaway image from base/*.c (no xpra), for a developer box; CI passes the base
# image it just built. Both images and containers are removed on exit.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[ $# -eq 1 ] || { echo "usage: $0 IMAGE | --local" >&2; exit 64; }
C=porthole-nstest-$$ C2=porthole-nstest-$$-default IMAGE=$1 LOCAL=
cleanup() {
  docker rm -f "$C" "$C2" >/dev/null 2>&1 || :
  [ -z "$LOCAL" ] || docker rmi "$IMAGE" >/dev/null 2>&1 || :
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

if [ "$IMAGE" = --local ]; then
  IMAGE=porthole-standin-nstest:$$ LOCAL=1
  ctx=$(mktemp -d "${TMPDIR:-/tmp}/porthole-nstest.XXXXXX")
  cp "$ROOT/base/porthole-standin.c" "$ROOT/base/porthole-standin-at.c" "$ctx/"
  cat > "$ctx/Dockerfile" <<'EOF'
FROM debian:13-slim AS cc
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev
COPY porthole-standin.c porthole-standin-at.c /src/
RUN gcc -O2 -Wall -Werror -o /porthole-standin /src/porthole-standin.c \
 && gcc -O2 -Wall -Werror -o /porthole-standin-at /src/porthole-standin-at.c
FROM debian:13-slim
COPY --from=cc /porthole-standin /porthole-standin-at /usr/local/bin/
RUN mkdir -p /usr/local/lib/porthole-standin/mnt
EOF
  docker build -q -t "$IMAGE" "$ctx" >/dev/null || { rm -rf "$ctx"; fail "could not build $IMAGE"; }
  rm -rf "$ctx"
fi

docker run -d --name "$C" --init --security-opt seccomp=unconfined --entrypoint sleep "$IMAGE" infinity >/dev/null
docker run -d --name "$C2" --init --entrypoint sleep "$IMAGE" infinity >/dev/null
x() { docker exec -u 0 "$C" "$@"; }   # outside the namespace, as root
# A stand-in's /proc/PID/exe is read as its own user, the way 1Password reads it: Docker's default
# root has no CAP_SYS_PTRACE, so another uid may not.
sum() { docker exec -u "${2:-0}" "$C" sh -c 'sha256sum < "$1" | cut -c1-64' sh "$1"; }
STANDIN_SUM=$(sum /usr/local/bin/porthole-standin)

# at USER PATH: start the stand-in at PATH as USER, wait until it listens, print its pid.
at() {
  x rm -f /tmp/t.sock /tmp/t.pid
  docker exec -d -u "$1" "$C" porthole-standin-at "$2" /tmp/t.sock /nonexistent
  n=0
  until x test -s /tmp/t.pid; do
    n=$((n + 1)); [ "$n" -le 50 ] || fail "no stand-in came up at '$2' as $1"; sleep 0.1
  done
  x cat /tmp/t.pid
}
field() { x awk -v k="$2:" '$1 == k { print $2 }' "/proc/$1/status"; }

# seen PATH: a stand-in at PATH is seen there from outside, by its own user, and is the stand-in.
seen() {
  pid=$(at 1000:1001 "$1")
  got=$(docker exec -u 1000:1001 "$C" readlink "/proc/$pid/exe") || fail "cannot read $1's exe"
  [ "$got" = "$1" ] || fail "stand-in at '$1' is seen as '$got'"
  [ "$(sum "/proc/$pid/exe" 1000:1001)" = "$STANDIN_SUM" ] || fail "'$1' does not run the stand-in"
  [ "$(field "$pid" Uid)/$(field "$pid" Gid)" = 1000/1001 ] || fail "'$1' does not run as 1000:1001"
  x sh -c 'kill "$1"' sh "$pid"
  echo "ok: $1"
}

perl_sum=$(sum /usr/bin/perl)
seen /usr/bin/perl                                   # (a) a file the container has
[ "$(sum /usr/bin/perl)" = "$perl_sum" ] || fail "the container's /usr/bin/perl changed"
seen "/Applications/Google Chrome.app"               # (b) a path under / the container lacks
x test ! -e /Applications || fail "/Applications appeared in the container"
seen /opt/pkg/bin/tmux                               # (c) a path under a directory it has
x test ! -e /opt/pkg || fail "/opt/pkg appeared in the container"
seen /bin/zsh                                        # (d) through a container symlink (/bin -> usr/bin)
x test -L /bin || fail "/bin is no longer a symlink"
seen /usr/bin/awk                                    # (e) a path that is a symlink in the container
x test -L /usr/bin/awk || fail "/usr/bin/awk is no longer a symlink"

for p in rel/path /a/../b /a/./b /a/ /a//b /; do      # (f) refused
  rc=0; docker exec -u 1000:1001 "$C" porthole-standin-at "$p" /tmp/t.sock /nonexistent 2>/dev/null || rc=$?
  [ "$rc" = 2 ] || fail "'$p' was not refused (exit $rc)"
done
echo "ok: refuses bad paths"

docker exec -u 1000:1001 "$C" porthole-standin-at --check || fail "--check fails as Porthole runs it"   # (h)
rc=0; msg=$(docker exec -u 1000:1001 "$C2" porthole-standin-at --check 2>&1) || rc=$?                   # (i)
[ "$rc" = 3 ] || fail "--check under Docker's default seccomp exited $rc: $msg"
case $msg in "porthole-standin-at: caller identity is unavailable: this container cannot create user namespaces ("*")") ;;
  *) fail "--check under Docker's default seccomp said: $msg" ;; esac
x rmdir /usr/local/lib/porthole-standin/mnt                                                             # (g)
rc=0; msg=$(docker exec -u 1000:1001 "$C" porthole-standin-at --check 2>&1) || rc=$?
x mkdir /usr/local/lib/porthole-standin/mnt
[ "$rc" = 4 ] || fail "--check without its mount point exited $rc: $msg"
case $msg in *"caller identity is unavailable"*) fail "a missing mount point blamed user namespaces: $msg" ;; esac
echo "ok: --check"

pid=$(at 1000:0 "/Applications/Google Chrome.app")                                                     # (j)
[ "$(field "$pid" Uid)/$(field "$pid" Gid)" = 1000/0 ] || fail "a 1000:0 stand-in does not run as 1000:0"
x sh -c 'kill "$1"' sh "$pid"
echo "ok: runs as who started it"

out=$(mktemp "${TMPDIR:-/tmp}/porthole-nstest.XXXXXX")                                                 # (k)
printf 'hello\n' | docker exec -i -u 1000:0 "$C" porthole-standin-at "/Applications/Google Chrome.app" \
  --run sh -c 'cat; sleep 3' > "$out" &
n=0 rpid=
while [ -z "$rpid" ]; do
  n=$((n + 1)); [ "$n" -le 50 ] || fail "--run never started"; sleep 0.1
  rpid=$(x sh -c 'for p in /proc/[0-9]*; do
    tr "\000" " " < "$p/cmdline" 2>/dev/null | grep -q "^/Applications/Google Chrome.app --run " && echo "${p#/proc/}"
  done; :')
done
[ "$(docker exec -u 1000:0 "$C" readlink "/proc/$rpid/exe")" = "/Applications/Google Chrome.app" ] || fail "--run's stand-in is not seen at its Mac path"
x sh -c 'for p in /proc/[0-9]*; do awk -v k="$1" '"'"'$1 == "PPid:" && $2 == k { f = 1 } END { exit !f }'"'"' "$p/status" 2>/dev/null && exit 0; done; exit 1' sh "$rpid" \
  || fail "--run's program is not the stand-in's child"
wait
[ "$(cat "$out")" = hello ] || fail "--run did not pass stdin/stdout through: $(cat "$out")"
rm -f "$out"
echo "ok: --run"

# --as UID:GID: started as root, the namespace holds every user and group, and the stand-in becomes
# UID:GID before anything runs. 1Password's browser helper is set-group-ID and quits unless the kernel
# really changed its group, which it can't for a group a namespace doesn't hold.
x sh -c 'cp /usr/bin/id /tmp/sgid-id && chgrp 1001 /tmp/sgid-id && chmod 2755 /tmp/sgid-id'           # (l)
asrun() { docker exec -i -u 0 "$C" porthole-standin-at --as 1000:0 "/Applications/Google Chrome.app" --run "$@" </dev/null; }
[ "$(asrun /tmp/sgid-id -g)" = 1001 ] || fail "a set-group-ID program under --as did not change group: egid $(asrun /tmp/sgid-id -g)"
[ "$(asrun /tmp/sgid-id -rg)/$(asrun /tmp/sgid-id -u)" = 0/1000 ] || fail "under --as, a program's real ids are not 1000:0"
echo "ok: --as: a set-group-ID program changes group"

x rm -f /tmp/t.sock /tmp/t.pid                                                                          # (m)
docker exec -d -u 0 "$C" porthole-standin-at --as 1000:0 "/Applications/Google Chrome.app" /tmp/t.sock /nonexistent
n=0; until x test -s /tmp/t.pid; do n=$((n + 1)); [ "$n" -le 50 ] || fail "no --as stand-in came up"; sleep 0.1; done
pid=$(x cat /tmp/t.pid)
st=$(x cat "/proc/$pid/status")
line() { printf '%s\n' "$st" | awk -v k="$1:" '$1 == k { $1 = ""; sub(/^ /, ""); print }'; }
[ "$(line Uid)" = "1000 1000 1000 1000" ] || fail "--as stand-in's uids: $(line Uid)"
[ "$(line Gid)" = "0 0 0 0" ] || fail "--as stand-in's gids: $(line Gid)"
[ "$(line Groups)" = 0 ] || fail "--as stand-in's groups: $(line Groups)"
for c in CapInh CapPrm CapEff CapAmb; do [ "$(line $c)" = 0000000000000000 ] || fail "--as stand-in keeps $c $(line $c)"; done
# The namespace is root's, so only a process with CAP_SYS_PTRACE (root here; 1Password with PTRACE=yes)
# reads inside it, and uid 1000 can't enter it: inside, every id is mapped, so entering it would be root.
[ "$(x readlink "/proc/$pid/exe")" = "/Applications/Google Chrome.app" ] || fail "--as stand-in is not seen at its Mac path"
! docker exec -u 1000:0 "$C" nsenter -U -t "$pid" true 2>/dev/null || fail "uid 1000 can enter a --as stand-in's namespace"
x sh -c 'kill "$1"' sh "$pid"
echo "ok: --as: no root left in the stand-in, and its namespace is closed to uid 1000"

rc=0; docker exec -u 1000:1001 "$C" porthole-standin-at --as 1000:0 /x/y 2>/dev/null || rc=$?               # (n)
[ "$rc" = 2 ] || fail "--as not started as root was not refused (exit $rc)"
for a in onepassword 1000 1000: :0 0:0 0:1001 1000:x -1:0; do
  rc=0; docker exec -u 0 "$C" porthole-standin-at --as "$a" /x/y 2>/dev/null || rc=$?
  [ "$rc" = 2 ] || fail "--as '$a' was not refused (exit $rc)"
done
echo "ok: --as refuses non-root starts and bad or root targets"

# --as also leaves the stand-in at a Mac path the container lacks, seen from outside: 1Password's app
# opens its browser helper's parent by the path its exe reads, from outside the namespace. Only where
# root alone could have put anything on the way, and never over what is there.
asat() { docker exec -u 0 "$C" porthole-standin-at --as 1000:0 "$1" --run true </dev/null || fail "--as at '$1' failed"; }
asat "/Applications/Firefox Test.app"                                                                   # (o)
[ "$(x stat -c '%F %U %a' "/Applications/Firefox Test.app")" = "regular file root 755" ] \
  || fail "--as left no root-owned stand-in at a missing Mac path: $(x stat -c '%F %U %a' "/Applications/Firefox Test.app" 2>&1)"
[ "$(sum "/Applications/Firefox Test.app")" = "$STANDIN_SUM" ] || fail "--as left something else at a missing Mac path"
[ "$(x stat -c '%U %a' /Applications)" = "root 755" ] || fail "--as made /Applications as $(x stat -c '%U %a' /Applications)"
asat /usr/bin/perl
[ "$(sum /usr/bin/perl)" = "$perl_sum" ] || fail "--as changed the container's /usr/bin/perl"
x sh -c 'mkdir -m 777 /open && ln -s /tmp /lnk && mkdir -p /mine && chown 1000 /mine'
for p in /open/X.app /lnk/X.app /mine/X.app /open/sub/X.app; do
  asat "$p"
done
x sh -c 'test ! -e /open/X.app && test ! -e /tmp/X.app && test ! -e /mine/X.app && test ! -e /open/sub' \
  || fail "--as put something under a directory others can write, or through a symlink"
echo "ok: --as leaves the stand-in at a missing Mac path, and only where root alone could"
echo "ok standin_ns"
