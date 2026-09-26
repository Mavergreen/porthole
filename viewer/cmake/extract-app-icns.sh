#!/bin/sh
# Extract an app's icon from its own container (the user's installed copy -- Porthole never ships a
# vendor icon) into a Mac .icns. Writes OUT only on success; exits non-zero otherwise.
# Usage: extract-app-icns.sh CONTAINER ICON_GLOB OUT.icns
set -u
CONTAINER="${1:?usage: extract-app-icns.sh CONTAINER ICON_GLOB OUT.icns}"
ICON_GLOB="${2:?usage: extract-app-icns.sh CONTAINER ICON_GLOB OUT.icns}"
OUT="${3:?usage: extract-app-icns.sh CONTAINER ICON_GLOB OUT.icns}"
_here=$(cd "$(dirname "$0")" && pwd)
if [ -f "$_here/porthole-icon-lib.sh" ]; then . "$_here/porthole-icon-lib.sh"
else . "$_here/../../bin/porthole-icon-lib.sh"; fi

# The glob is expanded by the container's shell on purpose (it's the conf's ICON_GLOB).
png=$(docker exec "$CONTAINER" sh -c "ls -S $ICON_GLOB 2>/dev/null | head -1" 2>/dev/null)
[ -n "$png" ] || { echo "icon: nothing in $CONTAINER matches $ICON_GLOB" >&2; exit 1; }
tmp=$(mktemp "${TMPDIR:-/tmp}/porthole-extract.XXXXXX") || exit 1
if docker exec "$CONTAINER" cat "$png" > "$tmp" 2>/dev/null && icon_is_png "$tmp" \
   && icon_png_to_icns "$tmp" "$OUT"; then
  rm -f "$tmp"; echo "icon: wrote $OUT" >&2; exit 0
fi
rm -f "$tmp"; echo "icon: could not read or convert $png from $CONTAINER" >&2; exit 1
