step_id() {
  printf 'enable-wifi-send-device-name\n'
}

step_name() {
  printf 'Enable GrapheneOS Wi-Fi Send device name\n'
}

step_state_key() {
  printf 'STATE_WIFI_SEND_DEVICE_NAME_ENABLED\n'
}

step_is_done() {
  [[ -n "${WIFI_SSID:-}" ]] || return 0
  is_grapheneos_build || return 0
  wifi_send_device_name_enabled_for_profile
}

step_guide() {
  cat <<'EOF'
This step enables GrapheneOS "Send device name" for the saved Wi-Fi network.

Manual action is not normally required.
EOF
}

step_apply() {
  [[ -n "${WIFI_SSID:-}" ]] || return 0
  if ! is_grapheneos_build; then
    log 'Current OS is not GrapheneOS; skipping the Send device name step.'
    return 0
  fi

  require_cmd adb
  assert_adb_device

  log "Enabling Wi-Fi Send device name for $WIFI_SSID"
  ensure_profile_wifi_connected_with_stable_mac

  if wifi_send_device_name_enabled_for_profile; then
    log "Wi-Fi Send device name is already enabled for $WIFI_SSID"
    return 0
  fi

  wifi_set_send_device_name_enabled_for_profile
}
