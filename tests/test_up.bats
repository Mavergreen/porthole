#!/usr/bin/env bats
# platform: host-agnostic
# `porthole up` must never run a container from an image that doesn't match the recipe it was
# handed: an image left behind under the same name (an older recipe, an older base) is rebuilt,
# and a container created from a superseded image is recreated -- its named volumes kept.

load test_helper

REPO="$BATS_TEST_DIRNAME/.."
LABEL=dev.mavergreen.porthole.recipe

# A docker fake with state: images carry a recipe label and an id, containers remember the id
# they were created from. State lives in $FAKE/{image,container}.<name>.
fake_docker() {
  FAKE="$WORK/fake"; mkdir -p "$FAKE" "$WORK/bin"
  export FAKE
  cat > "$WORK/bin/docker" <<'EOF'
#!/bin/sh
printf 'docker %s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "image inspect")
    shift 2; _fmt=""; [ "$1" = --format ] && { _fmt=$2; shift 2; }
    [ -f "$FAKE/image.$1" ] || exit 1
    case "$_fmt" in
      *Labels*) sed -n 1p "$FAKE/image.$1" ;;
      *.Id*)    sed -n 2p "$FAKE/image.$1" ;;
    esac ;;
  "container inspect")
    shift 2; _fmt=""; [ "$1" = -f ] && { _fmt=$2; shift 2; }
    [ -f "$FAKE/container.$1" ] || exit 1
    case "$_fmt" in
      *Running*) echo true ;;
      *.Image*)  cat "$FAKE/container.$1" ;;
    esac ;;
  "rm -f") rm -f "$FAKE/container.$3" ;;
  "images --format") cat "$FAKE/base-tags" 2>/dev/null ;;
  "rmi "*) : ;;
  "volume create") eval "_v=\${$#}"; touch "$FAKE/volume.$_v" ;;
  "start "*) : ;;
  *)
    case "$1" in
      build)
        shift; _lab="" _tag=""
        while [ $# -gt 1 ]; do
          case "$1" in
            --label) case "$2" in dev.mavergreen.porthole.recipe=*) _lab=${2#*=} ;; esac; shift 2 ;;
            -t) _tag=$2; shift 2 ;;
            *) shift ;;
          esac
        done
        _n=$(( $(cat "$FAKE/builds" 2>/dev/null || echo 0) + 1 )); echo "$_n" > "$FAKE/builds"
        printf '%s\nsha256:built%s\n' "$_lab" "$_n" > "$FAKE/image.$_tag" ;;
      run)
        _name=""; _img=""
        while [ $# -gt 0 ]; do
          case "$1" in --name) _name=$2; shift 2 ;; *) _img=$1; shift ;; esac
        done
        sed -n 2p "$FAKE/image.$_img" > "$FAKE/container.$_name" ;;
    esac ;;
esac
exit 0
EOF
  chmod +x "$WORK/bin/docker"
  export PATH="$WORK/bin:$PATH"
}

# A materialized-style spec + build context.
make_spec() {
  mkdir -p "$WORK/app/ctx"
  printf 'FROM ghcr.io/mavergreen/porthole-base:1\n' > "$WORK/app/ctx/Dockerfile"
  cat > "$WORK/app/demo.container" <<'EOF'
NAME='Linux Demo'
CONTAINER='demo-gui'
SLUG='demo'
EXTRA_VOLUMES='demo-cli:/cfg'
IMAGE='mavericks-demo'
BUILD_CONTEXT='ctx'
DATADIR='/data'
VOLUME='demo-gui-data'
EOF
  SPEC="$WORK/app/demo.container"
}

builds() { cat "$FAKE/builds" 2>/dev/null || echo 0; }


@test "first up builds the image, labelled with the recipe fingerprint, and runs it" {
  fake_docker; make_spec
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(builds)" -eq 1 ]
  grep -q -- "--label $LABEL=" "$STUB_LOG"
  [ -f "$FAKE/container.demo-gui" ]
}

@test "a second up with the same recipe neither rebuilds nor recreates" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC"
  : > "$STUB_LOG"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(builds)" -eq 1 ]
  ! grep -q '^docker rm' "$STUB_LOG" || false
  ! grep -q '^docker run' "$STUB_LOG" || false
}

@test "an unlabelled image already under the name (an older recipe) is rebuilt, not reused" {
  fake_docker; make_spec
  printf '<no value>\nsha256:legacy\n' > "$FAKE/image.mavericks-demo"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(builds)" -eq 1 ]
  [ "$(cat "$FAKE/container.demo-gui")" = sha256:built1 ]
}

@test "a changed recipe (e.g. a new base) rebuilds and recreates the container, keeping its volumes" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC"
  printf 'FROM ghcr.io/mavergreen/porthole-base:2\n' > "$WORK/app/ctx/Dockerfile"
  : > "$STUB_LOG"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(builds)" -eq 2 ]
  [ "$(cat "$FAKE/container.demo-gui")" = sha256:built2 ]
  grep -q '^docker rm -f demo-gui$' "$STUB_LOG"
  ! grep -q '^docker volume rm' "$STUB_LOG" || false
  grep -q -- '-v demo-gui-data:/data' "$STUB_LOG"
}

@test "a container made from an image that has since been replaced is recreated" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC"
  echo sha256:somethingelse > "$FAKE/container.demo-gui"
  : > "$STUB_LOG"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(builds)" -eq 1 ]
  [ "$(cat "$FAKE/container.demo-gui")" = sha256:built1 ]
}

@test "replacing an image removes the one it replaced" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC"
  printf 'FROM ghcr.io/mavergreen/porthole-base:2\n' > "$WORK/app/ctx/Dockerfile"
  : > "$STUB_LOG"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q '^docker rmi sha256:built1$' "$STUB_LOG"
}

@test "an up that changes nothing removes nothing" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC"
  : > "$STUB_LOG"
  "$REPO/bin/porthole" up "$SPEC"
  ! grep -q '^docker rmi' "$STUB_LOG" || false
}

# Each Porthole release pins a new ~1.4GB base; left behind, they fill the Docker VM.
@test "a rebuild untags older tags of the base it builds FROM, and only those" {
  fake_docker; make_spec
  printf 'ghcr.io/mavergreen/porthole-base:0\nghcr.io/mavergreen/porthole-base:1\n' > "$FAKE/base-tags"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q '^docker rmi ghcr.io/mavergreen/porthole-base:0$' "$STUB_LOG"
  ! grep -q '^docker rmi ghcr.io/mavergreen/porthole-base:1$' "$STUB_LOG" || false
}

@test "up labels the image, the container and every data volume with the slug" {
  fake_docker; make_spec
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q -- '^docker build .*--label dev.mavergreen.porthole.slug=demo' "$STUB_LOG"
  grep -q -- '^docker volume create --label dev.mavergreen.porthole.slug=demo demo-gui-data$' "$STUB_LOG"
  grep -q -- '^docker volume create --label dev.mavergreen.porthole.slug=demo demo-cli$' "$STUB_LOG"
  grep -q -- '^docker run .*--label dev.mavergreen.porthole.slug=demo' "$STUB_LOG"
}

@test "a build never leaves its step containers behind" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC"
  grep -q -- '^docker build .*--force-rm' "$STUB_LOG"
}
