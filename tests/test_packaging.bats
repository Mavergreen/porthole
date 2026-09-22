#!/usr/bin/env bats
# build_pkg.sh stages the Porthole.app engine + the engine CLI/templates + the CLI wrapper
# into a productbuild .pkg with a 10.9 floor. Uses a fake minimal Porthole.app so the test
# needs no compiled viewer (real pkgbuild/productbuild, which macOS provides).

setup() {
  ENGINE="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/porthole-pkg-test.XXXXXX")"
  FAKEAPP="$WORK/Porthole.app"
  mkdir -p "$FAKEAPP/Contents/MacOS" "$FAKEAPP/Contents/Resources"
  printf '#!/bin/sh\n' > "$FAKEAPP/Contents/MacOS/Porthole"; chmod 755 "$FAKEAPP/Contents/MacOS/Porthole"
  printf '<plist></plist>\n' > "$FAKEAPP/Contents/Info.plist"
}
teardown() { [ -n "$WORK" ] && rm -rf "$WORK"; }

@test "build_pkg stages the app, the engine CLI, and the wrapper into the payload" {
  run sh "$ENGINE/packaging/macos/build_pkg.sh" 9.9.9 "$WORK/out.pkg" "$FAKEAPP"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$WORK/out.pkg" ]
  files="$(pkgutil --payload-files "$WORK/out.pkg")"
  echo "$files" | grep -q 'Applications/Porthole.app/Contents/MacOS/Porthole'
  echo "$files" | grep -q 'Applications/Porthole.app/Contents/Resources/engine/bin/porthole'
  echo "$files" | grep -q 'Applications/Porthole.app/Contents/Resources/engine/bin/generate-viewer'
  echo "$files" | grep -q 'Applications/Porthole.app/Contents/Resources/engine/templates/launcher.tmpl'
  echo "$files" | grep -q 'usr/local/bin/porthole'
}

@test "the pkg declares a 10.9 minimum" {
  sh "$ENGINE/packaging/macos/build_pkg.sh" 9.9.9 "$WORK/out.pkg" "$FAKEAPP" >/dev/null
  d="$WORK/expand"; pkgutil --expand "$WORK/out.pkg" "$d"
  grep -q 'os-version min="10.9"' "$d/Distribution"
}

@test "build_pkg stages engine/bin/s6-ipcserver when transport binaries are provided" {
  command -v pkgbuild >/dev/null 2>&1 || skip "pkgbuild not available"
  command -v pkgutil >/dev/null 2>&1 || skip "pkgutil not available"
  tdir="$WORK/transport"; mkdir -p "$tdir"
  for b in s6-ipcserver s6-ipcserver-socketbinder s6-ipcserverd; do
    printf 'fake\n' > "$tdir/$b"; chmod +x "$tdir/$b"
  done
  PORTHOLE_TRANSPORT_DIR="$tdir" run sh "$ENGINE/packaging/macos/build_pkg.sh" \
      9.9.9 "$WORK/out-transport.pkg" "$FAKEAPP"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  pkgutil --payload-files "$WORK/out-transport.pkg" 2>/dev/null | grep -q 'engine/bin/s6-ipcserver' \
    || { echo "transport not in payload: $(pkgutil --payload-files "$WORK/out-transport.pkg" 2>/dev/null)"; return 1; }
  for _b in s6-ipcserver-socketbinder s6-ipcserverd; do
    pkgutil --payload-files "$WORK/out-transport.pkg" 2>/dev/null | grep -q "engine/bin/$_b" \
      || { echo "missing engine/bin/$_b in payload"; return 1; }
  done
}

# ONE-TIME MIGRATION off the ModernMavericks identity (flag day 2026-09-22).
# DELETABLE with packaging/macos/scripts/preinstall's block (see shipyard SKILL.md "Consolidation backlog").
fake_pkgutil() {
  mkdir -p "$WORK/stubs"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit %s\n' "$WORK/pkgutil.log" "${1:-0}" > "$WORK/stubs/pkgutil"
  chmod 755 "$WORK/stubs/pkgutil"
}

@test "the pkg carries the flag-day preinstall" {
  sh "$ENGINE/packaging/macos/build_pkg.sh" 9.9.9 "$WORK/out.pkg" "$FAKEAPP" >/dev/null
  d="$WORK/expand"; pkgutil --expand "$WORK/out.pkg" "$d"
  cmp "$ENGINE/packaging/macos/scripts/preinstall" "$d/porthole-component.pkg/Scripts/preinstall" \
    || { echo "the component pkg does not ship scripts/preinstall, so the old receipt is never forgotten"; return 1; }
}

@test "preinstall forgets the pre-flag-day receipt on the TARGET volume" {
  fake_pkgutil 0
  mkdir -p "$WORK/vol"
  PATH="$WORK/stubs:$PATH" run sh "$ENGINE/packaging/macos/scripts/preinstall" pkg "$WORK/vol" "$WORK/vol" "$WORK/vol"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qx -- "--volume $WORK/vol --forget dev.modernmavericks.porthole" "$WORK/pkgutil.log" \
    || { echo "old receipt not forgotten on the target volume; pkgutil saw: $(cat "$WORK/pkgutil.log" 2>/dev/null)"; return 1; }
}

@test "preinstall touches nothing without a target volume, and never fails the install" {
  fake_pkgutil 1
  PATH="$WORK/stubs:$PATH" run sh "$ENGINE/packaging/macos/scripts/preinstall"
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$WORK/pkgutil.log" ] || { echo "forgot a receipt with no target volume: $(cat "$WORK/pkgutil.log")"; return 1; }
  mkdir -p "$WORK/vol"
  PATH="$WORK/stubs:$PATH" run sh "$ENGINE/packaging/macos/scripts/preinstall" pkg "$WORK/vol" "$WORK/vol" "$WORK/vol"
  [ "$status" -eq 0 ] || { echo "a failing pkgutil failed the install"; return 1; }
}
