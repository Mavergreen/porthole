# platform: macOS-only -- finds apps in the Mac's Applications folders and reaches the Docker VM
# porthole-spec-lib.sh -- sourced by the engine's runtime tools (porthole-cli, porthole-follow,
# porthole-native-host): find an installed app's spec by slug, and reach its container.

# spec_find SLUG: print the first Contents/Resources/SLUG.container among the apps in
# PORTHOLE_APPS_DIRS (colon-separated; default /Applications and ~/Applications), or fail saying so.
spec_find() {
  _sf_ifs=$IFS; IFS=:
  for _sf_d in ${PORTHOLE_APPS_DIRS:-/Applications:$HOME/Applications}; do
    IFS=$_sf_ifs
    for _sf_s in "$_sf_d"/*.app/Contents/Resources/"$1".container; do
      [ -f "$_sf_s" ] && { printf '%s\n' "$_sf_s"; return 0; }
    done
    IFS=:
  done
  IFS=$_sf_ifs
  echo "no installed app for '$1'" >&2
  return 1
}

# spec_docker_env: point docker at the VM, as the app launchers do, unless the caller already has.
spec_docker_env() {
  [ -n "${DOCKER_HOST:-}${DOCKER_CONTEXT:-}" ] && return 0
  PATH="$PATH:/usr/local/mavergreen/bin"; export PATH
  eval "$(docker-machine env "${PORTHOLE_MACHINE:-default}" 2>/dev/null | grep '^export ')" || :
}

# spec_docker_unreachable: exit 0 iff a docker error on stdin is the client failing to reach the VM
# (not anything a program in the container said).
spec_docker_unreachable() { grep -qE '^(error during connect|Cannot connect to the Docker daemon)'; }

# spec_up NAME CONTAINER: exit 0 iff the container is running; otherwise say why, exit 1.
spec_up() {
  _su=$(docker inspect -f '{{.State.Running}}' "$2" 2>&1)
  [ "$_su" = true ] && return 0
  if printf '%s\n' "$_su" | spec_docker_unreachable; then
    echo "$1 can't be reached: the Docker VM isn't answering (check Container Tools)." >&2
  else
    echo "$1 isn't running; open it first." >&2
  fi
  return 1
}
