step_id() {
  printf 'unlock-bootloader\n'
}

step_name() {
  printf 'Unlock the bootloader\n'
}

step_state_key() {
  printf 'STATE_BOOTLOADER_UNLOCKED\n'
}

step_is_done() {
  if adb_ready; then
    [[ "$(device_lock_state)" != '1' ]]
    return
  fi
  if fastboot_ready; then
    fastboot_unlocked
    return
  fi
  return 1
}

step_guide() {
  cat <<'EOF'
This step wipes the phone.

Before continuing on the phone:
  1. Remove any Google accounts to avoid Factory Reset Protection.
  2. Open Settings > System > Developer options.
  3. Turn on OEM unlocking.
  4. Keep USB debugging enabled.
  5. Be ready to confirm the unlock prompt in Fastboot Mode.

When the phone shows the unlock confirmation screen:
  1. Use the volume buttons to highlight Unlock the bootloader.
  2. Press the power button once to confirm.
EOF
}

step_apply() {
  require_cmd adb
  require_cmd fastboot
  assert_adb_device
  assert_device_matches_profile "$(device_codename)" "$DEVICE_CODENAME"

  if step_is_done; then
    log 'Bootloader already appears unlocked; skipping unlock flow.'
    return 0
  fi

  warn 'Unlocking the bootloader will factory reset the phone.'
  maybe_prompt_destructive 'Continue with bootloader unlock?' || die 'aborted'

  log 'Rebooting to bootloader'
  adb reboot bootloader
  sleep 5
  assert_fastboot_device

  cat <<'EOF'

The phone is now in Fastboot Mode.

Next on the host, the script will run:
  fastboot flashing unlock

After that command is sent, the phone will show the unlock confirmation screen.

Manual action needed on the phone then:
  - Use volume keys to choose 'Unlock the bootloader'
  - Press power to confirm

EOF

  fastboot flashing unlock
  warn 'If the phone rebooted automatically, wait for Android to boot and re-enable USB debugging afterward.'
}
