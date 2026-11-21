#!/usr/bin/env bats
# platform: host-agnostic
# porthole-menubar-art SPEC DIR: copies each MENUBAR_ART pair out of the app's container into DIR (the
# per-user cache the viewer reads): <n>.app.png, the app's tray picture, and <n>.mac.png (or
# <n>.mac-template.png for a *Template* image), the Mac picture shown for it. Porthole ships neither.

setup() {
  W="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pma.XXXXXX")" && pwd)"
  export ROOT="$W/root" PORTHOLE_ROOT="$W/root"
  mkdir -p "$ROOT/opt/app" "$W/bin"
  png() { printf '\211PNG\r\n\032\n%s' "$1"; }
  png plain-tray > "$ROOT/opt/app/tray.png"
  # An Electron archive holding two pictures, one of them unpacked beside it.
  python3 - "$ROOT/opt/app/app.asar" <<'PY'
import json, struct, sys, os
a = b'\x89PNG\r\n\x1a\nunlocked-tray'; m = b'\x89PNG\r\n\x1a\nunlocked-mac'
h = {"files": {"images": {"files": {
  "tray_unlocked.png": {"size": len(a), "offset": "0"},
  "menubar": {"files": {"u_Template@2x.png": {"size": len(m), "offset": str(len(a))}}},
  "big.png": {"size": 9, "unpacked": True}}}}}
js = json.dumps(h).encode(); js += b' ' * (-len(js) % 4)
hdr = struct.pack('<4I', 4, len(js) + 8, len(js) + 4, len(js))
open(sys.argv[1], 'wb').write(hdr + js + a + m)
os.makedirs(sys.argv[1] + '.unpacked/images', exist_ok=True)
open(sys.argv[1] + '.unpacked/images/big.png', 'wb').write(b'\x89PNG\r\n\x1a\nB')
PY
  # docker: `exec [-i] [-u U] CONTAINER CMD...` runs CMD here; inspect reports it running.
  cat > "$W/bin/docker" <<'SH'
#!/bin/sh
[ "$1" = inspect ] && { [ -e "$ROOT/../down" ] && echo false || echo true; exit 0; }
[ "$1" = exec ] || exit 1
shift; while [ $# -gt 0 ]; do case $1 in -i) shift ;; -u) shift 2 ;; *) break ;; esac; done
shift; exec "$@"
SH
  chmod 755 "$W/bin/docker"
  export PATH="$W/bin:$PATH" DOCKER_HOST=tcp://192.0.2.1:2376
  cat > "$W/demo.container" <<'SPEC'
NAME='Linux Demo'
SLUG='demo'
CONTAINER='demo-gui'
APP_USER='demo'
MENUBAR_ART='unlocked plain'
MENUBAR_ART_unlocked='/opt/app/app.asar:/images/tray_unlocked.png /opt/app/app.asar:/images/menubar/u_Template@2x.png'
MENUBAR_ART_plain='/opt/app/tray.png /opt/app/app.asar:/images/big.png'
SPEC
  TOOL="${BATS_TEST_DIRNAME}/../bin/porthole-menubar-art"
  OUT="$W/cache/demo.menubar"
}
teardown() { rm -rf "$W"; }

@test "each pair is copied out, from an archive, its unpacked side, or a plain file" {
  run "$TOOL" "$W/demo.container" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(tail -c +9 "$OUT/unlocked.app.png")" = unlocked-tray ]
  [ "$(tail -c +9 "$OUT/unlocked.mac-template.png")" = unlocked-mac ]
  [ "$(tail -c +9 "$OUT/plain.app.png")" = plain-tray ]
  [ "$(tail -c +9 "$OUT/plain.mac.png")" = B ]
  [ "$(ls "$OUT" | wc -l | tr -d ' ')" = 4 ]
}

@test "a picture that can't be had leaves the previous cache as it was, and says which" {
  "$TOOL" "$W/demo.container" "$OUT"
  sed -i.bak 's|/opt/app/tray.png|/opt/app/gone.png|' "$W/demo.container"
  run "$TOOL" "$W/demo.container" "$OUT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"/opt/app/gone.png"* ]] || { echo "$output"; return 1; }
  [ "$(tail -c +9 "$OUT/plain.app.png")" = plain-tray ]
  [ -z "$(ls -d "$OUT".* 2>/dev/null)" ]
}

@test "something that isn't a PNG is refused" {
  echo 'not a picture' > "$ROOT/opt/app/tray.png"
  run "$TOOL" "$W/demo.container" "$OUT"
  [ "$status" -ne 0 ]
  [ ! -e "$OUT" ]
}

@test "an app with no menu-bar art: any old cache goes" {
  mkdir -p "$OUT"; : > "$OUT/x.app.png"
  sed -i.bak '/^MENUBAR_ART/d' "$W/demo.container"
  run "$TOOL" "$W/demo.container" "$OUT"
  [ "$status" -eq 0 ]
  [ ! -e "$OUT" ]
}

@test "the container not running: nothing changes" {
  touch "$W/down"
  run "$TOOL" "$W/demo.container" "$OUT"
  [ "$status" -ne 0 ]
  [ ! -e "$OUT" ]
}
