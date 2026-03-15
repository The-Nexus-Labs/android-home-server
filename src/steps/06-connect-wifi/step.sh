step_id() {
  printf 'connect-wifi\n'
}

step_name() {
  printf 'Connect the device to Wi-Fi\n'
}

step_state_key() {
  printf 'STATE_WIFI_CONNECTED\n'
}

step_is_done() {
  [[ -n "${WIFI_SSID:-}" ]] || return 0
  adb shell dumpsys wifi 2>/dev/null | grep -Fq "mWifiInfo SSID: \"$WIFI_SSID\""
}

step_guide() {
  cat <<'EOF'
This step usually connects the phone to Wi-Fi over ADB.

If Android blocks the connection or you need to join the network manually on the phone:
  1. Open Settings.
  2. Tap Network and Internet.
  3. Tap Internet or Wi-Fi.
  4. Select the network name from config/global.env.
  5. Enter the password if asked.
  6. Wait until the network shows Connected.
EOF
}

step_apply() {
  [[ -n "${WIFI_SSID:-}" ]] || {
    warn "WIFI_SSID is empty in $PROFILE_FILE; skipping Wi-Fi provisioning"
    return 0
  }

  require_cmd adb
  assert_adb_device

  log "Connecting device Wi-Fi to $WIFI_SSID"
  connect_profile_wifi
}