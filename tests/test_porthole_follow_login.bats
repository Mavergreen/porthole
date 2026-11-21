#!/usr/bin/env bats
# platform: host-agnostic
# porthole-follow, start at login: the app's own setting (its XDG autostart entry, which 1Password's
# "Start at login" checkbox writes) and the Mac's Login Items follow each other. Whichever side changed
# since the last sync wins (two on/off sides that differ cannot both have changed).

setup() {
  W="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pfl.XXXXXX")" && pwd)"
  export STATE="$W/state" HOME="$W/home" TMPDIR="$W/tmp" PORTHOLE_STATE_DIR="$W/pstate"
  mkdir -p "$STATE" "$HOME" "$TMPDIR" "$STATE/chome/.config/autostart"
  B="$W/Applications/Linux Demo.app"; mkdir -p "$B/Contents/Resources"
  export BUNDLE="$B"
  cat > "$B/Contents/Resources/demo.container" <<'SPEC'
NAME='Linux Demo'
SLUG='demo'
CONTAINER='demo-gui'
APP_USER='demo'
APP_HOME='/home/demo'
APP_BIN='demo'
APP_FLAGS='--no-sandbox'
SOCKETS=''
SPEC
  BIN="$W/bin"; mkdir -p "$BIN"
  # docker: `exec [-i] [-u U] CONTAINER sh -c SCRIPT ARG...` runs SCRIPT here with the container's HOME.
  cat > "$BIN/docker" <<'SH'
#!/bin/sh
[ "$1" = exec ] || exit 0
shift
while [ $# -gt 0 ]; do case $1 in -i) shift ;; -u) shift 2 ;; *) break ;; esac; done
shift   # CONTAINER
[ -e "$STATE/down" ] && { echo "container is not running" >&2; exit 1; }
if [ "$1" = sh ] && [ "$2" = -c ]; then
  echo "linux-call $4" >> "$STATE/calls"
  shift 2; HOME="$STATE/chome" exec sh -c "$@"
fi
exit 1
SH
  # osascript: a Login Items list in a file.
  cat > "$BIN/osascript" <<'SH'
#!/bin/sh
s=$2; touch "$STATE/items"
case $s in
  *"get the path of every login item"*) paste -sd, - < "$STATE/items" | sed 's/,/, /g'; echo "mac-read" >> "$STATE/calls" ;;
  *"make login item"*) p=$(printf '%s' "$s" | sed -n 's/.*path:"\([^"]*\)".*/\1/p'); h=$(printf '%s' "$s" | sed -n 's/.*hidden:\([a-z]*\).*/\1/p')
     echo "$p" >> "$STATE/items"; echo "mac-make $h" >> "$STATE/calls" ;;
  *"delete"*) p=$(printf '%s' "$s" | sed -n 's/.*path is "\([^"]*\)".*/\1/p'); grep -vxF "$p" "$STATE/items" > "$STATE/i2"; mv "$STATE/i2" "$STATE/items"; echo "mac-delete" >> "$STATE/calls" ;;
esac
SH
  printf '#!/bin/sh\nexit 0\n' > "$BIN/s6-ipcserver"
  chmod 755 "$BIN"/*
  export PATH="$BIN:$PATH" DOCKER_HOST=tcp://192.0.2.1:2376 PORTHOLE_FOLLOW_BIN="$BIN" PORTHOLE_FOLLOW_SECS=0.2
  FOLLOW="${BATS_TEST_DIRNAME}/../bin/porthole-follow"
  AS="$STATE/chome/.config/autostart"
}
teardown() { rm -rf "$W"; }

once() { PORTHOLE_FOLLOW_ONCE=1 "$FOLLOW" "$BUNDLE/Contents/Resources/demo.container" $$; }
app_entry() { printf '[Desktop Entry]\nType=Application\nName=Demo\nExec=/opt/Demo/demo %s\n' "$1" > "$AS/com.example.Demo.desktop"; }
login_items() { cat "$STATE/items" 2>/dev/null; }

@test "the app's own setting turned on: a Login Item is made, hidden when the entry starts it differently" {
  app_entry --silent
  once
  [ "$(login_items)" = "$BUNDLE" ]
  grep -qx 'mac-make true' "$STATE/calls"
  [ "$(cat "$PORTHOLE_STATE_DIR/demo.login")" = on ]
}

@test "an entry that starts the app as usual makes a visible Login Item" {
  app_entry --no-sandbox
  once
  grep -qx 'mac-make false' "$STATE/calls"
}

@test "a disabled entry counts as off" {
  app_entry --silent; echo 'X-GNOME-Autostart-enabled=false' >> "$AS/com.example.Demo.desktop"
  once
  [ -z "$(login_items)" ]
}

@test "an entry for another program is not the app's" {
  printf '[Desktop Entry]\nExec=/usr/bin/other\n' > "$AS/other.desktop"
  once
  [ -z "$(login_items)" ]
  [ -f "$AS/other.desktop" ]
}

@test "the Login Item removed on the Mac: the app's entry goes, and comes back as it was" {
  app_entry --silent; once
  : > "$STATE/items"
  once
  [ ! -e "$AS/com.example.Demo.desktop" ]
  [ "$(cat "$PORTHOLE_STATE_DIR/demo.login")" = off ]
  echo "$BUNDLE" > "$STATE/items"
  once
  grep -qx 'Exec=/opt/Demo/demo --silent' "$AS/com.example.Demo.desktop"
}

@test "a Login Item added on the Mac with no entry ever seen: an entry that starts the app as usual" {
  echo "$BUNDLE" > "$STATE/items"
  once
  f=$(ls "$AS"/*.desktop)
  grep -qx 'Exec=demo --no-sandbox' "$f"
  grep -qx 'X-GNOME-Autostart-enabled=true' "$f"
}

@test "steady state: only the two reads" {
  app_entry --silent; once
  : > "$STATE/calls"
  once
  [ "$(sort "$STATE/calls" | tr '\n' ' ')" = "linux-call read mac-read " ]
}

@test "neither side on and none ever seen: nothing written" {
  once
  [ -z "$(login_items)" ]
  [ -z "$(ls "$AS")" ]
  ! grep -q 'mac-make\|mac-delete' "$STATE/calls"
}

@test "the container down: nothing changes" {
  app_entry --silent; touch "$STATE/down"
  once
  [ -z "$(login_items)" ]
  [ ! -e "$PORTHOLE_STATE_DIR/demo.login" ]
}

@test "once the app writes its own entry, it replaces the one made from the Mac, so unticking in the app turns it off" {
  echo "$BUNDLE" > "$STATE/items"
  once                                          # placeholder entry made
  app_entry --silent                            # the user ticks the app's own checkbox
  once
  [ "$(ls "$AS")" = com.example.Demo.desktop ]
  rm "$AS/com.example.Demo.desktop"             # ...and unticks it
  once
  [ -z "$(login_items)" ]
}
