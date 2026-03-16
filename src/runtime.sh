SRC_DIR="$PROJECT_ROOT/src"
RUN_STEP="$SRC_DIR/run-step.sh"

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
  local setting current_mac
  [[ -n "${WIFI_SSID:-}" ]] || return 1

  setting=$(adb shell dumpsys wifi 2>/dev/null | awk -v ssid="$WIFI_SSID" '
    index($0, "SSID: \"" ssid "\"") { seen = 1 }
    seen && /macRandomizationSetting:/ {
      print $2
      exit
    }
  ')

  [[ "$setting" == '0' ]] || return 1

  current_mac=$(wifi_current_mac_for_profile 2>/dev/null || true)
  if [[ -n "$current_mac" ]] && mac_address_is_locally_administered "$current_mac"; then
    return 1
  fi

  return 0
}

termux_boot_script_present() {
  adb_root 'test -f /data/data/com.termux/files/home/.termux/boot/10-home-server.sh' >/dev/null 2>&1
}

termux_setup_helper_present() {
  adb_root 'test -f /data/data/com.termux/files/home/setup.sh' >/dev/null 2>&1
}

termux_root_grants_present() {
  magisk_policy_row_exists_for_package com.termux
}

termux_root_enabled_present() {
  termux_root_grants_present
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

ssh_port_open() {
  local host=$1
  local port=$2
  timeout 5 bash -lc "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
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
  RUNTIME_TERMUX_ROOT_READY=0
  RUNTIME_MAGISK_SERVICE_READY=0
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
    if termux_root_enabled_present; then
      RUNTIME_TERMUX_ROOT_READY=1
    fi
    if adb_root 'test -f /data/adb/service.d/20-home-server-tuning.sh' >/dev/null 2>&1; then
      RUNTIME_MAGISK_SERVICE_READY=1
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
  local send_device_name_enabled='unknown'
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
    printf '  - Termux granted in Magisk: %s\n' "$([[ "$RUNTIME_TERMUX_ROOT_READY" == "1" ]] && printf yes || printf no)"
    printf '  - setup helper present: %s\n' "$([[ "$RUNTIME_TERMUX_SETUP_HELPER_READY" == "1" ]] && printf yes || printf no)"
    printf '  - Termux boot script present: %s\n' "$([[ "$RUNTIME_TERMUX_BOOT_SCRIPT_READY" == "1" ]] && printf yes || printf no)"
    printf '  - Magisk battery tuning script present: %s\n' "$([[ "$RUNTIME_MAGISK_SERVICE_READY" == "1" ]] && printf yes || printf no)"
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
      if is_grapheneos_build && wifi_send_device_name_enabled_for_profile; then
        send_device_name_enabled='yes'
      else
        send_device_name_enabled='no'
      fi
      printf '  - configured Wi-Fi SSID: %s\n' "$WIFI_SSID"
      printf '  - Wi-Fi MAC randomization disabled for %s: %s\n' "$WIFI_SSID" "$mac_randomization_disabled"
      printf '  - Wi-Fi Send device name enabled for %s: %s\n' "$WIFI_SSID" "$send_device_name_enabled"
    fi
    if [[ "$RUNTIME_ROOT_READY" == "1" && "$RUNTIME_MAGISK_APP_READY" == "1" ]]; then
      magisk_ui_notification=$(magisk_su_notification_ui_effective_value)
      printf '  - Magisk UI Superuser notification: %s\n' "$(magisk_ui_notification_label "$magisk_ui_notification")"
      shell_notification=$(magisk_policy_notification_effective_value_by_uid 2000)
      printf '  - Magisk shell grant notification disabled: %s\n' "$(magisk_policy_notification_disabled_label "$shell_notification")"
      if [[ "$RUNTIME_TERMUX_READY" == "1" ]]; then
        termux_notification=$(magisk_policy_notification_effective_value_for_package com.termux)
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

print_workflow_plan() {
  printf 'Planned actions during this run:\n'
  printf '  - inspect the connected device\n'
  printf '  - prepare pinned platform-tools, GrapheneOS, Magisk and Termux assets\n'
  printf '  - unlock the bootloader when needed\n'
  printf '  - flash GrapheneOS when needed\n'
  printf '  - install and activate Magisk root\n'
  printf '  - connect Wi-Fi to the configured network\n'
  printf '  - enforce GrapheneOS Wi-Fi privacy settings for that network\n'
  printf '  - disable the GrapheneOS system updater package\n'
  printf '  - install the Magisk battery-tuning service script\n'
  printf '  - install Termux and Termux:Boot\n'
  printf '  - authorize Termux root in Magisk\n'
  printf '  - configure the Termux SSH service\n'
  printf '  - disable Magisk root-granted notifications for shell and Termux\n'
  printf '  - validate SSH reachability and always-on Termux checks\n\n'
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
    print_step_detail 'Rebooting the device into Fastboot Mode.'
    adb reboot bootloader
    sleep 5
  fi
  wait_for_fastboot_ready
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
    wait_for_enter 'Press Enter to retry ADB detection: '
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
    wait_for_enter 'Press Enter to retry fastboot detection: '
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
      wait_for_enter 'Press Enter to retry the unlock flow from Android: '
      "$RUN_STEP" unlock-bootloader apply || true
      continue
    fi

    if fastboot_ready; then
      wait_for_enter 'Press Enter to send the fastboot unlock command now: '
      fastboot flashing unlock || true
      warn 'If the unlock confirmation still did not appear on the device, boot back into Android and verify that OEM unlocking is enabled.'
      continue
    fi

    wait_for_enter 'Press Enter once the device is back in Android or Fastboot Mode: '
  done
}

wait_for_root_ready() {
  while true; do
    if adb_root id >/dev/null 2>&1; then
      return 0
    fi
    print_manual_block "Waiting for Magisk shell root.

On the phone:
  1. Open Magisk.
  2. Open Settings.
  3. Set Superuser access to 'Apps and ADB'.
  4. Return to the main Magisk screen.
  5. If Android shows a root prompt for Shell or ADB, tap Allow.
  6. If the Superuser section is greyed out, finish any additional Magisk setup prompt, then reopen Magisk.
  7. If Superuser still stays greyed out, rerun ./src/run-step.sh install-magisk-root apply.
"
    wait_for_enter 'Press Enter to retry shell root: '
  done
}

trigger_termux_root_request() {
  local termux_uid request_script

  ensure_adb_ready

  if ! adb_package_installed com.termux; then
    return 1
  fi

  termux_uid=$(adb_root 'stat -c %u /data/data/com.termux' | tr -d '\r')
  [[ -n "$termux_uid" ]] || return 1

  request_script=/data/data/com.termux/files/home/.termux/request-root.sh

  adb shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  adb_root "mkdir -p /data/data/com.termux/files/home/.termux && printf 'allow-external-apps=true\n' > /data/data/com.termux/files/home/.termux/termux.properties && cat > '$request_script' <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
su -c true >/dev/null 2>&1 || exit 1
EOF
chown -R ${termux_uid}:${termux_uid} /data/data/com.termux/files/home/.termux && chmod 700 '$request_script'"

  adb shell am startservice \
    -n com.termux/.app.RunCommandService \
    -a com.termux.RUN_COMMAND \
    --es com.termux.RUN_COMMAND_PATH "$request_script" \
    --es com.termux.RUN_COMMAND_WORKDIR /data/data/com.termux/files/home \
    --ez com.termux.RUN_COMMAND_BACKGROUND true \
    --es com.termux.RUN_COMMAND_RUNNER app-shell >/dev/null 2>&1 || true
}

wait_for_termux_root_access() {
  local heading=${1:-Grant Termux root in Magisk now.}

  while true; do
    if termux_root_grants_present; then
      return 0
    fi

    trigger_termux_root_request || true

    print_manual_block "$heading

On the phone:
  1. Open Magisk.
  2. Approve the Termux root prompt if it appears.
  3. In Superuser, confirm that Termux is listed and allowed.
  4. If Termux is still missing, open Termux once, then return here.
"
    wait_for_enter 'Press Enter after granting Termux root: '
    heading='Termux root access is still not granted correctly in Magisk.'
  done
}

wait_for_termux_bootstrap() {
  local host=$1
  local heading=${2:-Termux bootstrap still needs a manual finish.}
  local details=${3:-}

  while true; do
    if ssh_port_open "$host" "$TERMUX_SSH_PORT"; then
      return 0
    fi

    print_manual_block "$heading

${details:+$details

}On the phone:
  1. Open Termux.
  2. Run:
       ./setup.sh
  3. Leave Termux open for 10 seconds.
  4. Return here.
"
    wait_for_enter 'Press Enter after running ./setup.sh in Termux: '
    heading='Termux bootstrap still needs a manual finish.'
    details=
  done
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
    if termux_root_grants_present; then
      termux_root=1
      "$RUN_STEP" disable-magisk-termux-notification apply disable >/dev/null 2>&1 || true
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
      if [[ "$wake_lock" != "1" ]]; then
        warn 'Wake lock could not be confirmed from adb. The server should still work, but keeping Termux open once and rerunning ./setup.sh can help if Android later becomes aggressive.'
      fi
      return 0
    fi

    if [[ "$termux_root" != "1" ]]; then
      warn 'Termux root is not granted yet; returning to the Termux root authorization step.'
      "$RUN_STEP" authorize-termux-root apply
      continue
    fi

    if [[ "$setup_helper" != "1" ]]; then
      warn 'Termux setup helper is missing; restaging the bootstrap files.'
      "$RUN_STEP" stage-termux-bootstrap apply
      continue
    fi

    print_manual_block "Termux is not fully validated as always-on yet.

Current checks:
  - setup helper present: $([[ "$setup_helper" == "1" ]] && printf yes || printf no)
  - boot script present: $([[ "$boot_script" == "1" ]] && printf yes || printf no)
  - Termux granted in Magisk: $([[ "$termux_root" == "1" ]] && printf yes || printf no)
  - sshd running: $([[ "$sshd_running" == "1" ]] && printf yes || printf no)
  - Termux standby bucket non-restrictive: $([[ "$termux_bucket" == "1" ]] && printf yes || printf no)
  - Termux:Boot standby bucket non-restrictive: $([[ "$termux_boot_bucket" == "1" ]] && printf yes || printf no)
  - Termux background whitelist: $([[ "$termux_netpolicy" == "1" ]] && printf yes || printf no)
  - Termux:Boot background whitelist: $([[ "$termux_boot_netpolicy" == "1" ]] && printf yes || printf no)
  - wake lock detected: $([[ "$wake_lock" == "1" ]] && printf yes || printf no)

On the phone:
  1. Open Termux.
  2. Run:
       ./setup.sh
  3. Leave Termux open for a few seconds.
"
    wait_for_enter 'Press Enter after rerunning the Termux setup command: '
  done
}

reconcile_runtime_policies() {
  local changed=0

  ensure_adb_ready

  if [[ -n "${WIFI_SSID:-}" ]] && ! "$RUN_STEP" connect-wifi test; then
    log "Re-applying Wi-Fi connection for $WIFI_SSID"
    "$RUN_STEP" connect-wifi apply
    changed=1
  fi

  if [[ -n "${WIFI_SSID:-}" ]] && is_grapheneos_build && ! "$RUN_STEP" disable-wifi-mac-randomization test; then
    log "Re-applying GrapheneOS Wi-Fi MAC randomization policy for $WIFI_SSID"
    "$RUN_STEP" disable-wifi-mac-randomization apply
    changed=1
  fi

  if [[ -n "${WIFI_SSID:-}" ]] && is_grapheneos_build && ! "$RUN_STEP" enable-wifi-send-device-name test; then
    log "Re-applying GrapheneOS Wi-Fi Send device name policy for $WIFI_SSID"
    "$RUN_STEP" enable-wifi-send-device-name apply
    changed=1
  fi

  if ! grapheneos_updater_disabled; then
    log 'Re-applying updater policy'
    "$RUN_STEP" disable-system-updater apply disable
    changed=1
  fi

  if [[ "$RUNTIME_ROOT_READY" == "1" && "$RUNTIME_MAGISK_SERVICE_READY" != "1" ]]; then
    log 'Re-installing the Magisk battery tuning service script'
    "$RUN_STEP" install-magisk-service apply
    changed=1
  fi

  if [[ "$RUNTIME_ROOT_READY" == "1" && "$RUNTIME_MAGISK_APP_READY" == "1" ]] && ! "$RUN_STEP" disable-magisk-ui-notification test; then
    log 'Re-applying Magisk UI notification policy'
    "$RUN_STEP" disable-magisk-ui-notification apply disable || true
    changed=1
  fi

  if [[ "$RUNTIME_ROOT_READY" == "1" && "$RUNTIME_MAGISK_APP_READY" == "1" ]] && ! "$RUN_STEP" disable-magisk-shell-notification test; then
    log 'Re-applying Magisk shell notification policy'
    "$RUN_STEP" disable-magisk-shell-notification apply disable || true
    changed=1
  fi

  if [[ "$RUNTIME_ROOT_READY" == "1" && "$RUNTIME_MAGISK_APP_READY" == "1" ]] && ! "$RUN_STEP" disable-magisk-termux-notification test; then
    log 'Re-applying Magisk Termux notification policy'
    "$RUN_STEP" disable-magisk-termux-notification apply disable || true
    changed=1
  fi

  return "$changed"
}