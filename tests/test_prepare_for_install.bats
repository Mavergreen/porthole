#!/usr/bin/env bats
# platform: host-agnostic
# porthole prepare-for-install: an install opens each app's own launch window (--prepare) in the
# console user's session and waits for it, so the app is built before Installer finishes. It never
# fails the install.

load test_helper
REPO="$BATS_TEST_DIRNAME/.."

# Apps as materialize leaves them, plus stubs: pgrep finds alice's loginwindow (pid 123); launchctl
# logs what it would run, and fails for an app whose name is in $WORK/fail.
setup_apps() {
  mkdir -p "$WORK/bin" "$WORK/Applications" "$WORK/mg"
  printf '#!/bin/sh\nprintf "pgrep %%s\\n" "$*" >> "%s"\necho 123\n' "$STUB_LOG" > "$WORK/bin/pgrep"
  cat > "$WORK/bin/launchctl" <<EOF
#!/bin/sh
printf 'launchctl %s\n' "\$*" >> "$STUB_LOG"
case "\$*" in *"\$(cat "$WORK/fail" 2>/dev/null || echo none)"*) exit 1 ;; esac
exit 0
EOF
  chmod +x "$WORK/bin/pgrep" "$WORK/bin/launchctl"
  for a in Alpha Beta; do
    s=$(echo "$a" | tr 'A-Z' 'a-z')
    mkdir -p "$WORK/mg/$s/share/porthole/presets"
    printf 'APP=%s\n' "$a" > "$WORK/mg/$s/share/porthole/presets/$s.conf"
  done
  export PATH="$WORK/bin:$PATH" PORTHOLE_CONSOLE_USER=alice PORTHOLE_PRESETS_DIR="$WORK/mg"
}
conf() { printf '%s' "$WORK/mg/$1/share/porthole/presets/$1.conf"; }
prepares() { grep '^launchctl ' "$STUB_LOG"; }

@test "each named app is prepared in the user's session, in order" {
  setup_apps
  run "$REPO/bin/porthole" prepare-for-install --apps-dir "$WORK/Applications" "$(conf alpha)" "$(conf beta)"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(prepares)" = "launchctl bsexec 123 sudo -u alice -H $WORK/Applications/Linux Alpha.app/Contents/MacOS/Porthole --prepare $WORK/Applications/Linux Alpha.app/Contents/Resources/bin/alpha
launchctl bsexec 123 sudo -u alice -H $WORK/Applications/Linux Beta.app/Contents/MacOS/Porthole --prepare $WORK/Applications/Linux Beta.app/Contents/Resources/bin/beta" ] || { prepares; return 1; }
  grep -q '^pgrep -x -u alice loginwindow$' "$STUB_LOG"
}

@test "with no confs, every installed preset is prepared" {
  setup_apps
  run "$REPO/bin/porthole" prepare-for-install --apps-dir "$WORK/Applications"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(prepares | wc -l | tr -d ' ')" = 2 ] || { prepares; return 1; }
}

# An install to another disk must leave the running system alone.
@test "another volume: nothing runs, exit 0" {
  setup_apps; mkdir -p "$WORK/vol"
  run "$REPO/bin/porthole" prepare-for-install --root "$WORK/vol" "$(conf alpha)"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$(prepares)" ]
}

# Installed over ssh, or at the login window: no one to show a window to; the first launch builds.
@test "no one at the console: nothing runs, exit 0" {
  setup_apps
  run env PORTHOLE_CONSOLE_USER=root "$REPO/bin/porthole" prepare-for-install "$(conf alpha)"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$(prepares)" ]
}

@test "a failed prepare is logged, the next app still runs, and the install goes on" {
  setup_apps; echo "Linux Alpha" > "$WORK/fail"
  run "$REPO/bin/porthole" prepare-for-install --apps-dir "$WORK/Applications" "$(conf alpha)" "$(conf beta)"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Linux Alpha not prepared (status 1)"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"prepared Linux Beta"* ]] || { echo "$output"; return 1; }
}
