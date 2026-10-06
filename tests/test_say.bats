#!/usr/bin/env bats
# platform: host-agnostic
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
  [ "$(say say_ready /tmp/x.sock /tmp/i.icns)" = '{"t":"ready","socket":"/tmp/x.sock","icon":"/tmp/i.icns","image":""}' ]
}

@test "say_ready carries the image the app is running" {
  export PORTHOLE_PROTOCOL=1
  [ "$(say say_ready /s /i sha256:x)" = '{"t":"ready","socket":"/s","icon":"/i","image":"sha256:x"}' ]
}

@test "say_prepared is one protocol line, and silent outside the viewer" {
  [ "$(PORTHOLE_PROTOCOL=1 say say_prepared)" = '{"t":"prepared"}' ]
  [ -z "$(say say_prepared 2>&1)" ]
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

@test "an error carrying escape sequences and invalid UTF-8 is still one valid JSON line" {
  out=$(sh -c '. "$1"; PORTHOLE_PROTOCOL=1 say_error "$(printf "bad \033[31mred")" "$(printf "tail \377\376 end\a")" 7>&1' _ "$REPO/bin/porthole-say.sh")
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || { echo "$out"; return 1; }
  py=$(command -v python3 || command -v python) || skip "needs a python to parse JSON"
  printf '%s' "$out" | "$py" -c 'import json,sys; m=json.loads(sys.stdin.read()); assert m["t"]=="error" and "red" in m["text"] and "end" in m["detail"], m'
}

@test "say_mark puts a line in the system log under the app's name, and never fails" {
  export STUB_LOG="$BATS_TEST_TMPDIR/log" PATH="$BATS_TEST_DIRNAME/stubs:$PATH" PORTHOLE_LOG_NAME=demo
  run say say_mark 'up: start'
  [ "$status" -eq 0 ]
  grep -qx 'logger -t porthole demo: up: start' "$STUB_LOG"
  run env PATH=/nonexistent /bin/sh -c '. "$1"; say_mark x' _ "$REPO/bin/porthole-say.sh"
  [ "$status" -eq 0 ]
}

@test "each step a launch shows is also in the system log" {
  export STUB_LOG="$BATS_TEST_TMPDIR/log" PATH="$BATS_TEST_DIRNAME/stubs:$PATH" PORTHOLE_LOG_NAME=demo
  say say_step 'Downloading' 2>/dev/null
  grep -qx 'logger -t porthole demo: step: Downloading' "$STUB_LOG"
}

@test "say_routine is a step marked routine under the viewer" {
  export PORTHOLE_PROTOCOL=1
  [ "$(say say_routine 'Checking')" = '{"t":"step","text":"Checking","routine":true}' ]
}

@test "outside the viewer say_routine prints like say_step" {
  unset PORTHOLE_PROTOCOL
  run sh -c '. "$1"; say_routine Hello 2>&1 >/dev/null' _ "$REPO/bin/porthole-say.sh"
  [ "$output" = Hello ]
}

@test "say_routine is marked in the system log" {
  export STUB_LOG="$BATS_TEST_TMPDIR/log" PATH="$BATS_TEST_DIRNAME/stubs:$PATH" PORTHOLE_LOG_NAME=demo
  say say_routine 'Checking' 2>/dev/null
  grep -qx 'logger -t porthole demo: step: Checking' "$STUB_LOG"
}
