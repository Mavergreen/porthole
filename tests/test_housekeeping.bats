#!/usr/bin/env bats
# Housekeeping: only Porthole-labeled objects, only disposables, never data (except `forget --delete-data`).
load test_helper
REPO="$BATS_TEST_DIRNAME/.."

# State: $FAKE/containers "name slug status", $FAKE/images "id slug dangling", $FAKE/volumes "name slug";
# slug "-" = unlabeled. Filters understood: label=dev.mavergreen.porthole.slug[=S], status=S, dangling=true.
hk_docker() {
  FAKE="$WORK/fake"; mkdir -p "$FAKE" "$WORK/bin"; : > "$FAKE/containers"; : > "$FAKE/images"; : > "$FAKE/volumes"
  export FAKE
  cat > "$WORK/bin/docker" <<'EOF'
#!/bin/sh
printf 'docker %s\n' "$*" >> "$STUB_LOG"
[ -f "$FAKE/down" ] && exit 1
lab= stat= dang=
scan() { while [ $# -gt 0 ]; do
  case "$1" in --filter) case "$2" in
      label=dev.mavergreen.porthole.slug=*) lab=${2#*slug=} ;;
      label=dev.mavergreen.porthole.slug) lab='*' ;;
      status=*) stat="$stat ${2#status=} " ;;
      dangling=true) dang=1 ;;
    esac; shift 2 ;; *) shift ;; esac; done; }
m() { [ -n "$lab" ] && [ "$1" != - ] && { [ "$lab" = '*' ] || [ "$lab" = "$1" ]; }; }
del() { grep -v "^$2 " "$FAKE/$1" > "$FAKE/$1.t" || true; mv "$FAKE/$1.t" "$FAKE/$1"; }
scan "$@"
case "$1 $2" in
  "info "*) exit 0 ;;
  "ps -a"|"ps -aq")
    while read -r n s st; do m "$s" || continue
      [ -z "$stat" ] || case "$stat" in *" $st "*) ;; *) continue ;; esac
      case "$2" in -aq) echo "$n" ;; *) echo "$n $s" ;; esac
    done < "$FAKE/containers" ;;
  "images -q") while read -r i s d; do m "$s" && echo "$i"; done < "$FAKE/images" ;;
  "image prune") while read -r i s d; do m "$s" && [ "$d" = 1 ] && del images "$i"; done < "$FAKE/images"; exit 0 ;;
  "volume ls") while read -r n s; do m "$s" && echo "$n"; done < "$FAKE/volumes" ;;
  "volume rm") del volumes "$3" ;;
  "rm -f"|"rm "*) eval "_n=\${$#}"; del containers "$_n" ;;
  "rmi -f") del images "$3" ;;
esac
exit 0
EOF
  chmod +x "$WORK/bin/docker"; export PATH="$WORK/bin:$PATH"
}

@test "cleanup removes stopped leftovers and dangling images of Porthole's, and nothing else" {
  hk_docker
  printf 'demo-gui demo exited\nold_step demo exited\nlive demo running\nclodefd - exited\n' > "$FAKE/containers"
  printf 'aaa demo 1\nbbb demo 0\nccc - 1\n' > "$FAKE/images"
  printf 'demo-gui-data demo\n' > "$FAKE/volumes"
  run sh -c 'PORTHOLE_LIB=1 PORTHOLE_SELF="$1"; . "$1"; porthole_cleanup' _ "$REPO/bin/porthole"
  grep -q '^demo-gui ' "$FAKE/containers"      # the app's own container stays (up recreates or starts it)
  ! grep -q '^old_step ' "$FAKE/containers" || return 1   # a stopped labeled leftover goes
  grep -q '^live ' "$FAKE/containers"          # running: never
  grep -q '^clodefd ' "$FAKE/containers"       # unlabeled: never
  ! grep -q '^aaa ' "$FAKE/images" || return 1   # dangling labeled image goes
  grep -q '^bbb ' "$FAKE/images"; grep -q '^ccc ' "$FAKE/images"
  grep -q '^demo-gui-data ' "$FAKE/volumes"    # data: never
}

@test "an unlabeled container or volume with a Porthole-looking name is never touched" {
  hk_docker
  printf 'legacy-gui - exited\n' > "$FAKE/containers"; printf 'legacy-gui-data -\n' > "$FAKE/volumes"
  run sh -c 'PORTHOLE_LIB=1 PORTHOLE_SELF="$1"; . "$1"; porthole_cleanup' _ "$REPO/bin/porthole"
  grep -q '^legacy-gui ' "$FAKE/containers"; grep -q '^legacy-gui-data ' "$FAKE/volumes"
}

state_demo() {
  printf 'demo-gui demo running\nother-gui other running\n' > "$FAKE/containers"
  printf 'img1 demo 0\nimg2 other 0\n' > "$FAKE/images"
  printf 'demo-gui-data demo\nother-gui-data other\n' > "$FAKE/volumes"
}

@test "forget --keep-data removes the app's containers and images, keeps its data" {
  hk_docker; state_demo
  run "$REPO/bin/porthole" forget demo --keep-data
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! grep -q '^demo-gui ' "$FAKE/containers" || return 1; ! grep -q '^img1 ' "$FAKE/images" || return 1
  grep -q '^demo-gui-data ' "$FAKE/volumes"
  grep -q '^other-gui ' "$FAKE/containers"; grep -q '^other-gui-data ' "$FAKE/volumes"
}

@test "forget --delete-data also deletes the app's data volumes, and only its" {
  hk_docker; state_demo
  run "$REPO/bin/porthole" forget demo --delete-data
  [ "$status" -eq 0 ]
  ! grep -q '^demo-gui-data ' "$FAKE/volumes" || return 1; grep -q '^other-gui-data ' "$FAKE/volumes"
}

@test "forget with no flag and no terminal keeps the data" {
  hk_docker; state_demo
  run "$REPO/bin/porthole" forget demo </dev/null
  [ "$status" -eq 0 ]
  grep -q '^demo-gui-data ' "$FAKE/volumes"
}

@test "forget when Docker is unreachable removes nothing and still succeeds" {
  hk_docker; state_demo; : > "$FAKE/down"
  run "$REPO/bin/porthole" forget demo --delete-data
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker isn't reachable"* ]]
  grep -q '^demo-gui-data ' "$FAKE/volumes"
}

@test "forget without a slug is a usage error" {
  hk_docker
  run "$REPO/bin/porthole" forget
  [ "$status" -eq 2 ]
}
