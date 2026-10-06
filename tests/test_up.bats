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
    case "$*" in *porthole-base*) [ -f "$FAKE/pulled" ] && exit 0; exit 1 ;; esac
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
      *.Config.Env*) cat "$FAKE/env.$1" 2>/dev/null ;;
    esac ;;
  "rm -f") rm -f "$FAKE/container.$3" ;;
  "images --format") cat "$FAKE/base-tags" 2>/dev/null ;;
  "manifest inspect") case "$*" in *@sha256:*) _dg=${3##*@}; if [ -f "$FAKE/manifest.$_dg" ]; then cat "$FAKE/manifest.$_dg"; else cat "$FAKE/manifest-by-digest" 2>/dev/null || exit 1; fi ;; *) cat "$FAKE/manifest" 2>/dev/null || exit 1 ;; esac ;;
  "images -q") echo img1 ;;
  "image prune") touch "$FAKE/pruned" ;;
  "rmi "*) : ;;
  "volume create") eval "_v=\${$#}"; touch "$FAKE/volume.$_v" ;;
  "start "*) : ;;
  *)
    case "$1" in
      pull)
        for l in aaaaaaaaaaaa bbbbbbbbbbbb; do echo "$l: Pulling fs layer"; done
        echo "aaaaaaaaaaaa: Pull complete"; echo "bbbbbbbbbbbb: Pull complete"
        touch "$FAKE/pulled" ;;
      build)
        echo "Step 1/2 : FROM x"; echo "Step 2/2 : RUN y"
        [ -f "$FAKE/build-fails" ] && { echo "boom" >&2; exit 1; }
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
        case "$*" in *"--entrypoint df"*)
          [ -f "$FAKE/free" ] || exit 1
          f=$(cat "$FAKE/free"); [ -f "$FAKE/pruned" ] && [ -f "$FAKE/free-after" ] && f=$(cat "$FAKE/free-after")
          printf 'Filesystem 1024-blocks Used Available Capacity Mounted\noverlay 18000000 1 %s 1%% /\n' "$f"; exit 0 ;;
        esac
        _name=""; _img=""; _env=""
        while [ $# -gt 0 ]; do
          case "$1" in --name) _name=$2; shift 2 ;; -e) _env="$_env$2
"; shift 2 ;; *) _img=$1; shift ;; esac
        done
        sed -n 2p "$FAKE/image.$_img" > "$FAKE/container.$_name"
        printf '%s' "$_env" > "$FAKE/env.$_name" ;;
    esac ;;
esac
exit 0
EOF
  chmod +x "$WORK/bin/docker"
  export PATH="$WORK/bin:$PATH"
  export PORTHOLE_CACHE_DIR="$WORK/cache"   # never this Mac's ~/Library/Caches
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

# Builds now happen at install (--image-only), and the launch after one finds nothing to rebuild:
# the old base must go when the build does, or each Porthole release leaves ~1.4 GB behind.
@test "an install-time build untags older tags of the base too" {
  fake_docker; make_spec
  printf 'ghcr.io/mavergreen/porthole-base:0\nghcr.io/mavergreen/porthole-base:1\n' > "$FAKE/base-tags"
  run "$REPO/bin/porthole" up --image-only "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q '^docker rmi ghcr.io/mavergreen/porthole-base:0$' "$STUB_LOG" || { cat "$STUB_LOG"; return 1; }
  ! grep -q '^docker rmi ghcr.io/mavergreen/porthole-base:1$' "$STUB_LOG" || false
}

# Signal showed every message four hours ahead: its container ran UTC on a Mac in New York. A
# container takes the Mac's time zone when it's created, and a launch after the Mac's zone has changed
# (travel) recreates it -- apps read the zone only when they start.
@test "a new container gets the Mac's time zone" {
  fake_docker; make_spec
  PORTHOLE_HOST_TZ=America/New_York "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  grep -qx 'PORTHOLE_TZ=America/New_York' "$FAKE/env.demo-gui" || { cat "$FAKE/env.demo-gui"; return 1; }
}

@test "a launch in a new time zone recreates the container, volumes kept" {
  fake_docker; make_spec
  PORTHOLE_HOST_TZ=America/New_York "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  : > "$STUB_LOG"
  PORTHOLE_HOST_TZ=Europe/Berlin "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  grep -q '^docker rm -f demo-gui$' "$STUB_LOG" || { cat "$STUB_LOG"; return 1; }
  grep -qx 'PORTHOLE_TZ=Europe/Berlin' "$FAKE/env.demo-gui" || return 1
  ! grep -q '^docker volume rm' "$STUB_LOG" || false
}

@test "a launch in the same time zone keeps the container" {
  fake_docker; make_spec
  PORTHOLE_HOST_TZ=America/New_York "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  : > "$STUB_LOG"
  PORTHOLE_HOST_TZ=America/New_York "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  ! grep -q '^docker rm -f' "$STUB_LOG" || false
}

# 10.9 links /etc/localtime into /usr/share/zoneinfo; newer macOS into /var/db/timezone/zoneinfo.
@test "the Mac's time zone is read from its localtime link, wherever the zoneinfo lives" {
  ln -s /usr/share/zoneinfo/America/New_York "$WORK/lt-old"
  ln -s /var/db/timezone/zoneinfo/Europe/Berlin "$WORK/lt-new"
  [ "$(lib host_tz "$WORK/lt-old")" = America/New_York ] || return 1
  [ "$(lib host_tz "$WORK/lt-new")" = Europe/Berlin ] || return 1
  [ -z "$(lib host_tz "$WORK/no-such-link")" ]
}

@test "up labels the image, the container and every data volume with the slug" {
  fake_docker; make_spec
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q -- '^docker build .*--label dev.mavergreen.porthole.slug=demo' "$STUB_LOG"
  grep -qF -- 'docker volume create --label dev.mavergreen.porthole.slug=demo --label dev.mavergreen.porthole.name=Linux Demo demo-gui-data' "$STUB_LOG" || return 1
  grep -qF -- 'docker volume create --label dev.mavergreen.porthole.slug=demo --label dev.mavergreen.porthole.name=Linux Demo demo-cli' "$STUB_LOG" || return 1
  grep -q -- '^docker run .*--label dev.mavergreen.porthole.slug=demo' "$STUB_LOG"
}

@test "a build never leaves its step containers behind" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC"
  grep -q -- '^docker build .*--force-rm' "$STUB_LOG"
}

@test "under the viewer, up pulls the base with layer progress, then reports build steps" {
  fake_docker; make_spec
  printf '{"layers":[{"size":3000000,"digest":"sha256:aaaaaaaaaaaa00"},{"size":1000000,"digest":"sha256:bbbbbbbbbbbb00"}]}\n' > "$FAKE/manifest"
  output=$(PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC" 2>/dev/null) || { echo "$output"; return 1; }
  [[ "$output" == *'{"t":"step","text":"Downloading the Linux runtime"}
{"t":"progress","fraction":0.75}
{"t":"progress","fraction":1}
{"t":"step","text":"Building'* ]] || { echo "$output"; return 1; }
  [[ "$output" == *'{"t":"step","text":"Building Linux Demo (2/2)"}'* ]] || return 1
  ! grep -q 'osascript' "$STUB_LOG" || return 1
}

# docker pull's own words, as a terminal shows them (cursor moves, carriage returns): the base's
# first layer is already here; the other two download, then extract, with byte counts.
tty_pull() {
  e=$(printf '\033'); r=$(printf '\r')
  printf 'aaaaaaaaaaaa: Already exists\n'
  for l in "bbbbbbbbbbbb: Pulling fs layer" "cccccccccccc: Pulling fs layer" "cccccccccccc: Waiting" \
           "bbbbbbbbbbbb: Downloading [=>   ]  1.5MB/3MB" "bbbbbbbbbbbb: Download complete" \
           "bbbbbbbbbbbb: Extracting [=>   ]  1.5MB/3MB" "cccccccccccc: Downloading [=>   ]  500kB/1MB" \
           "bbbbbbbbbbbb: Pull complete" "cccccccccccc: Download complete" "cccccccccccc: Pull complete"; do
    printf '%s[1A%s[2K%s%s %s%s[1B' "$e" "$e" "$r" "$l" "$r" "$e"
  done
  printf 'Digest: sha256:0123\r\nStatus: Downloaded newer image\r\n'
}
# Run one of porthole's functions, sourced in its own shell (porthole sets -eu).
lib() { sh -c 'PORTHOLE_LIB=1 PORTHOLE_SELF="$1"; . "$1"; shift; "$@"' _ "$REPO/bin/porthole" "$@"; }
SIZES='aaaaaaaaaaaa 1000000
bbbbbbbbbbbb 3000000
cccccccccccc 1000000'

# The bar used to read 100% from the first line: a layer already here counted as one of one done.
@test "pull progress counts the bytes still to fetch, downloaded then extracted, rising from the start" {
  out=$(tty_pull | lib pull_fractions "$SIZES" 2>/dev/null)
  [ "$(printf '%s\n' "$out" | tr '\n' ' ')" = "0.1875 0.375 0.5625 0.625 0.8125 0.875 1 " ] || { echo "$out"; return 1; }
}

@test "without a terminal, pull progress still weighs each layer by its size" {
  out=$(printf '%s\n' "aaaaaaaaaaaa: Already exists" "bbbbbbbbbbbb: Pulling fs layer" "cccccccccccc: Pulling fs layer" \
    "bbbbbbbbbbbb: Download complete" "cccccccccccc: Download complete" "bbbbbbbbbbbb: Pull complete" \
    "cccccccccccc: Pull complete" | lib pull_fractions "$SIZES" 2>/dev/null)
  [ "$(printf '%s\n' "$out" | tr '\n' ' ')" = "0.375 0.5 0.875 1 " ] || { echo "$out"; return 1; }
}

# With no sizes to weigh (no manifest), the bar stays indeterminate rather than claiming anything.
@test "pull progress with no layer sizes claims nothing until bytes are reported" {
  out=$(printf '%s\n' "aaaaaaaaaaaa: Already exists" "bbbbbbbbbbbb: Pulling fs layer" | lib pull_fractions "" 2>/dev/null)
  [ -z "$out" ] || { echo "$out"; return 1; }
}

@test "layer_sizes names each linux/amd64 layer by the id docker pull prints" {
  fake_docker
  printf '{"config":{"size":999,"digest":"sha256:ffffffffffff00"},"layers":[{"mediaType":"x","size":600,"digest":"sha256:0123456789abcdef"},{"digest":"sha256:fedcba9876543210","size":400,"mediaType":"x"}]}\n' > "$FAKE/manifest"
  [ "$(lib layer_sizes ghcr.io/mavergreen/porthole-base:1 | tr '\n' ' ')" = "0123456789ab 600 fedcba987654 400 " ]
}

@test "every stdout line from up under the viewer is a protocol message" {
  fake_docker; make_spec
  out=$(PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC" 2>/dev/null)
  printf '%s\n' "$out" | while IFS= read -r l; do case "$l" in '{"t":'*) ;; *) echo "stray: $l"; exit 1 ;; esac; done
}

@test "an already-present base is not pulled again" {
  fake_docker; make_spec; touch "$FAKE/pulled"
  "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  ! grep -q '^docker pull' "$STUB_LOG" || return 1
}

@test "up records the image it built" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  [ "$(cat "$WORK/cache/demo.image")" = sha256:built1 ]
}

# An install prepares the image while the app may be open and in use: its container must be left alone.
@test "--image-only builds but leaves the container alone" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  printf 'RUN new\n' >> "$WORK/app/ctx/Dockerfile"
  : > "$STUB_LOG"
  run "$REPO/bin/porthole" up --image-only "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$FAKE/container.demo-gui")" = sha256:built1 ] || return 1
  ! grep -q '^docker rm -f' "$STUB_LOG" || return 1
  [ "$(cat "$WORK/cache/demo.image")" = sha256:built2 ]
}

# A build holding an app's lock, as ps shows one: a porthole process.
holder() { sh -c 'sleep "$1"; :' porthole-up "$1" >/dev/null 2>&1 & echo $!; }   # two commands: sh stays, so ps shows it

# A lock outlives a power loss in ~/Library/Caches; if its pid comes back as some other process, it
# must not keep the app from opening -- silently, if that lock was an install's.
@test "a lock whose pid is now some other process is reclaimed" {
  fake_docker; make_spec
  mkdir -p "$WORK/cache/demo.lock"; sleep 3 & echo $! > "$WORK/cache/demo.lock/pid"; : > "$WORK/cache/demo.lock/shown"
  output=$(PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC" 2>/dev/null) || { echo "$output"; return 1; }
  [[ "$output" != *'"t":"quiet"'* ]] || { echo "$output"; return 1; }
  [ ! -d "$WORK/cache/demo.lock" ]
}

@test "a second up waits for a build in progress, then goes on" {
  fake_docker; make_spec
  mkdir -p "$WORK/cache/demo.lock"; holder 3 > "$WORK/cache/demo.lock/pid"
  output=$(PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC" 2>/dev/null) || { echo "$output"; return 1; }
  [[ "$output" == *'{"t":"step","text":"Waiting for Linux Demo'"'"'s update to finish"}'* ]] || { echo "$output"; return 1; }
  [ -f "$FAKE/container.demo-gui" ]
}

# Opening the app while an install builds it: that build's own window already shows the progress, so
# the launch waits without a second window on top of it.
@test "a launch waiting on a build that has its own window waits quietly" {
  fake_docker; make_spec
  mkdir -p "$WORK/cache/demo.lock"; holder 2 > "$WORK/cache/demo.lock/pid"; : > "$WORK/cache/demo.lock/shown"
  output=$(PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC" 2>/dev/null) || { echo "$output"; return 1; }
  [[ "$output" == *'{"t":"quiet"}'* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"Waiting for"* ]] || { echo "$output"; return 1; }
}

# A build with no window (an install over ssh, op's CLI): the launch shows where that build is.
@test "a launch waiting on a headless build shows that build's progress" {
  fake_docker; make_spec
  mkdir -p "$WORK/cache/demo.lock"; holder 2 > "$WORK/cache/demo.lock/pid"
  printf '%s\n' '{"t":"step","text":"Building Linux Demo (3/9)"}' '{"t":"progress","fraction":0.33}' > "$WORK/cache/demo.lock/progress"
  output=$(PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC" 2>/dev/null) || { echo "$output"; return 1; }
  [[ "$output" == *'{"t":"step","text":"Building Linux Demo (3/9)"}
{"t":"progress","fraction":0.33}'* ]] || { echo "$output"; return 1; }
}

# What a waiting launch reads: whether this build has a window, and where it has got to.
@test "a build under a window marks its lock so, and records its progress there" {
  fake_docker; make_spec
  sed -i '' 's|^      build)$|      build) cp -R "$PORTHOLE_CACHE_DIR/demo.lock" "$FAKE/seen-lock" 2>/dev/null|' "$WORK/bin/docker"
  PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  [ -f "$FAKE/seen-lock/shown" ] || { ls -la "$FAKE/seen-lock"; return 1; }
  grep -q '"t":"step","text":"Downloading the Linux runtime"' "$FAKE/seen-lock/progress" || { cat "$FAKE/seen-lock/progress"; return 1; }
}

# A build killed outright (Installer force-quit, power loss) must not block every launch after it.
@test "a lock left by a dead build is reclaimed" {
  fake_docker; make_spec
  true & _dead=$!; wait "$_dead"
  mkdir -p "$WORK/cache/demo.lock"; echo "$_dead" > "$WORK/cache/demo.lock/pid"
  output=$(PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC" 2>/dev/null) || { echo "$output"; return 1; }
  [[ "$output" != *"Waiting for"* ]] || { echo "$output"; return 1; }
  [ ! -d "$WORK/cache/demo.lock" ]
}

# porthole exec ends by exec'ing docker in the same process, so up's exit trap never runs; a long
# command (op's bridges) would hold the app's lock and stall every launch.
@test "porthole exec releases the app's lock before running the command" {
  fake_docker; make_spec
  "$REPO/bin/porthole" exec "$SPEC" -- true >/dev/null 2>&1
  [ ! -d "$WORK/cache/demo.lock" ]
}

# A failed --rebuild leaves the old image, whose recipe label still matches; that must not pass.
@test "a failed --rebuild is reported, not mistaken for the old image" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC" >/dev/null 2>&1
  : > "$FAKE/build-fails"
  run "$REPO/bin/porthole" up --rebuild "$SPEC"
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"image build failed"* ]] || return 1
}

manifest_1gb() {
  printf '{"config":{"size":999},"layers":[{"size":600000000},{"size":400000000}]}\n' > "$FAKE/manifest"
}

@test "enough space: up proceeds" {
  fake_docker; make_spec; manifest_1gb; echo 9000000 > "$FAKE/free"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "short, then enough after cleanup: up cleans and proceeds" {
  fake_docker; make_spec; manifest_1gb; echo 1000000 > "$FAKE/free"; echo 9000000 > "$FAKE/free-after"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # cleanup ran BEFORE the build (up also cleans after every run, so "a prune happened" proves nothing)
  awk '/^docker image prune/ && !p { p = NR } /^docker build/ { b = NR } END { exit !(p && b && p < b) }' "$STUB_LOG"
}

@test "still short after cleanup: an error with both numbers, exit 3, nothing built" {
  fake_docker; make_spec; manifest_1gb; echo 1000000 > "$FAKE/free"; echo 2900000 > "$FAKE/free-after"
  run env PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 3 ]
  [[ "$output" == *'"t":"error"'* ]] || return 1
  [[ "$output" == *"needs about 3.8 GB"* ]] || return 1
  [[ "$output" == *"has 2.8 GB free"* ]] || return 1
  ! grep -q '^docker build' "$STUB_LOG" || return 1
}

@test "a failed estimate or measurement never blocks" {
  fake_docker; make_spec                       # no manifest, no free file
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# Registries and docker versions print the manifest compact or pretty; the estimate must not care.
@test "a pretty-printed manifest is summed the same as a compact one" {
  fake_docker; make_spec
  printf '{\n  "config": {\n    "size": 999\n  },\n  "layers": [\n    {\n      "size": 600000000\n    },\n    {\n      "size": 400000000\n    }\n  ]\n}\n' > "$FAKE/manifest"
  echo 1000000 > "$FAKE/free"; echo 2900000 > "$FAKE/free-after"
  run env PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"needs about 3.8 GB"* ]] || return 1
}

@test "a multi-platform base is estimated from its linux/amd64 image, not the index" {
  fake_docker; make_spec
  printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","size":1000,"digest":"sha256:aaa","platform":{"architecture":"arm64","os":"linux"}},{"mediaType":"application/vnd.oci.image.manifest.v1+json","size":1000,"digest":"sha256:bbb","platform":{"architecture":"amd64","os":"linux"}}]}\n' > "$FAKE/manifest"
  printf '{"config":{"size":999},"layers":[{"size":600000000},{"size":400000000}]}\n' > "$FAKE/manifest-by-digest"
  echo 1000000 > "$FAKE/free"; echo 2900000 > "$FAKE/free-after"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 3 ] || { echo "$output"; return 1; }
  grep -q 'manifest inspect ghcr.io/mavergreen/porthole-base@sha256:bbb' "$STUB_LOG"
}

@test "a multi-platform index is read whatever its key order or layout" {
  fake_docker; make_spec
  printf '{\n "manifests": [\n  {"digest": "sha256:aaa", "mediaType": "application/vnd.oci.image.manifest.v1+json", "platform": {"os": "linux", "architecture": "arm64"}, "size": 1000},\n  {"digest": "sha256:bbb", "mediaType": "application/vnd.oci.image.manifest.v1+json", "platform": {"os": "linux", "architecture": "amd64"}, "size": 1000}\n ],\n "mediaType": "application/vnd.oci.image.index.v1+json"\n}\n' > "$FAKE/manifest"
  printf '{"config":{"size":999},"layers":[{"size":600000000},{"size":400000000}]}\n' > "$FAKE/manifest-by-digest"
  echo 1000000 > "$FAKE/free"; echo 2900000 > "$FAKE/free-after"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 3 ] || { echo "$output"; return 1; }
  grep -q 'manifest inspect ghcr.io/mavergreen/porthole-base@sha256:bbb' "$STUB_LOG"
}

@test "a base pinned by digest is looked up by repository and platform digest" {
  fake_docker; make_spec
  printf 'FROM ghcr.io/mavergreen/porthole-base@sha256:ccc\n' > "$WORK/app/ctx/Dockerfile"
  printf '{"manifests":[{"mediaType":"x","size":1000,"digest":"sha256:bbb","platform":{"architecture":"amd64","os":"linux"}}]}\n' > "$FAKE/manifest.sha256:ccc"
  printf '{"config":{"size":999},"layers":[{"size":600000000},{"size":400000000}]}\n' > "$FAKE/manifest-by-digest"
  echo 1000000 > "$FAKE/free"; echo 2900000 > "$FAKE/free-after"
  run "$REPO/bin/porthole" up "$SPEC"
  grep -q 'manifest inspect ghcr.io/mavergreen/porthole-base@sha256:bbb$' "$STUB_LOG" || { grep manifest "$STUB_LOG"; return 1; }
}

@test "up logs each stage under the app's name, so a slow launch can be timed afterwards" {
  fake_docker; make_spec
  "$REPO/bin/porthole" up "$SPEC" 2>/dev/null
  echo "sha256:other" > "$FAKE/container.demo-gui"   # left on an older image: recreated
  : > "$STUB_LOG"
  run "$REPO/bin/porthole" up "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  marks=$(sed -n 's/^logger -t porthole demo: //p' "$STUB_LOG")
  expected='up: locked
up: image current
up: recreating container
up: container running
up: cleaned up'
  [ "$marks" = "$expected" ] || { echo "$marks"; return 1; }
}

@test "up's steps are never routine" {
  fake_docker; make_spec
  output=$(PORTHOLE_PROTOCOL=1 "$REPO/bin/porthole" up "$SPEC" 2>/dev/null) || { echo "$output"; return 1; }
  [[ "$output" == *'"Building Linux Demo (1/2)"'* ]] || { echo "$output"; return 1; }
  [[ "$output" != *'"routine"'* ]] || { echo "$output"; return 1; }
}
