#!/bin/sh
# platform: macOS-only -- drives shipyard's stage_product.sh/build_component_pkg.sh/set_install_floor.sh, which run pkgbuild/productbuild/PlistBuddy
# Build the Porthole .pkg: the shared viewer ENGINE, shipped as /Applications/Porthole.app.
# The engine CLI (bin/porthole, generate-viewer, the recovery watcher), the templates/, the
# menu daemon, and the icon extractor are staged INSIDE the app bundle
# (Contents/Resources/engine/) so `porthole materialize` resolves them relative to itself.
# the product's tree gets a porthole exec shim.
# Usage: build_pkg.sh <version> <out.pkg> [<built-Porthole.app>]
set -eu
VERSION=$1; OUT=$2
APP_IN="${3:-}"
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

# Locate the built Porthole.app (arg wins; else a conventional build dir).
if [ -z "$APP_IN" ]; then
  for d in "$REPO/_build/viewer/Porthole.app" "$REPO/build-native/viewer/Porthole.app"; do
    [ -d "$d" ] && { APP_IN="$d"; break; }
  done
fi
[ -n "$APP_IN" ] && [ -d "$APP_IN" ] \
  || { echo "build_pkg: no built Porthole.app (pass it as arg 3, or build it first)" >&2; exit 1; }

# Stage the payload exactly as it should land on disk.
# BSD mktemp (all macOS, incl. 10.9) requires an explicit template.
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/porthole-root.XXXXXX")
install -d "$ROOT/Applications"
cp -R "$APP_IN" "$ROOT/Applications/Porthole.app"

# Engine CLI + assets inside the bundle. materialize's ENGINE=$(dirname $0)/.. resolves to
# this engine/ dir, so generate-viewer, templates/, menu-daemon.py and the icon extractor
# all sit where it (and generate-viewer) look for them.
ENGDIR="$ROOT/Applications/Porthole.app/Contents/Resources/engine"
install -d "$ENGDIR/bin" "$ENGDIR/templates" "$ENGDIR/viewer/cmake"
install -m 0755 "$REPO/bin/porthole"                     "$ENGDIR/bin/porthole"
# Porthole's viewer transport (skarnet s6-ipcserver), cross-built for 10.9; the CMake `transport`
# target passes its dir. A dev build without it still packages -- the launcher then falls back to a
# PATH s6-ipcserver -- mirroring the ENGINE_BIN handling elsewhere.
if [ -n "${PORTHOLE_TRANSPORT_DIR:-}" ] && [ -x "$PORTHOLE_TRANSPORT_DIR/s6-ipcserver" ]; then
  for _b in s6-ipcserver s6-ipcserver-socketbinder s6-ipcserverd; do
    install -m 0755 "$PORTHOLE_TRANSPORT_DIR/$_b" "$ENGDIR/bin/$_b"
  done
else
  echo "build_pkg: no transport binaries (PORTHOLE_TRANSPORT_DIR unset) -- pkg relies on a PATH s6-ipcserver" >&2
fi
install -m 0755 "$REPO/bin/generate-viewer"              "$ENGDIR/bin/generate-viewer"
install -m 0755 "$REPO/bin/porthole-recover-watch"       "$ENGDIR/bin/porthole-recover-watch"
install -m 0644 "$REPO/bin/porthole-icon-lib.sh"          "$ENGDIR/bin/porthole-icon-lib.sh"
install -m 0644 "$REPO/menu-daemon.py"                   "$ENGDIR/menu-daemon.py"
# What the VIEWER speaks, read out of its sources (which do not ship). generate-viewer runs on the
# USER's Mac at materialize time and renders the launcher's compat nudge against this -- not against
# the base image's XPRA_VERSION, so the two can diverge and the nudge can fire. See generate-viewer.
sh "$REPO/build/xpra-client-version.sh" > "$ENGDIR/XPRA_CLIENT_VERSION"
chmod 644 "$ENGDIR/XPRA_CLIENT_VERSION"
install -m 0755 "$REPO/viewer/cmake/extract-app-icns.sh" "$ENGDIR/viewer/cmake/extract-app-icns.sh"
install -m 0644 "$REPO/packaging/macos/penguin.icns"     "$ENGDIR/penguin.icns"   # default app icon
cp -R "$REPO/templates/." "$ENGDIR/templates/"
# Stamp the release version into the engine so `porthole materialize` pins the per-app recipe's
# FROM to ghcr.io/mavergreen/porthole-base:<this version> (a dev checkout has none -> :latest).
printf '%s\n' "$VERSION" > "$ENGDIR/VERSION"

T="$ROOT/usr/local/mavergreen/porthole"
install -d "$T/bin"
cat > "$T/bin/porthole" <<'EOF'
#!/bin/sh
exec "/Applications/Porthole.app/Contents/Resources/engine/bin/porthole" "$@"
EOF
chmod 755 "$T/bin/porthole"

. "$REPO/build/msc.sh"
SCRIPTSDIR=$(mktemp -d "${TMPDIR:-/tmp}/porthole-scripts.XXXXXX")
set -- --stage "$ROOT" --product porthole --name Porthole --version "$VERSION" \
  --postinstall-hook "$HERE/postinstall-hook.sh" --scripts-out "$SCRIPTSDIR"
if [ -n "${UPD_APP:-}" ]; then
  [ -d "$UPD_APP" ] || { echo "build_pkg: UPD_APP set but no updater .app at $UPD_APP" >&2; exit 1; }
  set -- "$@" --updater-app "$UPD_APP"
fi
find "$ROOT" -name '._*' -delete 2>/dev/null || true
sh "$SHIPYARD/stage_product.sh" "$@"

COMPONENT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/porthole-pkg.XXXXXX")
sh "$SHIPYARD/build_component_pkg.sh" --root "$ROOT" --identifier dev.mavergreen.porthole \
  --version "$VERSION" --install-location / --scripts "$SCRIPTSDIR" \
  --out "$COMPONENT_DIR/porthole-component.pkg" >&2

mkdir -p "$(dirname "$OUT")"
sh "$SHIPYARD/set_install_floor.sh" --identifier dev.mavergreen.porthole --title Porthole \
  --component "$COMPONENT_DIR/porthole-component.pkg" --out "$OUT" --require-scripts --host-arch x86_64 >&2

echo "Built $OUT"
