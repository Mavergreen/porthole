#!/bin/sh
# platform: macOS-only -- runs the installed Porthole engine, which builds macOS app bundles
_porthole="$ROOT/Applications/Porthole.app/Contents/Resources/engine/bin/porthole"
for _conf in "$ROOT"/usr/local/mavergreen/*/share/porthole/presets/*.conf; do
  [ -f "$_conf" ] || continue
  "$_porthole" materialize "$_conf" --apps-dir "$ROOT/Applications" \
    || echo "porthole postinstall: could not re-materialize $_conf" >&2
done
