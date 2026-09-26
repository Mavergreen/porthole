#!/usr/bin/env bats
# platform: macOS-only -- runs PlistBuddy
# porthole materialize: render a preset conf into a standalone "Linux <App>.app" that
# wraps the SHARED installed Porthole engine. Structural test -- no live container
# (icon extraction skipped via PORTHOLE_MATERIALIZE_NO_ICON).

setup() {
  ENGINE="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  APPS="$(mktemp -d "${TMPDIR:-/tmp}/porthole-apps.XXXXXX")"
  # Never read this Mac's real icon caches.
  export PORTHOLE_ICON_CACHE="$APPS/sys-icons" PORTHOLE_USER_ICON_CACHE="$APPS/user-icons"
}
teardown() {
  [ -n "$APPS" ] && rm -rf "$APPS"
}

@test "materialize builds a standalone Linux <App>.app from a preset conf" {
  run "$ENGINE/bin/porthole" materialize "$ENGINE/examples/thunderbird.conf" --apps-dir "$APPS"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -d "$APPS/Linux Thunderbird.app" ]
}

@test "the bundle has an executable stub that execs the Resources launcher" {
  "$ENGINE/bin/porthole" materialize "$ENGINE/examples/thunderbird.conf" --apps-dir "$APPS" >/dev/null
  B="$APPS/Linux Thunderbird.app/Contents"
  [ -x "$B/MacOS/thunderbird" ]
  grep -q 'Resources/bin' "$B/MacOS/thunderbird"
  [ -x "$B/Resources/bin/thunderbird" ]
}

@test "the bundle carries the rendered container recipe" {
  "$ENGINE/bin/porthole" materialize "$ENGINE/examples/thunderbird.conf" --apps-dir "$APPS" >/dev/null
  [ -f "$APPS/Linux Thunderbird.app/Contents/Resources/thunderbird/Dockerfile" ]
}

@test "Info.plist names the app and the per-app bundle id" {
  "$ENGINE/bin/porthole" materialize "$ENGINE/examples/thunderbird.conf" --apps-dir "$APPS" >/dev/null
  P="$APPS/Linux Thunderbird.app/Contents/Info.plist"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$P")" = "Linux Thunderbird" ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$P")" = "dev.mavergreen.porthole.thunderbird" ]
}

@test "the app carries its OWN engine binary + recovery watcher and execs it in place" {
  # A copied binary makes each materialized app a distinct LaunchServices app (own icon/name/instance),
  # so several viewers can run at once -- rather than all reactivating one shared Porthole.app.
  fake="$APPS/fake-engine"; printf '#!/bin/sh\nexit 0\n' > "$fake"; chmod +x "$fake"
  PORTHOLE_ENGINE_BIN="$fake" "$ENGINE/bin/porthole" \
    materialize "$ENGINE/examples/thunderbird.conf" --apps-dir "$APPS" >/dev/null
  B="$APPS/Linux Thunderbird.app/Contents"
  [ -x "$B/MacOS/Porthole" ]                                 # its own copy of the viewer engine binary
  [ -x "$B/Resources/bin/porthole-recover-watch" ]          # the recovery watcher, bundled
  grep -q 'exec "$_bin" "$XPRA_SOCK"' "$B/Resources/bin/thunderbird"   # runs it IN PLACE
  ! grep -q 'open "$APP"' "$B/Resources/bin/thunderbird" || false     # not `open` of a shared app
}

# Icons: fixtures from our own penguin; logger stubbed to a file; both caches in the temp dir.
icon_setup() {
  command -v sips >/dev/null 2>&1 || skip "needs sips (macOS)"
  export PORTHOLE_ICON_CACHE="$APPS/sys-icons" PORTHOLE_USER_ICON_CACHE="$APPS/user-icons"
  mkdir -p "$APPS/bin"; printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/logger.log"\n' "$APPS" > "$APPS/bin/logger"
  chmod +x "$APPS/bin/logger"; export PATH="$APPS/bin:$PATH"
  sips -s format png "$ENGINE/packaging/macos/penguin.icns" --out "$APPS/p1024.png" >/dev/null
  sips -z 180 180 "$APPS/p1024.png" --out "$APPS/p180.png" >/dev/null
  sips -z 512 512 "$APPS/p1024.png" --out "$APPS/p512.png" >/dev/null
  unset PORTHOLE_MATERIALIZE_NO_ICON
  sed '/^ICON_URL=/d' "$ENGINE/examples/thunderbird.conf" > "$APPS/thunderbird.conf"
}
with_icon_url() { printf 'ICON_URL=%s\n' "$1" >> "$APPS/thunderbird.conf"; }
mat() { "$ENGINE/bin/porthole" materialize "$APPS/thunderbird.conf" --apps-dir "$APPS" >/dev/null; }
R() { printf '%s' "$APPS/Linux Thunderbird.app/Contents/Resources"; }

@test "no icon anywhere: the penguin, recorded as width 0" {
  icon_setup; mat
  cmp -s "$(R)/AppIcon.icns" "$ENGINE/packaging/macos/penguin.icns"
  [ "$(cat "$(R)/AppIcon.width")" = 0 ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APPS/Linux Thunderbird.app/Contents/Info.plist")" = AppIcon ]
}

@test "ICON_URL of any size lands in the system cache and the bundle" {
  icon_setup; with_icon_url "file://$APPS/p180.png"; mat
  [ -f "$APPS/sys-icons/thunderbird.icns" ]
  w=$(cat "$(R)/AppIcon.width"); [ "$w" -gt 0 ] && [ "$w" -le 180 ]   # never upscaled: 128 for a 180 source
  cmp -s "$(R)/AppIcon.icns" "$APPS/sys-icons/thunderbird.icns"
}

@test "a 404 ICON_URL keeps the cached icon, succeeds, and logs why" {
  icon_setup; with_icon_url "file://$APPS/p512.png"; mat
  cp "$APPS/sys-icons/thunderbird.icns" "$APPS/before.icns"
  sed -i '' "s|^ICON_URL=.*|ICON_URL=file://$APPS/gone.png|" "$APPS/thunderbird.conf"
  run "$ENGINE/bin/porthole" materialize "$APPS/thunderbird.conf" --apps-dir "$APPS"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp -s "$APPS/sys-icons/thunderbird.icns" "$APPS/before.icns"
  [ "$(cat "$(R)/AppIcon.width")" = 512 ]
  grep -q 'porthole thunderbird: ICON_URL fetch failed' "$APPS/logger.log"
}

@test "an ICON_URL serving a non-PNG keeps the cached icon and logs why" {
  icon_setup; with_icon_url "file://$APPS/p512.png"; mat
  printf '<html>moved</html>' > "$APPS/page.png"
  sed -i '' "s|^ICON_URL=.*|ICON_URL=file://$APPS/page.png|" "$APPS/thunderbird.conf"
  mat
  [ "$(icon_w "$APPS/sys-icons/thunderbird.icns")" = 512 ]
  grep -q 'thunderbird: ICON_URL is not a PNG' "$APPS/logger.log"
}
icon_w() { sips -g pixelWidth "$1" | awk '/pixelWidth/{print $2}'; }

@test "the larger cached icon wins, whichever cache holds it" {
  icon_setup; with_icon_url "file://$APPS/p180.png"; mat
  mkdir -p "$APPS/user-icons"
  . "$ENGINE/bin/porthole-icon-lib.sh"; icon_png_to_icns "$APPS/p512.png" "$APPS/user-icons/thunderbird.icns"
  mat
  [ "$(cat "$(R)/AppIcon.width")" = 512 ]
  cmp -s "$(R)/AppIcon.icns" "$APPS/user-icons/thunderbird.icns"
}

@test "re-materializing keeps a cached real icon (no penguin reset)" {
  icon_setup; with_icon_url "file://$APPS/p512.png"; mat
  export PORTHOLE_MATERIALIZE_NO_ICON=1; mat
  [ "$(cat "$(R)/AppIcon.width")" = 512 ]
}

@test "PORTHOLE_MATERIALIZE_NO_ICON makes no fetch" {
  icon_setup; with_icon_url "file://$APPS/p512.png"
  PORTHOLE_MATERIALIZE_NO_ICON=1 "$ENGINE/bin/porthole" materialize "$APPS/thunderbird.conf" --apps-dir "$APPS" >/dev/null
  [ ! -f "$APPS/sys-icons/thunderbird.icns" ]
}

@test "with no console user (and no override), materialize skips the user cache and succeeds" {
  icon_setup; unset PORTHOLE_USER_ICON_CACHE
  run env PORTHOLE_CONSOLE_USER=root "$ENGINE/bin/porthole" materialize "$APPS/thunderbird.conf" --apps-dir "$APPS"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the bundle carries the icon library for its launcher" {
  icon_setup; mat
  [ -f "$(R)/bin/porthole-icon-lib.sh" ]
}
