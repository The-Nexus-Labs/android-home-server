#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd adb
assert_adb_device
ensure_dirs

codename=$(device_codename)
model=$(device_prop ro.product.model)
fingerprint=$(device_prop ro.build.fingerprint)
android_version=$(device_prop ro.build.version.release)
lock_state=$(device_lock_state)
verified_boot=$(device_prop ro.boot.verifiedbootstate)
debuggable=$(device_prop ro.debuggable)

log "Connected device: $model ($codename)"
log "Android version: $android_version"
log "Fingerprint: $fingerprint"
log "Bootloader locked flag: $lock_state"
log "Verified boot state: $verified_boot"
log "Debuggable: $debuggable"

assert_device_matches_profile "$codename" "$DEVICE_CODENAME"

if [[ "$android_version" != "16" ]]; then
  warn "This workflow expects a recent Android 16-based stock or GrapheneOS userspace. Connected device reports Android $android_version."
fi

if [[ "$lock_state" == "1" ]]; then
  warn "Bootloader is still locked. Flashing cannot begin yet."
else
  log "Bootloader is already unlocked."
fi

cat <<EOF

Manual prerequisites still required on the phone before flashing:
  1. Remove Google accounts to avoid FRP.
  2. Enable OEM unlocking in Developer options.
  3. Confirm USB debugging stays enabled.
  4. Back up anything important; unlocking wipes the device.
  5. Be ready to complete the official GrapheneOS first-boot setup and re-enable USB debugging.
EOF
