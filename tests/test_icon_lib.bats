#!/usr/bin/env bats
# The shared icon helpers. Real sips/iconutil (macOS only); fixtures are made from our own penguin.
ENGINE="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 || skip "needs sips + iconutil (macOS)"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/icon-lib.XXXXXX")"
  . "$ENGINE/bin/porthole-icon-lib.sh"
  sips -s format png "$ENGINE/packaging/macos/penguin.icns" --out "$WORK/p1024.png" >/dev/null
  sips -z 180 180 "$WORK/p1024.png" --out "$WORK/p180.png" >/dev/null
  sips -z 512 512 "$WORK/p1024.png" --out "$WORK/p512.png" >/dev/null
}
teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

@test "icon_width reads a PNG and an icns's largest representation" {
  [ "$(icon_width "$WORK/p180.png")" = 180 ]
  [ "$(icon_width "$ENGINE/packaging/macos/penguin.icns")" = 1024 ]
  [ "$(icon_width "$WORK/missing.png")" = 0 ]
}

@test "icon_is_png accepts a PNG and rejects an HTML error page" {
  icon_is_png "$WORK/p180.png"
  printf '<html>404</html>' > "$WORK/err.png"
  ! icon_is_png "$WORK/err.png" || return 1
}

@test "icon_png_to_icns never upscales: a 180px source yields an icns no wider than 180" {
  icon_png_to_icns "$WORK/p180.png" "$WORK/out/x.icns"
  w=$(icon_width "$WORK/out/x.icns")
  [ "$w" -gt 0 ] && [ "$w" -le 180 ]
}

@test "icon_png_to_icns keeps the full size of a large source" {
  icon_png_to_icns "$WORK/p1024.png" "$WORK/x.icns"
  [ "$(icon_width "$WORK/x.icns")" = 1024 ]
}

@test "icon_png_to_icns leaves an existing OUT untouched when the source is not an image" {
  cp "$ENGINE/packaging/macos/penguin.icns" "$WORK/keep.icns"
  printf 'nope' > "$WORK/bad.png"
  ! icon_png_to_icns "$WORK/bad.png" "$WORK/keep.icns" || return 1
  cmp -s "$WORK/keep.icns" "$ENGINE/packaging/macos/penguin.icns"
}

@test "icon_best picks the widest existing file, first on a tie" {
  icon_png_to_icns "$WORK/p180.png" "$WORK/a.icns"
  icon_png_to_icns "$WORK/p512.png" "$WORK/b.icns"
  cp "$WORK/b.icns" "$WORK/c.icns"
  [ "$(icon_best "$WORK/a.icns" "$WORK/b.icns")" = "$WORK/b.icns" ]
  [ "$(icon_best "$WORK/b.icns" "$WORK/c.icns")" = "$WORK/b.icns" ]
  [ "$(icon_best "$WORK/c.icns" "$WORK/b.icns")" = "$WORK/c.icns" ]
  [ "$(icon_best "$WORK/none.icns" "$WORK/a.icns")" = "$WORK/a.icns" ]
  [ -z "$(icon_best "$WORK/none.icns")" ]
}

@test "icon_log never fails, even without logger" {
  PATH=/nonexistent icon_log demo "a reason"
}
