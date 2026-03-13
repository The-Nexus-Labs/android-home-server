#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd adb
assert_adb_device

resolve_updater_package() {
  if [[ -n "${SYSTEM_UPDATER_PACKAGE:-}" ]]; then
    printf '%s\n' "$SYSTEM_UPDATER_PACKAGE"
    return 0
  fi

  if adb_package_installed app.seamlessupdate.client || is_grapheneos_build; then
    printf '%s\n' 'app.seamlessupdate.client'
    return 0
  fi

  return 1
}

resolve_updater_label() {
  if [[ -n "${SYSTEM_UPDATER_LABEL:-}" ]]; then
    printf '%s\n' "$SYSTEM_UPDATER_LABEL"
    return 0
  fi

  if [[ "$UPDATER_PACKAGE" == 'app.seamlessupdate.client' ]]; then
    printf '%s\n' 'GrapheneOS System Updater'
    return 0
  fi

  printf '%s\n' 'system updater'
}

UPDATER_PACKAGE=${UPDATER_PACKAGE:-$(resolve_updater_package || true)}
UPDATE_MODE=${1:-disable}

[[ -n "$UPDATER_PACKAGE" ]] || die "unable to detect a supported system updater implementation for this OS"

if ! adb_package_installed "$UPDATER_PACKAGE"; then
  die "system updater package not found: $UPDATER_PACKAGE"
fi

UPDATER_LABEL=$(resolve_updater_label)

case "${UPDATE_MODE,,}" in
  disable|disabled|off|manual)
    log "Disabling $UPDATER_LABEL"
    adb shell pm disable-user --user 0 "$UPDATER_PACKAGE" >/dev/null
    ;;
  enable|enabled|on|auto|automatic)
    log "Enabling $UPDATER_LABEL"
    adb shell pm enable --user 0 "$UPDATER_PACKAGE" >/dev/null
    ;;
  status)
    ;;
  *)
    die "unsupported update mode: $UPDATE_MODE (use disable, enable or status)"
    ;;
esac

if adb shell pm list packages -d 2>/dev/null | tr -d '\r' | grep -qx "package:$UPDATER_PACKAGE"; then
  cat <<EOF

Update mode: disabled
$UPDATER_LABEL is disabled.
Use ./scripts/configure-system-updater.sh enable before taking managed updates.
EOF
else
  cat <<EOF

Update mode: enabled
$UPDATER_LABEL is enabled.
EOF
fi