#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/state.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/step.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/runtime.sh"

load_step_metadata() {
  local step_key=$1
  step_load_module "$(step_resolve_file "$step_key")"
}

step_label() {
  local step_key=$1
  load_step_metadata "$step_key"
  step_name
}

step_state() {
  local step_key=$1
  load_step_metadata "$step_key"
  step_current_state_key
}

mark_step_complete() {
  state_mark_complete "$(step_state "$1")"
}

step_completed() {
  local step_key=$1
  state_has "$(step_state "$step_key")"
}

run_step_if_needed() {
  local number=$1
  local total=$2
  local step_key=$3

  shift 3

  print_step_header "Step $number/$total: $(step_label "$step_key")"
  if "$RUN_STEP" "$step_key" test; then
    print_step_detail "$(step_label "$step_key") is already complete; skipping."
    mark_step_complete "$step_key"
    return 0
  fi

  "$RUN_STEP" "$step_key" apply "$@"
  mark_step_complete "$step_key"
}

print_session_header() {
  local model=$DEVICE_NAME
  local codename=$DEVICE_CODENAME

  if adb_ready; then
    model=$(device_prop ro.product.model)
    codename=$(device_codename)
  fi

  print_bootstrap_header "$DEVICE_NAME" "$model" "$codename"
}

state_load
require_cmd adb
require_cmd fastboot
require_cmd python3
ensure_dirs

print_session_header

print_step_header 'Step 1/16: Inspect the connected device'
if adb_ready; then
  "$RUN_STEP" inspect-device apply
elif fastboot_ready; then
  print_step_detail 'Device is currently in Fastboot Mode; Android-side inspection is limited until it boots again.'
else
  wait_for_adb_ready
  "$RUN_STEP" inspect-device apply
fi
mark_step_complete inspect-device

refresh_runtime_state

if [[ "$RUNTIME_GRAPHENEOS_READY" != '1' ]] && ! step_completed flash-grapheneos; then
  print_manual_block "Before continuing:
  1. Remove Google accounts to avoid FRP.
  2. Enable OEM unlocking in Developer options.
  3. Keep USB debugging enabled.
  4. Back up anything important.
"
  wait_for_enter 'Press Enter when the phone is ready for download and flashing: '
fi

run_step_if_needed 2 16 prepare-assets --download

print_step_header 'Step 3/16: Unlock the bootloader if needed'
refresh_runtime_state
if [[ "$RUNTIME_BOOTLOADER_UNLOCKED" == '1' ]] || step_completed unlock-bootloader; then
  print_step_detail 'Bootloader already unlocked; skipping unlock step.'
  mark_step_complete unlock-bootloader
else
  ensure_adb_ready
  "$RUN_STEP" unlock-bootloader apply || true
  wait_for_bootloader_unlocked
  mark_step_complete unlock-bootloader
fi

refresh_runtime_state
if [[ "$RUNTIME_GRAPHENEOS_READY" != '1' ]] && ! step_completed flash-grapheneos; then
  print_manual_block 'If the phone wiped and rebooted after unlocking, return it to Fastboot Mode now.'
  ensure_fastboot_ready
fi

print_step_header 'Step 4/16: Flash GrapheneOS'
refresh_runtime_state
if [[ "$RUNTIME_GRAPHENEOS_READY" == '1' ]]; then
  print_step_detail 'GrapheneOS is already installed; skipping flash step.'
  mark_step_complete flash-grapheneos
elif step_completed flash-grapheneos && [[ "$RUNTIME_FASTBOOT_READY" == '1' ]]; then
  print_step_detail 'GrapheneOS flash was already completed in a previous run; skipping reflash while the device is in Fastboot Mode.'
else
  ensure_fastboot_ready
  refresh_runtime_state
  if [[ "$RUNTIME_BOOTLOADER_UNLOCKED" != '1' ]]; then
    wait_for_bootloader_unlocked
    ensure_fastboot_ready
  fi
  "$RUN_STEP" flash-grapheneos apply
  mark_step_complete flash-grapheneos
fi

refresh_runtime_state
if [[ "$RUNTIME_GRAPHENEOS_READY" != '1' ]]; then
  print_manual_block "Complete the first GrapheneOS boot on the phone now.

Required on-device actions:
  1. Finish setup.
  2. Re-enable Developer options.
  3. Re-enable OEM unlocking.
  4. Re-enable USB debugging.
  5. Accept the ADB prompt.
"
  wait_for_adb_ready
fi

print_step_header 'Step 5/16: Install Magisk root'
refresh_runtime_state
if [[ "$RUNTIME_ROOT_READY" == '1' ]]; then
  print_step_detail 'Shell root is already available; skipping Magisk installation.'
  mark_step_complete install-magisk-root
elif [[ "$RUNTIME_MAGISK_RUNTIME_READY" == '1' ]]; then
  print_step_detail 'Magisk runtime is already present; waiting only for shell root approval.'
  wait_for_root_ready
  mark_step_complete install-magisk-root
else
  ensure_adb_ready
  "$RUN_STEP" install-magisk-root apply
  wait_for_adb_ready
  wait_for_root_ready
  mark_step_complete install-magisk-root
fi

run_step_if_needed 6 16 connect-wifi
run_step_if_needed 7 16 disable-wifi-mac-randomization
run_step_if_needed 8 16 enable-wifi-send-device-name
run_step_if_needed 9 16 disable-system-updater
run_step_if_needed 10 16 install-magisk-service
run_step_if_needed 11 16 install-termux
run_step_if_needed 12 16 stage-termux-bootstrap
run_step_if_needed 13 16 disable-magisk-ui-notification
run_step_if_needed 14 16 disable-magisk-shell-notification
run_step_if_needed 15 16 disable-magisk-termux-notification

print_step_header 'Step 16/16: Verify SSH and re-check every step'
"$RUN_STEP" verify-final-state apply
mark_step_complete verify-final-state