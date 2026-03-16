step_id() {
  printf 'install-termux\n'
}

step_name() {
  printf 'Install Termux and Termux:Boot\n'
}

step_state_key() {
  printf 'STATE_TERMUX_INSTALLED\n'
}

step_is_done() {
  adb_package_installed com.termux && adb_package_installed com.termux.boot
}

step_guide() {
  cat <<'EOF'
This step installs Termux and Termux:Boot over ADB.

If Android shows an install confirmation dialog on the phone:
  1. Tap Install.
  2. Wait for the install to finish.
  3. Return to the workflow.
EOF
}

step_apply() {
  local termux_apk termux_boot_apk force_reinstall=0

  require_cmd adb
  require_manifest
  assert_adb_device
  adb_root id >/dev/null 2>&1 || die 'root is not available yet; run ./src/run-step.sh install-magisk-root apply first'

  if [[ "${INTERACTIVE_FORCE:-0}" == '1' ]]; then
    force_reinstall=1
  fi

  termux_apk="$DOWNLOAD_DIR/$(manifest_value termux.apk_name)"
  termux_boot_apk="$DOWNLOAD_DIR/$(manifest_value termux_boot.apk_name)"

  for file in "$termux_apk" "$termux_boot_apk"; do
    [[ -f "$file" ]] || die "missing required file: $file"
  done

  if [[ "$force_reinstall" == '1' ]] && adb_package_installed com.termux; then
    log 'Force mode enabled; reinstalling Termux'
    adb install -r "$termux_apk" >/dev/null
  elif adb_package_installed com.termux; then
    log 'Termux already installed; skipping APK install'
  else
    log 'Installing Termux'
    adb install -r "$termux_apk" >/dev/null
  fi

  if [[ "$force_reinstall" == '1' ]] && adb_package_installed com.termux.boot; then
    log 'Force mode enabled; reinstalling Termux:Boot'
    adb install -r "$termux_boot_apk" >/dev/null
  elif adb_package_installed com.termux.boot; then
    log 'Termux:Boot already installed; skipping APK install'
  else
    log 'Installing Termux:Boot'
    adb install -r "$termux_boot_apk" >/dev/null
  fi

  if adb_root 'test -f /data/adb/service.d/20-home-server-tuning.sh' >/dev/null 2>&1; then
    log 'Re-applying battery and background execution tuning now that Termux packages exist'
    adb_root '/data/adb/service.d/20-home-server-tuning.sh'
  fi

  log 'Launching Termux once to initialize its private directories'
  adb shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  sleep 10

  log 'Launching Termux:Boot once to enable its boot receiver'
  adb shell monkey -p com.termux.boot -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  sleep 5
}