#!/usr/bin/env bats
# Generated launcher: the per-user icon cache and the Dock icon hand-off.
load test_helper
ENGINE="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# A materialized-style root: the generated thunderbird launcher, the library, a fake extractor that
# copies $EXTRACT_FROM to OUT (or fails when unset), and a viewer stub printing PORTHOLE_APP_ICON.
run_icon() {  # $1 = image Created; $2 = AppIcon.width in the bundle
  command -v sips >/dev/null 2>&1 || skip "needs sips (macOS)"
  R="$WORK/app/Contents/Resources"; mkdir -p "$R/bin" "$WORK/app/Contents/MacOS"
  cp "$ENGINE/examples/bin/thunderbird" "$R/bin/thunderbird"
  [ -n "${NOLIB:-}" ] || cp "$ENGINE/bin/porthole-icon-lib.sh" "$R/bin/"
  printf 'NAME=x\nCONTAINER=thunderbird-gui\nIMAGE=mavericks-thunderbird\nBUILD_CONTEXT=thunderbird\n' > "$R/thunderbird.container"
  printf '%s\n' "$2" > "$R/AppIcon.width"
  cat > "$R/bin/extract-app-icns.sh" <<'EOF'
#!/bin/sh
echo "extract $*" >> "$WORK/extract.log"
[ -n "${EXTRACT_FROM:-}" ] || exit 1
mkdir -p "$(dirname "$3")"; cp "$EXTRACT_FROM" "$3"
EOF
  chmod +x "$R/bin/extract-app-icns.sh"
  printf '#!/bin/sh\necho "APPICON=${PORTHOLE_APP_ICON:-}"\n' > "$WORK/app/Contents/MacOS/Porthole"
  chmod +x "$WORK/app/Contents/MacOS/Porthole"
  cat > "$STUB_DIR/docker-created" <<EOF
$1
EOF
  export WORK CREATED_FILE="$STUB_DIR/docker-created"
  run env DOCKER_HOST=tcp://192.0.2.1:2376 HOME="$WORK/home" \
      PORTHOLE_ICON_CACHE="$WORK/sys" PORTHOLE_USER_ICON_CACHE="$WORK/user" \
      THUNDERBIRD_NO_RECOVER=1 "$R/bin/thunderbird"
}
fixture_icns() {  # $1 = width, $2 = out
  sips -s format png "$ENGINE/packaging/macos/penguin.icns" --out "$WORK/p.png" >/dev/null
  sips -z "$1" "$1" "$WORK/p.png" --out "$WORK/p$1.png" >/dev/null
  ( . "$ENGINE/bin/porthole-icon-lib.sh"; icon_png_to_icns "$WORK/p$1.png" "$2" )
}

@test "no cached icon: extracts into the user cache and hands it to the viewer" {
  fixture_icns 512 "$WORK/src.icns"
  EXTRACT_FROM="$WORK/src.icns" run_icon 2026-01-01T00:00:00.000000000Z 0
  [ -f "$WORK/user/thunderbird.icns" ]
  grep -q "extract thunderbird-gui /usr/share/icons/hicolor/256x256/apps/thunderbird.png $WORK/user/thunderbird.icns" "$WORK/extract.log"
  [[ "$output" == *"APPICON=$WORK/user/thunderbird.icns"* ]]
}

@test "a 512 system icon, bundle already wearing it: no extraction, no hand-off" {
  fixture_icns 512 "$WORK/sys/thunderbird.icns"
  run_icon 2026-01-01T00:00:00.000000000Z 512
  [ ! -f "$WORK/extract.log" ]
  [[ "$output" != *"APPICON=/"* ]]
}

@test "only a 180 icon cached: extracts to upgrade it" {
  fixture_icns 180 "$WORK/sys/thunderbird.icns"; fixture_icns 512 "$WORK/src.icns"
  EXTRACT_FROM="$WORK/src.icns" run_icon 2026-01-01T00:00:00.000000000Z 180
  grep -q "^extract thunderbird-gui .* $WORK/user/thunderbird.icns$" "$WORK/extract.log"
  [[ "$output" == *"APPICON=$WORK/user/thunderbird.icns"* ]]
}

@test "a user icon older than the image is re-extracted" {
  fixture_icns 512 "$WORK/user/thunderbird.icns"; touch -t 200001010000 "$WORK/user/thunderbird.icns"
  fixture_icns 512 "$WORK/src.icns"
  EXTRACT_FROM="$WORK/src.icns" run_icon 2026-01-01T00:00:00.000000000Z 512
  grep -q "^extract thunderbird-gui .* $WORK/user/thunderbird.icns$" "$WORK/extract.log"
}

@test "a failed extraction still launches the viewer" {
  run_icon 2026-01-01T00:00:00.000000000Z 0
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"APPICON="* ]]
}

# Icons are best-effort: a bundle without the icon library (an older materialize, or a launcher run
# straight from examples/) must still launch, just without icon handling.
@test "no icon library: the launcher skips icons and still launches" {
  fixture_icns 512 "$WORK/src.icns"
  EXTRACT_FROM="$WORK/src.icns" run_icon_nolib 2026-01-01T00:00:00.000000000Z 0
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"APPICON="* ]]
  [ ! -f "$WORK/extract.log" ]
}
run_icon_nolib() { NOLIB=1 run_icon "$@"; }

# The container is the source of the user cache: once its icon is cached and fresh, extracting again
# can't do better, however small it is. (A 256px-only app re-extracted on every launch.)
@test "a small container icon, already cached and fresh, is not re-extracted every launch" {
  fixture_icns 256 "$WORK/user/thunderbird.icns"; fixture_icns 512 "$WORK/src.icns"
  EXTRACT_FROM="$WORK/src.icns" run_icon 2000-01-01T00:00:00.000000000Z 256
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -f "$WORK/extract.log" ]
}
