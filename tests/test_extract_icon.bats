#!/usr/bin/env bats
# The container icon extractor: argument-driven, writes only on success.
ENGINE="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
X="$ENGINE/viewer/cmake/extract-app-icns.sh"

setup() {
  command -v sips >/dev/null 2>&1 || skip "needs sips (macOS)"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/extract.XXXXXX")"; mkdir -p "$WORK/bin"
  sips -s format png "$ENGINE/packaging/macos/penguin.icns" --out "$WORK/icon.png" >/dev/null
  # docker exec C sh -c "ls -S GLOB..." -> a path, or nothing when $WORK/nomatch exists;
  # docker exec C cat PATH -> the fixture PNG. Logs every call.
  cat > "$WORK/bin/docker" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$WORK/docker.log"
case "\$*" in
  *"ls -S"*) [ -f "$WORK/nomatch" ] || echo /usr/share/icons/app.png ;;
  *" cat "*) cat "$WORK/icon.png" ;;
esac
EOF
  chmod +x "$WORK/bin/docker"; export PATH="$WORK/bin:$PATH"
}
teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

@test "extracts the named container's icon into OUT" {
  run sh "$X" demo-gui '/usr/share/icons/hicolor/*/apps/demo.png' "$WORK/out/demo.icns"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$WORK/out/demo.icns" ]
  grep -q '^exec demo-gui sh -c ls -S /usr/share/icons/hicolor/\*/apps/demo.png' "$WORK/docker.log"
  ! grep -q 'op-gui\|docker-machine' "$WORK/docker.log"
}

@test "no match: non-zero, OUT untouched" {
  : > "$WORK/nomatch"; printf 'keep' > "$WORK/keep.icns"
  run sh "$X" demo-gui '/nope/*.png' "$WORK/keep.icns"
  [ "$status" -ne 0 ]
  [ "$(cat "$WORK/keep.icns")" = keep ]
}

@test "missing arguments: usage error, nothing written" {
  run sh "$X" demo-gui
  [ "$status" -ne 0 ]
}
