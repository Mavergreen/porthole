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

# spec_running CONTAINER: exit 0 iff the container is running.
spec_running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }
