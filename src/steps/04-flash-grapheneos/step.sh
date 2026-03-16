step_id() {
  printf 'flash-grapheneos\n'
}

step_name() {
  printf 'Flash GrapheneOS\n'
}

step_state_key() {
  printf 'STATE_GRAPHENEOS_FLASHED\n'
}

step_is_done() {
  adb_ready && is_grapheneos_build
}

step_guide() {
  cat <<'EOF'
This step flashes the pinned official GrapheneOS factory image.

Before continuing:
  1. Make sure the phone is on the Fastboot screen.
  2. Confirm the bootloader is already unlocked.
  3. Keep the USB cable connected until flashing finishes.

After flashing finishes on the phone:
  1. Let the phone boot into GrapheneOS.
  2. Complete the initial setup wizard.
  3. Re-enable Developer options.
  4. Re-enable OEM unlocking.
  5. Re-enable USB debugging.
  6. Accept the new ADB authorization prompt.
EOF
}

step_apply() {
  local release_dir flash_log

  require_cmd fastboot
  require_manifest
  ensure_dirs

  release_dir=$(find "$GRAPHENEOS_RELEASE_DIR" -type f -name flash-all.sh -print 2>/dev/null | sed 's#/flash-all.sh$##' | sort | tail -n1 || true)
  [[ -n "$release_dir" ]] || die 'official GrapheneOS flash script not found; run ./src/run-step.sh prepare-assets apply --download first'

  warn 'This will flash the pinned official GrapheneOS release onto the connected device.'
  maybe_prompt_destructive 'Continue with GrapheneOS flashing?' || die 'aborted'

  assert_fastboot_device
  if ! fastboot_unlocked; then
    print_manual_block "Bootloader is still locked, so flashing is blocked.

What to do:
  1. Boot into Android.
  2. Enable OEM unlocking in Developer options.
  3. Run the bootloader unlock step and confirm the on-device prompt.
  4. Return to Fastboot Mode and rerun make interactive.
"
    die 'fastboot reports that the bootloader is locked'
  fi

  print_manual_block "Official GrapheneOS flash script located at:
  $release_dir

Manual action if the phone is not already in Fastboot Mode:
  - Reboot the device while holding Volume Down.
  - Leave it on the Fastboot screen.
"

  TMPDIR="$GRAPHENEOS_RELEASE_DIR/tmp"
  mkdir -p "$TMPDIR"
  flash_log="$ARTIFACT_ROOT/flash-grapheneos.log"
  log 'Running the official GrapheneOS flash script. This can take several minutes.'
  log "Flash output is being streamed and saved to $flash_log"
  if ! (
    cd "$release_dir"
    PATH="$PLATFORM_TOOLS_DIR:$PATH" TMPDIR="$TMPDIR" bash ./flash-all.sh 2>&1
  ) | tee "$flash_log"; then
    if grep -q 'not allowed when locked' "$flash_log"; then
      print_manual_block "Flashing failed because the bootloader is still locked.

What to do on the phone:
  1. Boot into Android.
  2. Enable OEM unlocking in Developer options.
  3. Run the unlock step again.
  4. Confirm 'Unlock the bootloader' on the device.
  5. Rerun make interactive.
"
      die "flashing blocked by locked bootloader; see $flash_log"
    fi

    die "GrapheneOS flashing failed; see $flash_log for details"
  fi

  print_manual_block "Flashing completed.

Next on the host:
  - The phone is still unlocked, which is required for the root workflow.
  - The script will now reboot the device into GrapheneOS.
"

  fastboot reboot

  cat <<'EOF'

GrapheneOS flashing finished.
After Android boots on the phone:
  1. Complete the GrapheneOS setup wizard.
  2. Re-enable Developer options.
  3. Re-enable OEM unlocking.
  4. Re-enable USB debugging.
  5. Accept the ADB authorization prompt.
EOF
}
