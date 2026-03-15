step_id() {
  printf 'inspect-device\n'
}

step_name() {
  printf 'Inspect the connected device\n'
}

step_state_key() {
  printf 'STATE_DEVICE_INSPECTED\n'
}

step_is_done() {
  require_cmd adb
  assert_adb_device
  assert_device_matches_profile "$(device_codename)" "$DEVICE_CODENAME"
}

step_guide() {
  cat <<'EOF'
This step reads the current device state over ADB.

If the phone is not detected:
  1. Unlock the phone.
  2. Connect it with a working USB data cable.
  3. On the phone, allow the USB debugging prompt.
  4. If Developer options are hidden, open Settings > About phone and tap Build number 7 times.
  5. Open Settings > System > Developer options and enable USB debugging.
EOF
}

step_apply() {
  local codename android_version lock_state

  require_cmd adb
  assert_adb_device
  ensure_dirs

  codename=$(device_codename)
  android_version=$(device_prop ro.build.version.release)
  lock_state=$(device_lock_state)

  assert_device_matches_profile "$codename" "$DEVICE_CODENAME"

  if [[ "$android_version" != "16" ]]; then
    warn "This workflow expects a recent Android 16-based stock or GrapheneOS userspace. Connected device reports Android $android_version."
  fi

  if [[ "$lock_state" == "1" ]]; then
    warn 'Bootloader is still locked. Flashing cannot begin yet.'
  fi
}
