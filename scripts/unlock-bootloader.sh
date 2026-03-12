#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd adb
require_cmd fastboot
assert_adb_device

assert_device_matches_profile "$(device_codename)" "$DEVICE_CODENAME"

if [[ "$(device_lock_state)" != "1" ]]; then
  log "Bootloader already appears unlocked; skipping unlock flow."
  exit 0
fi

warn "Unlocking the bootloader will factory reset the phone."
maybe_prompt_destructive "Continue with bootloader unlock?" || die "aborted"

log "Rebooting to bootloader"
adb reboot bootloader
sleep 5
assert_fastboot_device

cat <<EOF

The phone is now in Fastboot Mode.

Next on the host, the script will run:
  fastboot flashing unlock

After that command is sent, the phone will show the unlock confirmation screen.

Manual action needed on the phone then:
  - Use volume keys to choose 'Unlock the bootloader'
  - Press power to confirm

EOF

fastboot flashing unlock
warn "If the phone rebooted automatically, wait for Android to boot and re-enable USB debugging afterward."
