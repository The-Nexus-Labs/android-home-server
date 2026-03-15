#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

INTERACTIVE_FORCE=0

usage() {
  cat <<'EOF'
usage: ./src/bootstrap-interactive.sh [--force]

Options:
  --force    Reflash GrapheneOS and rerun every post-flash step without skipping.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      INTERACTIVE_FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[x] unsupported argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

export INTERACTIVE_FORCE

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
  local force_step=0

  shift 3

  if [[ "$INTERACTIVE_FORCE" == '1' ]] && (( number >= 5 )); then
    force_step=1
  fi

  print_step_header "Step $number/$total: $(step_label "$step_key")"
  if [[ "$force_step" != '1' ]] && "$RUN_STEP" "$step_key" test; then
    print_step_detail "$(step_label "$step_key") is already complete; skipping."
    mark_step_complete "$step_key"
    return 0
  fi

  if [[ "$force_step" == '1' ]]; then
    print_step_detail 'Force mode enabled; rerunning this step.'
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

if [[ "$INTERACTIVE_FORCE" == '1' ]]; then
  printf '    %sForce mode enabled: GrapheneOS will be reflashed and every post-flash step will be rerun.%s\n' "$(color_red 2>/dev/null || true)" "$(color_reset 2>/dev/null || true)"
fi

print_step_header 'Step 1/17: Inspect the connected device'
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

run_step_if_needed 2 17 prepare-assets --download

print_step_header 'Step 3/17: Unlock the bootloader if needed'
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
if [[ "$INTERACTIVE_FORCE" == '1' ]]; then
  print_step_detail 'Force mode will reflash GrapheneOS. Put the device into Fastboot Mode now.'
  ensure_fastboot_ready
elif [[ "$RUNTIME_GRAPHENEOS_READY" != '1' ]] && ! step_completed flash-grapheneos; then
  print_manual_block 'If the phone wiped and rebooted after unlocking, return it to Fastboot Mode now.'
  ensure_fastboot_ready
fi

print_step_header 'Step 4/17: Flash GrapheneOS'
refresh_runtime_state
if [[ "$INTERACTIVE_FORCE" == '1' ]]; then
  print_step_detail 'Force mode enabled; reflashing GrapheneOS.'
  ensure_fastboot_ready
  refresh_runtime_state
  if [[ "$RUNTIME_BOOTLOADER_UNLOCKED" != '1' ]]; then
    wait_for_bootloader_unlocked
    ensure_fastboot_ready
  fi
  "$RUN_STEP" flash-grapheneos apply
  mark_step_complete flash-grapheneos
elif [[ "$RUNTIME_GRAPHENEOS_READY" == '1' ]]; then
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
  print_step_detail 'Waiting for Android to boot and for ADB authorization to come back.'
  wait_for_adb_ready
fi

print_step_header 'Step 5/17: Install Magisk root'
refresh_runtime_state
if [[ "$INTERACTIVE_FORCE" == '1' ]]; then
  print_step_detail 'Force mode enabled; reinstalling Magisk root.'
  ensure_adb_ready
  "$RUN_STEP" install-magisk-root apply
  wait_for_adb_ready
  wait_for_root_ready
  mark_step_complete install-magisk-root
elif [[ "$RUNTIME_ROOT_READY" == '1' ]]; then
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

run_step_if_needed 6 17 connect-wifi
run_step_if_needed 7 17 disable-wifi-mac-randomization
run_step_if_needed 8 17 enable-wifi-send-device-name
run_step_if_needed 9 17 disable-system-updater
run_step_if_needed 10 17 install-magisk-service
run_step_if_needed 11 17 install-termux
run_step_if_needed 12 17 authorize-termux-root
run_step_if_needed 13 17 stage-termux-bootstrap
run_step_if_needed 14 17 disable-magisk-ui-notification
run_step_if_needed 15 17 disable-magisk-shell-notification
run_step_if_needed 16 17 disable-magisk-termux-notification

print_step_header 'Step 17/17: Verify SSH and re-check every step'
"$RUN_STEP" verify-final-state apply
mark_step_complete verify-final-state