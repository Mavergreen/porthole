#!/bin/sh
# platform: host-agnostic
# Porthole runs every app in a container, so it is the product that requires Container Tools (the
# presets require only Porthole). An install from before the /usr/local/mavergreen layout has
# docker-machine in /usr/local/bin and no manifest: it is out of date, not missing.
if [ ! -f "$ROOT/usr/local/mavergreen/container-tools/mavergreen.plist" ]; then
  if [ -e "$ROOT/usr/local/bin/docker-machine" ]; then
    echo "Porthole needs a newer Container Tools for Mavericks: update Container Tools for Mavericks to 20260727-mavericks.30 or later." >&2
    echo "Get it from https://github.com/Mavergreen/container-tools/releases, then run this installer again." >&2
  else
    echo "Porthole needs Container Tools for Mavericks installed first (it runs the apps' containers)." >&2
    echo "Install it (https://github.com/Mavergreen/container-tools), then run this installer again." >&2
  fi
  false
fi
