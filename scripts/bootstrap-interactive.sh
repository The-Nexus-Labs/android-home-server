#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

STATE_FILE="$BOOTSTRAP_STATE_PATH"

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
  : "${STATE_ASSETS_READY:=0}"
  : "${STATE_BOOTLOADER_UNLOCKED:=0}"
  : "${STATE_GRAPHENEOS_FLASHED:=0}"
  : "${STATE_ROOT_READY:=0}"
  : "${STATE_PROVISIONED:=0}"
}

mark_state() {
  local key=$1
  mkdir -p "$ARTIFACT_ROOT"
  touch "$STATE_FILE"
  if ! grep -q "^${key}=1$" "$STATE_FILE" 2>/dev/null; then
    printf '%s=1\n' "$key" >> "$STATE_FILE"
  fi
  eval "$key=1"
}

adb_ready() {
  [[ "$(adb get-state 2>/dev/null || true)" == "device" ]]
}

fastboot_ready() {
  fastboot devices | grep -q '[[:alnum:]]'
}

fastboot_unlocked() {
  fastboot getvar unlocked 2>&1 | tr '[:upper:]' '[:lower:]' | grep -qE 'unlocked:[[:space:]]*(yes|true)'
}

detect_wifi_ip() {
  adb shell ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 | tr -d '\r'
}

yes_no_unknown() {
  case "$1" in
    1) printf 'yes' ;;
    0) printf 'no' ;;
    *) printf 'unknown' ;;
  esac
}

magisk_ui_notification_label() {
  case "$1" in
    0) printf 'off' ;;
    1) printf 'toast' ;;
    *) printf 'unknown' ;;
  esac
}

magisk_policy_notification_disabled_label() {
  case "$1" in
    0) printf 'yes' ;;
    1) printf 'no' ;;
    *) printf 'unknown' ;;
  esac
}

grapheneos_updater_disabled() {
  if ! adb_package_installed app.seamlessupdate.client && ! is_grapheneos_build; then
    return 1
  fi
  adb shell pm list packages -d 2>/dev/null | tr -d '\r' | grep -qx 'package:app.seamlessupdate.client'
}

wifi_mac_randomization_disabled_for_profile() {
  local setting
  [[ -n "${WIFI_SSID:-}" ]] || return 1

  setting=$(adb shell dumpsys wifi 2>/dev/null | awk -v ssid="$WIFI_SSID" '
    index($0, "SSID: \"" ssid "\"") { seen = 1 }
    seen && /macRandomizationSetting:/ {
      print $2
      exit
    }
  ')

  [[ "$setting" == '0' ]]
}

print_workflow_plan() {
  printf 'Planned actions during this run:\n'
  printf '  - inspect the connected device and resume from the detected state\n'
  printf '  - prepare pinned platform-tools, GrapheneOS, Magisk and Termux assets\n'
  printf '  - unlock the bootloader when needed\n'
  printf '  - flash GrapheneOS when needed\n'
  printf '  - install and activate Magisk root\n'
  printf '  - grant and validate shell root access\n'
  if [[ -n "${WIFI_SSID:-}" ]]; then
    printf '  - connect Wi-Fi to %s\n' "$WIFI_SSID"
    if is_grapheneos_build; then
      printf '  - disable GrapheneOS Wi-Fi MAC randomization for %s\n' "$WIFI_SSID"
    fi
  else
    printf '  - skip Wi-Fi provisioning because WIFI_SSID is empty\n'
  fi
  printf '  - disable the GrapheneOS system updater package\n'
  printf '  - install the Magisk battery-tuning service script\n'
  printf '  - install Termux and Termux:Boot\n'
  printf '  - stage Termux setup.sh and boot scripts\n'
  printf '  - set Magisk UI Superuser notification to OFF\n'
  printf '  - disable Magisk root-granted notifications for shell and Termux\n'
  printf '  - launch the Termux bootstrap and bring up sshd\n'
  printf '  - validate SSH reachability and always-on Termux checks\n\n'
}

termux_boot_script_present() {
  adb_root 'test -f /data/data/com.termux/files/home/.termux/boot/10-home-server.sh' >/dev/null 2>&1
}

termux_setup_helper_present() {
  adb_root 'test -f /data/data/com.termux/files/home/setup.sh' >/dev/null 2>&1
}

termux_root_enabled_present() {
  adb_root 'test -f /data/data/com.termux/files/home/termux-root-enabled.txt' >/dev/null 2>&1
}

termux_sshd_running() {
  adb shell 'pgrep -x sshd >/dev/null 2>&1'
}

termux_bucket_non_restrictive() {
  local package=$1
  local bucket
  bucket=$(adb shell am get-standby-bucket "$package" 2>/dev/null | tr -d '\r' | tail -n1 | xargs | tr '[:upper:]' '[:lower:]')
  [[ "$bucket" =~ ^(5|10|active|working_set)$ ]]
}

termux_restrict_bg_whitelisted() {
  local package=$1
  local package_uid
  package_uid=$(adb_package_uid "$package")
  [[ -n "$package_uid" ]] || return 1
  adb_root 'cmd netpolicy list restrict-background-whitelist 2>/dev/null' \
    | tr -d '\r' \
    | tr ' ' '\n' \
    | grep -qx "$package_uid"
}

termux_wake_lock_detected() {
  adb shell "dumpsys power 2>/dev/null | grep -qi 'termux'"
}

wait_for_termux_runtime_validation() {
  while true; do
    local boot_script=0
    local setup_helper=0
    local termux_root=0
    local sshd_running=0
    local termux_bucket=0
    local termux_boot_bucket=0
    local termux_netpolicy=0
    local termux_boot_netpolicy=0
    local wake_lock=0

    ensure_adb_ready

    if termux_boot_script_present; then
      boot_script=1
    fi
    if termux_setup_helper_present; then
      setup_helper=1
    fi
    if termux_root_enabled_present; then
      termux_root=1
      bash "$SCRIPT_DIR/configure-magisk-notifications.sh" disable com.termux >/dev/null 2>&1 || true
    fi
    if termux_sshd_running; then
      sshd_running=1
    fi
    if termux_bucket_non_restrictive com.termux; then
      termux_bucket=1
    fi
    if termux_bucket_non_restrictive com.termux.boot; then
      termux_boot_bucket=1
    fi
    if termux_restrict_bg_whitelisted com.termux; then
      termux_netpolicy=1
    fi
    if termux_restrict_bg_whitelisted com.termux.boot; then
      termux_boot_netpolicy=1
    fi
    if termux_wake_lock_detected; then
      wake_lock=1
    fi

    if [[ "$setup_helper" == "1" && "$boot_script" == "1" && "$termux_root" == "1" && "$sshd_running" == "1" && "$termux_bucket" == "1" && "$termux_boot_bucket" == "1" && "$termux_netpolicy" == "1" && "$termux_boot_netpolicy" == "1" ]]; then
      print_manual_block "Always-on Termux validation:
  - setup helper present: yes
  - boot script present: yes
  - Termux root granted in Magisk: yes
  - sshd running: yes
  - Termux standby bucket non-restrictive: yes
  - Termux:Boot standby bucket non-restrictive: yes
  - Termux background whitelist: yes
  - Termux:Boot background whitelist: yes
  - wake lock detected: $([[ "$wake_lock" == "1" ]] && printf yes || printf no)
"
      if [[ "$wake_lock" != "1" ]]; then
        warn "Wake lock could not be confirmed from adb. The server should still work, but keeping Termux opened once and rerunning ./setup.sh can help if Android later becomes aggressive."
      fi
      return 0
    fi

    if [[ "$setup_helper" != "1" ]]; then
      warn "Termux setup helper is missing; re-staging provisioning payloads now."
      "$SCRIPT_DIR/postflash-provision.sh"
      continue
    fi

    print_manual_block "Termux is not fully validated as always-on yet.

Current checks:
  - setup helper present: $([[ "$setup_helper" == "1" ]] && printf yes || printf no)
  - boot script present: $([[ "$boot_script" == "1" ]] && printf yes || printf no)
  - Termux root granted in Magisk: $([[ "$termux_root" == "1" ]] && printf yes || printf no)
  - sshd running: $([[ "$sshd_running" == "1" ]] && printf yes || printf no)
  - Termux standby bucket non-restrictive: $([[ "$termux_bucket" == "1" ]] && printf yes || printf no)
  - Termux:Boot standby bucket non-restrictive: $([[ "$termux_boot_bucket" == "1" ]] && printf yes || printf no)
  - Termux background whitelist: $([[ "$termux_netpolicy" == "1" ]] && printf yes || printf no)
  - Termux:Boot background whitelist: $([[ "$termux_boot_netpolicy" == "1" ]] && printf yes || printf no)
  - wake lock detected: $([[ "$wake_lock" == "1" ]] && printf yes || printf no)

On the phone:
  - Open Magisk and grant root to Termux if it is not already granted.
  - Open Termux.
  - Run:
      ./setup.sh
  - Leave Termux open for a few seconds.
"
    wait_for_enter "Press Enter after rerunning the Termux setup command: "
  done
}

assets_ready() {
  [[ -f "$MANIFEST_PATH" ]] || return 1
  local required=(
    "$DOWNLOAD_DIR/$(manifest_value grapheneos.release_name)"
    "$DOWNLOAD_DIR/$(manifest_value grapheneos.release_sig_name)"
    "$DOWNLOAD_DIR/$(manifest_value grapheneos.allowed_signers_name)"
    "$DOWNLOAD_DIR/$(manifest_value platform_tools.zip_name)"
    "$DOWNLOAD_DIR/$(manifest_value termux.apk_name)"
    "$DOWNLOAD_DIR/$(manifest_value termux_boot.apk_name)"
    "$DOWNLOAD_DIR/$(manifest_value magisk.apk_name)"
    "$DOWNLOAD_DIR/$(manifest_value magisk.host_patch_name)"
  )
  local file
  for file in "${required[@]}"; do
    [[ -f "$file" ]] || return 1
  done
  [[ -d "$PLATFORM_TOOLS_DIR" ]] || return 1
  find "$GRAPHENEOS_RELEASE_DIR" -type f -name flash-all.sh -print -quit | grep -q .
}

refresh_runtime_state() {
  RUNTIME_ADB_READY=0
  RUNTIME_FASTBOOT_READY=0
  RUNTIME_BOOTLOADER_UNLOCKED=0
  RUNTIME_GRAPHENEOS_READY=0
  RUNTIME_MAGISK_APP_READY=0
  RUNTIME_MAGISK_RUNTIME_READY=0
  RUNTIME_ROOT_READY=0
  RUNTIME_TERMUX_READY=0
  RUNTIME_TERMUX_BOOT_READY=0
  RUNTIME_TERMUX_SETUP_HELPER_READY=0
  RUNTIME_TERMUX_BOOT_SCRIPT_READY=0
  RUNTIME_SSH_READY=0
  RUNTIME_WIFI_IP=

  if adb_ready; then
    RUNTIME_ADB_READY=1
    if [[ "$(device_lock_state)" != "1" ]]; then
      RUNTIME_BOOTLOADER_UNLOCKED=1
    fi
    if is_grapheneos_build; then
      RUNTIME_GRAPHENEOS_READY=1
    fi
    if adb_package_installed com.topjohnwu.magisk; then
      RUNTIME_MAGISK_APP_READY=1
    fi
    if magisk_runtime_present; then
      RUNTIME_MAGISK_RUNTIME_READY=1
    fi
    if adb_root id >/dev/null 2>&1; then
      RUNTIME_ROOT_READY=1
    fi
    if adb_package_installed com.termux; then
      RUNTIME_TERMUX_READY=1
    fi
    if adb_package_installed com.termux.boot; then
      RUNTIME_TERMUX_BOOT_READY=1
    fi
    if termux_setup_helper_present; then
      RUNTIME_TERMUX_SETUP_HELPER_READY=1
    fi
    if termux_boot_script_present; then
      RUNTIME_TERMUX_BOOT_SCRIPT_READY=1
    fi
    RUNTIME_WIFI_IP=$(detect_wifi_ip)
    if [[ -n "$RUNTIME_WIFI_IP" ]] && ssh_port_open "$RUNTIME_WIFI_IP" "$TERMUX_SSH_PORT"; then
      RUNTIME_SSH_READY=1
    fi
  elif fastboot_ready; then
    RUNTIME_FASTBOOT_READY=1
    if fastboot_unlocked; then
      RUNTIME_BOOTLOADER_UNLOCKED=1
    fi
  fi
}

print_resume_summary() {
  local updater_disabled='unknown'
  local mac_randomization_disabled='unknown'
  local magisk_ui_notification='unknown'
  local shell_notification='unknown'
  local termux_notification='unknown'

  printf '\nDetected state:\n'
  if [[ "$RUNTIME_ADB_READY" == "1" ]]; then
    printf '  - adb: ready\n'
    printf '  - bootloader unlocked: %s\n' "$([[ "$RUNTIME_BOOTLOADER_UNLOCKED" == "1" ]] && printf yes || printf no)"
    printf '  - GrapheneOS installed: %s\n' "$([[ "$RUNTIME_GRAPHENEOS_READY" == "1" ]] && printf yes || printf no)"
    printf '  - Magisk app installed: %s\n' "$([[ "$RUNTIME_MAGISK_APP_READY" == "1" ]] && printf yes || printf no)"
    printf '  - Magisk runtime present: %s\n' "$([[ "$RUNTIME_MAGISK_RUNTIME_READY" == "1" ]] && printf yes || printf no)"
    printf '  - shell root available: %s\n' "$([[ "$RUNTIME_ROOT_READY" == "1" ]] && printf yes || printf no)"
    printf '  - Termux installed: %s\n' "$([[ "$RUNTIME_TERMUX_READY" == "1" ]] && printf yes || printf no)"
    printf '  - Termux:Boot installed: %s\n' "$([[ "$RUNTIME_TERMUX_BOOT_READY" == "1" ]] && printf yes || printf no)"
    printf '  - setup helper present: %s\n' "$([[ "$RUNTIME_TERMUX_SETUP_HELPER_READY" == "1" ]] && printf yes || printf no)"
    printf '  - Termux boot script present: %s\n' "$([[ "$RUNTIME_TERMUX_BOOT_SCRIPT_READY" == "1" ]] && printf yes || printf no)"
    printf '  - SSH reachable: %s\n' "$([[ "$RUNTIME_SSH_READY" == "1" ]] && printf yes || printf no)"
    if grapheneos_updater_disabled; then
      updater_disabled='yes'
    else
      updater_disabled='no'
    fi
    printf '  - GrapheneOS updater disabled: %s\n' "$updater_disabled"
    if [[ -n "${WIFI_SSID:-}" ]]; then
      if wifi_mac_randomization_disabled_for_profile; then
        mac_randomization_disabled='yes'
      else
        mac_randomization_disabled='no'
      fi
      printf '  - configured Wi-Fi SSID: %s\n' "$WIFI_SSID"
      printf '  - Wi-Fi MAC randomization disabled for %s: %s\n' "$WIFI_SSID" "$mac_randomization_disabled"
    fi
    if [[ "$RUNTIME_ROOT_READY" == "1" && "$RUNTIME_MAGISK_APP_READY" == "1" ]]; then
      magisk_ui_notification=$(magisk_su_notification_ui_value 2>/dev/null || printf unknown)
      printf '  - Magisk UI Superuser notification: %s\n' "$(magisk_ui_notification_label "$magisk_ui_notification")"
      shell_notification=$(magisk_policy_notification_value_by_uid 2000 2>/dev/null || printf unknown)
      printf '  - Magisk shell grant notification disabled: %s\n' "$(magisk_policy_notification_disabled_label "$shell_notification")"
      if [[ "$RUNTIME_TERMUX_READY" == "1" ]]; then
        termux_notification=$(magisk_policy_notification_value_for_package com.termux 2>/dev/null || printf unknown)
        printf '  - Magisk Termux grant notification disabled: %s\n' "$(magisk_policy_notification_disabled_label "$termux_notification")"
      fi
    fi
    if [[ -n "$RUNTIME_WIFI_IP" ]]; then
      printf '  - Wi-Fi IP: %s\n' "$RUNTIME_WIFI_IP"
    fi
  elif [[ "$RUNTIME_FASTBOOT_READY" == "1" ]]; then
    printf '  - fastboot: ready\n'
    printf '  - bootloader unlocked: %s\n' "$([[ "$RUNTIME_BOOTLOADER_UNLOCKED" == "1" ]] && printf yes || printf no)"
  else
    printf '  - no device detected yet\n'
  fi
  printf '\n'
}

ensure_adb_ready() {
  if adb_ready; then
    return 0
  fi
  wait_for_adb_ready
}

ensure_fastboot_ready() {
  if fastboot_ready; then
    return 0
  fi
  if adb_ready; then
    log "Rebooting the device into Fastboot Mode"
    adb reboot bootloader
    sleep 5
  fi
  wait_for_fastboot_ready
}

ssh_port_open() {
  local host=$1
  local port=$2
  timeout 5 bash -lc "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
}

wait_for_adb_ready() {
  while true; do
    if adb get-state >/dev/null 2>&1; then
      return 0
    fi
    print_manual_block "Waiting for ADB.

On the phone:
  - Boot into Android.
  - Unlock the screen.
  - Enable USB debugging if needed.
  - Accept the ADB authorization prompt.
"
    wait_for_enter "Press Enter to retry ADB detection: "
  done
}

wait_for_fastboot_ready() {
  while true; do
    if fastboot devices | grep -q '[[:alnum:]]'; then
      return 0
    fi
    print_manual_block "Waiting for Fastboot Mode.

On the phone:
  - Reboot while holding Volume Down.
  - Leave the phone on the Fastboot Mode screen.
"
    wait_for_enter "Press Enter to retry fastboot detection: "
  done
}

print_bootloader_unlock_help() {
  print_manual_block "Bootloader is still locked.

What to do:
  1. Boot back into Android if needed.
  2. Open Settings > System > Developer options.
  3. Enable OEM unlocking.
  4. Make sure the device has internet access if the toggle is blocked.
  5. Run the unlock step again and confirm the on-device prompt.

On the unlock confirmation screen:
  - This screen appears only after the host runs the fastboot unlock command.
  - Use volume keys to choose 'Unlock the bootloader'.
  - Press power to confirm.
"
}

wait_for_bootloader_unlocked() {
  while true; do
    refresh_runtime_state
    if [[ "$RUNTIME_BOOTLOADER_UNLOCKED" == "1" ]]; then
      return 0
    fi

    print_bootloader_unlock_help

    if adb_ready; then
      wait_for_enter "Press Enter to retry the unlock flow from Android: "
      "$SCRIPT_DIR/unlock-bootloader.sh" || true
      continue
    fi

    if fastboot_ready; then
      wait_for_enter "Press Enter to send the fastboot unlock command now: "
      fastboot flashing unlock || true
      warn "If the unlock confirmation still did not appear on the device, boot back into Android and verify that OEM unlocking is enabled."
      continue
    fi

    wait_for_enter "Press Enter once the device is back in Android or Fastboot Mode: "
  done
}

wait_for_root_ready() {
  while true; do
    if adb_root id >/dev/null 2>&1; then
      return 0
    fi
    print_manual_block "Waiting for Magisk shell root.

On the phone:
  - Open Magisk.
  - Set Superuser access to 'Apps and ADB'.
  - Grant root for Shell / com.android.shell when prompted.
"
    wait_for_enter "Press Enter to retry shell root: "
  done
}

wait_for_termux_bootstrap() {
  local host=$1
  while true; do
    if ssh_port_open "$host" "$TERMUX_SSH_PORT"; then
      return 0
    fi
    print_manual_block "Termux bootstrap still needs a manual finish.

On the phone:
  - Open Termux.
  - Run:
      ./setup.sh
"
    wait_for_enter "Press Enter after running the Termux bootstrap command: "
  done
}

load_state
require_cmd adb
require_cmd fastboot
require_cmd python3
ensure_dirs

log "Step 1/7: Inspecting the connected device"
if adb_ready; then
  "$SCRIPT_DIR/preflight.sh"
elif fastboot_ready; then
  warn "Device is currently in Fastboot Mode; Android-side inspection is limited until it boots again."
else
  wait_for_adb_ready
  "$SCRIPT_DIR/preflight.sh"
fi

refresh_runtime_state
print_resume_summary
print_workflow_plan

if [[ "$RUNTIME_GRAPHENEOS_READY" != "1" && "$STATE_GRAPHENEOS_FLASHED" != "1" ]]; then
  print_manual_block "Before continuing:
  1. Remove Google accounts to avoid FRP.
  2. Enable OEM unlocking in Developer options.
  3. Keep USB debugging enabled.
  4. Back up anything important.
"
  wait_for_enter "Press Enter when the phone is ready for download and flashing: "
fi

log "Step 2/7: Preparing pinned assets"
if assets_ready; then
  log "Pinned assets already prepared; skipping download step."
  mark_state STATE_ASSETS_READY
else
  "$SCRIPT_DIR/download-assets.sh" --download
  mark_state STATE_ASSETS_READY
fi

log "Step 3/7: Unlocking the bootloader if needed"
refresh_runtime_state
if [[ "$RUNTIME_BOOTLOADER_UNLOCKED" == "1" || "$STATE_BOOTLOADER_UNLOCKED" == "1" ]]; then
  log "Bootloader already unlocked; skipping unlock step."
  mark_state STATE_BOOTLOADER_UNLOCKED
else
  ensure_adb_ready
  "$SCRIPT_DIR/unlock-bootloader.sh" || true
  wait_for_bootloader_unlocked
  mark_state STATE_BOOTLOADER_UNLOCKED
fi

refresh_runtime_state
if [[ "$RUNTIME_GRAPHENEOS_READY" != "1" && "$STATE_GRAPHENEOS_FLASHED" != "1" ]]; then
  print_manual_block "If the phone wiped and rebooted after unlocking, return it to Fastboot Mode now."
  ensure_fastboot_ready
fi

log "Step 4/7: Flashing GrapheneOS"
refresh_runtime_state
if [[ "$RUNTIME_GRAPHENEOS_READY" == "1" ]]; then
  log "GrapheneOS is already installed; skipping flash step."
  mark_state STATE_GRAPHENEOS_FLASHED
elif [[ "$STATE_GRAPHENEOS_FLASHED" == "1" && "$RUNTIME_FASTBOOT_READY" == "1" ]]; then
  log "GrapheneOS flash was already completed in a previous run; skipping reflash while the device is in Fastboot Mode."
else
  ensure_fastboot_ready
  refresh_runtime_state
  if [[ "$RUNTIME_BOOTLOADER_UNLOCKED" != "1" ]]; then
    wait_for_bootloader_unlocked
    ensure_fastboot_ready
  fi
  "$SCRIPT_DIR/flash-grapheneos.sh"
  mark_state STATE_GRAPHENEOS_FLASHED
fi

refresh_runtime_state
if [[ "$RUNTIME_GRAPHENEOS_READY" != "1" ]]; then
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

log "Step 5/7: Rooting with Magisk"
refresh_runtime_state
if [[ "$RUNTIME_ROOT_READY" == "1" ]]; then
  log "Shell root is already available; skipping Magisk installation."
  mark_state STATE_ROOT_READY
elif [[ "$RUNTIME_MAGISK_RUNTIME_READY" == "1" ]]; then
  log "Magisk runtime is already present; waiting only for shell root approval."
  wait_for_root_ready
  mark_state STATE_ROOT_READY
else
  ensure_adb_ready
  "$SCRIPT_DIR/root-magisk.sh"
  wait_for_adb_ready
  wait_for_root_ready
  mark_state STATE_ROOT_READY
fi

log "Step 6/7: Provisioning Wi-Fi, updater policy, Magisk notification policy, battery tuning, Termux and SSH"
refresh_runtime_state
if [[ "$RUNTIME_SSH_READY" == "1" && "$RUNTIME_TERMUX_SETUP_HELPER_READY" == "1" && "$RUNTIME_TERMUX_BOOT_SCRIPT_READY" == "1" ]]; then
  log "SSH is already reachable; skipping provisioning step."
  mark_state STATE_PROVISIONED
else
  if [[ "$RUNTIME_SSH_READY" == "1" ]]; then
    warn "SSH is already reachable, but Termux helper files are incomplete. Re-staging provisioning payloads."
  fi
  ensure_adb_ready
  "$SCRIPT_DIR/postflash-provision.sh"
fi

refresh_runtime_state
wifi_ip=${RUNTIME_WIFI_IP:-}
[[ -n "$wifi_ip" ]] || die "failed to detect wlan0 IP after provisioning"
if [[ "$RUNTIME_SSH_READY" != "1" ]]; then
  wait_for_termux_bootstrap "$wifi_ip"
fi
mark_state STATE_PROVISIONED

log "Step 7/7: Final SSH and always-on validation"
ssh_port_open "$wifi_ip" "$TERMUX_SSH_PORT" || die "SSH port $TERMUX_SSH_PORT is not reachable on $wifi_ip"
wait_for_termux_runtime_validation

magisk_ui_notification=$(magisk_su_notification_ui_value 2>/dev/null || printf unknown)
shell_notification=$(magisk_policy_notification_value_by_uid 2000 2>/dev/null || printf unknown)
termux_notification=$(magisk_policy_notification_value_for_package com.termux 2>/dev/null || printf unknown)
if [[ -n "${WIFI_SSID:-}" ]]; then
  if wifi_mac_randomization_disabled_for_profile; then
    mac_randomization_disabled='yes'
  else
    mac_randomization_disabled='no'
  fi
else
  mac_randomization_disabled='unknown'
fi
if grapheneos_updater_disabled; then
  updater_disabled='yes'
else
  updater_disabled='no'
fi

cat <<EOF

Interactive GrapheneOS server bootstrap completed.

Connection details:
  $ARTIFACT_ROOT/ssh-connection.txt

SSH endpoint:
  host: $wifi_ip
  port: $TERMUX_SSH_PORT
  password: $TERMUX_SSH_PASSWORD

Detailed outcome:
  Wi-Fi SSID: ${WIFI_SSID:-not configured}
  GrapheneOS Wi-Fi MAC randomization disabled: $mac_randomization_disabled
  GrapheneOS updater disabled: $updater_disabled
  Magisk UI Superuser notification: $(magisk_ui_notification_label "$magisk_ui_notification")
  Magisk shell grant notification disabled: $(magisk_policy_notification_disabled_label "$shell_notification")
  Magisk Termux grant notification disabled: $(magisk_policy_notification_disabled_label "$termux_notification")
EOF
