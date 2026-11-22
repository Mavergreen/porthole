#!/usr/bin/env bats
# platform: macOS-only -- reads real processes with sysctl and proc_pidpath
# porthole-caller names the Mac application behind a connection: the unit walk against a fake
# process table, then the real tool against real processes and a real Unix connection.

setup_file() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  OUT="$BATS_FILE_TMPDIR"
  CC="${CC:-clang}"
  $CC -Wall -Werror -I"$ROOT/standin" -o "$OUT/test_caller_walk" \
    "$ROOT/tests/standin/test_caller_walk.c" "$ROOT/standin/caller_walk.c"
  $CC -Wall -Werror -I"$ROOT/standin" -o "$OUT/porthole-caller" \
    "$ROOT/standin/porthole-caller.c" "$ROOT/standin/caller_walk.c"
}

setup() { OUT="$BATS_FILE_TMPDIR"; }

@test "the walk finds the application under launchd, and refuses what it cannot follow" {
  run "$OUT/test_caller_walk"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "pid names this shell's top process as <pid>-<start>, tab, its path" {
  run "$OUT/porthole-caller" pid $$
  echo "$output"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -Eq $'^[0-9]+-[0-9]+\t/'
}

@test "alive is true for a live instance and false for a wrong start time" {
  id=$("$OUT/porthole-caller" pid $$ | cut -f1)
  run "$OUT/porthole-caller" alive "$id"
  [ "$status" -eq 0 ]
  run "$OUT/porthole-caller" alive "${id%-*}-1"
  [ "$status" -ne 0 ]
}

@test "pid of a process that does not exist is refused with a reason" {
  run "$OUT/porthole-caller" pid 999999
  [ "$status" -eq 1 ]
  [[ "$output" == porthole-caller:* ]] || false
}

@test "peer names the client on the other end of fd 0 as pid does" {
  sock="$OUT/p.sock"; rm -f "$sock"
  # Python 3 where there is one, else 10.9's own 2.7 (the 10.9 VM job): Popen works in both.
  py=$(command -v python3 || command -v python)
  run "$py" - "$OUT/porthole-caller" "$sock" <<'PY'
import os, socket, subprocess, sys, time
tool, path = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX); s.bind(path); s.listen(1)
pid = os.fork()
if pid == 0:
    c = socket.socket(socket.AF_UNIX); c.connect(path); time.sleep(3); os._exit(0)
conn, _ = s.accept()
def run(args, stdin=None):
    p = subprocess.Popen(args, stdin=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate()
    return p.returncode, out.decode(), err.decode()
rc, peer, err = run([tool, "peer"], stdin=conn.fileno())
_, byp, _ = run([tool, "pid", str(pid)])
print(repr(peer), repr(byp), err)
sys.exit(0 if rc == 0 and peer and peer == byp else 1)
PY
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "peer with fd 0 not a socket is refused" {
  run "$OUT/porthole-caller" peer < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == porthole-caller:* ]] || false
}
