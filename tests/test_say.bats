#!/usr/bin/env bats
REPO="$BATS_TEST_DIRNAME/.."
say() { sh -c '. "$1"; shift; "$@"' _ "$REPO/bin/porthole-say.sh" "$@"; }

@test "json_str escapes quotes, backslashes, tabs and newlines" {
  run say json_str "$(printf 'a"b\\c\td\ne')"
  [ "$output" = '"a\"b\\c\td\ne"' ]
}

@test "under the viewer, messages are JSON lines on stdout" {
  export PORTHOLE_PROTOCOL=1
  [ "$(say say_step 'Downloading')" = '{"t":"step","text":"Downloading"}' ]
  [ "$(say say_progress 0.5)" = '{"t":"progress","fraction":0.5}' ]
  [ "$(say say_error 'No space' 'details here')" = '{"t":"error","text":"No space","detail":"details here"}' ]
  [ "$(say say_ready /tmp/x.sock /tmp/i.icns)" = '{"t":"ready","socket":"/tmp/x.sock","icon":"/tmp/i.icns"}' ]
}

@test "say_ask sends the question and returns the viewer's answer, whatever the key order" {
  export PORTHOLE_PROTOCOL=1
  out=$(printf '%s\n' '{"choice":"Delete","t":"answer","id":"q1"}' | sh -c '. "$1"; a=$(say_ask q1 "Delete?" "Ask later" Keep Delete "Ask later"); echo "ANSWER=$a"' _ "$REPO/bin/porthole-say.sh")
  [[ "$out" == *'{"t":"ask","id":"q1","text":"Delete?","choices":["Keep","Delete","Ask later"]}'* ]] || return 1
  [[ "$out" == *"ANSWER=Delete"* ]] || return 1
}

@test "say_ask ignores an answer to another question and falls back to the default on EOF" {
  export PORTHOLE_PROTOCOL=1
  out=$(printf '%s\n' '{"t":"answer","id":"other","choice":"Delete"}' | sh -c '. "$1"; echo "ANSWER=$(say_ask q1 "?" "Ask later" Keep Delete)"' _ "$REPO/bin/porthole-say.sh")
  [[ "$out" == *"ANSWER=Ask later"* ]] || return 1
}

@test "outside the viewer, text goes to stderr and questions take their default" {
  unset PORTHOLE_PROTOCOL
  run sh -c '. "$1"; say_step Hello 2>&1 >/dev/null' _ "$REPO/bin/porthole-say.sh"
  [ "$output" = Hello ]
  run sh -c '. "$1"; say_progress 0.5; say_ready /s' _ "$REPO/bin/porthole-say.sh"
  [ -z "$output" ]
  run sh -c '. "$1"; say_ask q "?" Keep Keep Delete </dev/null' _ "$REPO/bin/porthole-say.sh"
  [ "$output" = Keep ]
}
