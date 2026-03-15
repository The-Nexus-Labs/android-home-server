step_id() {
  printf 'disable-wifi-mac-randomization\n'
}

step_name() {
  printf 'Disable GrapheneOS Wi-Fi MAC randomization\n'
}

step_state_key() {
  printf 'STATE_WIFI_MAC_RANDOMIZATION_DISABLED\n'
}

step_is_done() {
  [[ -n "${WIFI_SSID:-}" ]] || return 0
  is_grapheneos_build || return 0
  wifi_mac_randomization_disabled_for_profile
}

step_guide() {
  cat <<'EOF'
This step disables MAC randomization for the saved Wi-Fi network on GrapheneOS.

Manual action is not normally required.
EOF
}

step_apply() {
  [[ -n "${WIFI_SSID:-}" ]] || return 0
  if ! is_grapheneos_build; then
    log 'Current OS is not GrapheneOS; skipping GrapheneOS-specific Wi-Fi privacy step.'
    return 0
  fi

  require_cmd adb
  assert_adb_device

  log "Disabling Wi-Fi MAC randomization for $WIFI_SSID"
  ensure_profile_wifi_connected_with_stable_mac
}