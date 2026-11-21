#!/usr/bin/env bats
# platform: host-agnostic
# launcher --open-url URL: a link to the app (its URL_SCHEMES, through the viewer's GetURL handler)
# runs the app's program with the URL in its container, which hands it to the running instance.
load test_helper

@test "--open-url runs the app's program with the URL, as its user on its display, and nothing else" {
  run env DOCKER_HOST=tcp://192.0.2.1:2376 THUNDERBIRD_NO_RECOVER=1 \
    "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird" --open-url 'mailto:a b@example.com?x=$y'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qxF 'docker exec -d -u thunderbird -e DISPLAY=:100 -e HOME=/home/thunderbird -e XDG_RUNTIME_DIR=/run/user/1000 thunderbird-gui thunderbird mailto:a b@example.com?x=$y' "$STUB_LOG" \
    || { cat "$STUB_LOG"; return 1; }
  ! grep -q 'porthole' "$STUB_LOG"
  [ "$(grep -c '^docker exec' "$STUB_LOG")" -eq 1 ]
}

@test "--open-url with no URL is refused" {
  run env DOCKER_HOST=tcp://192.0.2.1:2376 "${BATS_TEST_DIRNAME}/../examples/bin/thunderbird" --open-url
  [ "$status" -ne 0 ]
  ! grep -q '^docker exec' "$STUB_LOG"
}
