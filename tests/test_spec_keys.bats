#!/usr/bin/env bats
# platform: host-agnostic
# An app's spec (<slug>.container, rendered by generate-viewer) carries what the runtime tools need to
# give it native behaviour: its CLI, sockets, native-messaging hosts and URL schemes; and the engine
# tools find an installed app's spec by its slug.
load test_helper

render() {  # $1 = extra conf lines -> renders "$WORK/out/demo.container"
  mkdir -p "$WORK/conf" "$WORK/out"
  sed -n '/^APP=/,$p' "${BATS_TEST_DIRNAME}/../examples/thunderbird.conf" > "$WORK/conf/demo.conf"
  printf '%s\n' "$1" >> "$WORK/conf/demo.conf"
  PORTHOLE_BASE_REF=ghcr.io/mavergreen/porthole-base:latest \
    "${BATS_TEST_DIRNAME}/../bin/generate-viewer" "$WORK/conf/demo.conf" --out "$WORK/out" >/dev/null
}
spec() { ( . "$WORK/out/demo.container"; eval "printf '%s' \"\$$1\"" ); }

@test "the spec carries declared CLIs, sockets, native hosts and URL schemes, values intact" {
  render "CLI='op'
CLI_op='/usr/bin/op'
SOCKETS='ssh-agent'
SOCKET_ssh_agent='/c/a.sock ~/.x/a.sock'
URL_SCHEMES='sgnl x'
NATIVE_HOSTS='browser'
NATIVE_HOST_browser='/opt/h 1000:0'
NATIVE_HOST_browser_FILE='/etc/m /etc/c'
EXTRA_ENV='A=1 B=two'
APP_FLAGS=\"--x='it''s' \\\$HOME\""
  [ "$(spec CLI)" = op ]
  [ "$(spec CLI_op)" = /usr/bin/op ]
  [ "$(spec SOCKETS)" = ssh-agent ]
  [ "$(spec SOCKET_ssh_agent)" = '/c/a.sock ~/.x/a.sock' ]
  [ "$(spec URL_SCHEMES)" = 'sgnl x' ]
  [ "$(spec NATIVE_HOSTS)" = browser ]
  [ "$(spec NATIVE_HOST_browser)" = '/opt/h 1000:0' ]
  [ "$(spec NATIVE_HOST_browser_FILE)" = '/etc/m /etc/c' ]
  [ "$(spec APP_USER)" = thunderbird ]
  [ "$(spec APP_HOME)" = /home/thunderbird ]
  [ "$(spec APP_BIN)" = thunderbird ]
  [ "$(spec EXTRA_ENV)" = 'A=1 B=two' ]
  [ "$(spec APP_FLAGS)" = "--x='it''s' \$HOME" ]
}

@test "a conf without them renders them empty" {
  render ""
  [ -z "$(spec CLI)" ] && [ -z "$(spec SOCKETS)" ] && [ -z "$(spec URL_SCHEMES)" ] && [ -z "$(spec NATIVE_HOSTS)" ]
}

@test "a declared name with no definition is refused at generate time" {
  run sh -c 'cd "$1" && sed -n "/^APP=/,\$p" "$2" > d.conf && echo "SOCKETS=ssh-agent" >> d.conf &&
    "$3" d.conf --out o' _ "$WORK" "${BATS_TEST_DIRNAME}/../examples/thunderbird.conf" "${BATS_TEST_DIRNAME}/../bin/generate-viewer"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SOCKETS names 'ssh-agent' but SOCKET_ssh_agent is empty"* ]] || { echo "$output"; return 1; }
}

@test "spec_find finds an installed app's spec by slug, and says so when there is none" {
  mkdir -p "$WORK/A/Linux Demo.app/Contents/Resources" "$WORK/B"
  : > "$WORK/A/Linux Demo.app/Contents/Resources/demo.container"
  run sh -c '. "$1"; PORTHOLE_APPS_DIRS="$2:$3" spec_find demo' _ "${BATS_TEST_DIRNAME}/../bin/porthole-spec-lib.sh" "$WORK/B" "$WORK/A"
  [ "$status" -eq 0 ]
  [ "$output" = "$WORK/A/Linux Demo.app/Contents/Resources/demo.container" ]
  run sh -c '. "$1"; PORTHOLE_APPS_DIRS="$2" spec_find nope' _ "${BATS_TEST_DIRNAME}/../bin/porthole-spec-lib.sh" "$WORK/B"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no installed app for 'nope'"* ]]
}
