#!/usr/bin/env bats
# platform: host-agnostic
# Porthole runs every app in a container, so it is the product that requires Container Tools; the
# presets require only Porthole. shipyard's stage_product.sh --requires generates the check.
REPO="$BATS_TEST_DIRNAME/.."

@test "the package requires Container Tools, through shipyard's generated check" {
  grep -q -- '--requires container-tools' "$REPO/packaging/macos/build_pkg.sh"
}

@test "no hand-written requirement check is left to drift" {
  [ ! -e "$REPO/packaging/macos/preinstall-hook.sh" ] || return 1
  ! grep -q -- '--preinstall-hook' "$REPO/packaging/macos/build_pkg.sh" || return 1
}

# After re-materializing every preset (a new base changes each app's recipe), the install builds them
# all, each in its own window, before Installer finishes.
@test "postinstall prepares every app after re-materializing" {
  h="$REPO/packaging/macos/postinstall-hook.sh"
  grep -q 'prepare-for-install --root "$ROOT" --apps-dir "$ROOT/Applications"' "$h" || return 1
  [ "$(grep -n 'materialize' "$h" | tail -1 | cut -d: -f1)" -lt "$(grep -n 'prepare-for-install' "$h" | cut -d: -f1)" ]
}
