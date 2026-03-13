#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd adb
require_cmd python3
assert_adb_device

adb_root id >/dev/null 2>&1 || die "root is not available yet; run ./scripts/root-magisk.sh first"

action=${1:-disable}
if [[ $# -gt 0 ]]; then
  shift
fi

if [[ $# -eq 0 ]]; then
  set -- shell com.termux
fi

case "$action" in
  disable) value=0 ;;
  enable) value=1 ;;
  *) die "usage: $0 [disable|enable] [shell|package ...]" ;;
esac

magisk_set_su_notification_ui_value "$value"
if [[ "$value" == "0" ]]; then
  log "Magisk UI Superuser notification set to OFF"
else
  log "Magisk UI Superuser notification set to TOAST"
fi

for target in "$@"; do
  if [[ "$target" == "shell" ]]; then
    if ! magisk_set_policy_notification_by_uid 2000 "$value" shell; then
      warn "Magisk policy row for shell does not exist yet; grant shell root once and rerun this script"
    fi
    continue
  fi

  if ! adb_package_installed "$target"; then
    warn "Package $target is not installed; skipping"
    continue
  fi

  if ! magisk_set_policy_notification_for_package "$target" "$value"; then
    warn "Magisk policy row for $target does not exist yet; grant root to that app once and rerun this script"
  fi
done
