disable_system_updater_resolve_package() {
  if [[ -n "${SYSTEM_UPDATER_PACKAGE:-}" ]]; then
    printf '%s\n' "$SYSTEM_UPDATER_PACKAGE"
    return 0
  fi

  if adb_package_installed app.seamlessupdate.client || is_grapheneos_build; then
    printf '%s\n' 'app.seamlessupdate.client'
    return 0
  fi

  return 1
}

disable_system_updater_resolve_label() {
  if [[ -n "${SYSTEM_UPDATER_LABEL:-}" ]]; then
    printf '%s\n' "$SYSTEM_UPDATER_LABEL"
    return 0
  fi

  if [[ "$UPDATER_PACKAGE" == 'app.seamlessupdate.client' ]]; then
    printf '%s\n' 'GrapheneOS System Updater'
    return 0
  fi

  printf '%s\n' 'system updater'
}

step_id() {
  printf 'disable-system-updater\n'
}

step_name() {
  printf 'Disable the system updater\n'
}

step_state_key() {
  printf 'STATE_SYSTEM_UPDATER_DISABLED\n'
}

step_is_done() {
  grapheneos_updater_disabled
}

step_guide() {
  cat <<'EOF'
This step runs over ADB and normally does not require touching the phone.

It disables the OS updater package so updates only happen when you explicitly re-enable it.
EOF
}

step_apply() {
  local updater_package update_mode updater_label

  require_cmd adb
  assert_adb_device

  updater_package=${UPDATER_PACKAGE:-$(disable_system_updater_resolve_package || true)}
  update_mode=${1:-disable}

  [[ -n "$updater_package" ]] || die 'unable to detect a supported system updater implementation for this OS'

  if ! adb_package_installed "$updater_package"; then
    die "system updater package not found: $updater_package"
  fi

  UPDATER_PACKAGE=$updater_package
  updater_label=$(disable_system_updater_resolve_label)

  case "${update_mode,,}" in
    disable|disabled|off|manual)
      log "Disabling $updater_label"
      adb shell pm disable-user --user 0 "$updater_package" >/dev/null
      ;;
    enable|enabled|on|auto|automatic)
      log "Enabling $updater_label"
      adb shell pm enable --user 0 "$updater_package" >/dev/null
      ;;
    status)
      ;;
    *)
      die "unsupported update mode: $update_mode (use disable, enable or status)"
      ;;
  esac

  if adb shell pm list packages -d 2>/dev/null | tr -d '\r' | grep -qx "package:$updater_package"; then
    cat <<EOF

Update mode: disabled
$updater_label is disabled.
Use ./src/run-step.sh disable-system-updater apply enable before taking managed updates.
EOF
  else
    cat <<EOF

Update mode: enabled
$updater_label is enabled.
EOF
  fi
}