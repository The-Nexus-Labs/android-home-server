step_id() {
  printf 'disable-magisk-termux-notification\n'
}

step_name() {
  printf 'Disable the Magisk Termux grant notification\n'
}

step_state_key() {
  printf 'STATE_MAGISK_TERMUX_NOTIFICATION_DISABLED\n'
}

step_is_done() {
  if ! adb_package_installed com.termux; then
    return 1
  fi
  [[ "$(magisk_policy_notification_effective_value_for_package com.termux)" == '0' ]]
}

step_guide() {
  cat <<'EOF'
This step disables the Magisk notification for Termux root grants.

If Magisk says the Termux policy row does not exist yet:
  1. Open Magisk on the phone.
  2. Open Termux.
  3. Run:
       ./grant-root.sh
  4. Approve the Termux root request once.
  5. Rerun this step.
EOF
}

step_apply() {
  local action value

  require_cmd adb
  assert_adb_device
  adb_root id >/dev/null 2>&1 || die 'root is not available yet; run ./src/run-step.sh install-magisk-root apply first'

  if ! adb_package_installed com.termux; then
    die 'Termux is not installed yet; run ./src/run-step.sh install-termux apply first'
  fi

  action=${1:-disable}
  case "$action" in
    disable) value=0 ;;
    enable) value=1 ;;
    *) die 'usage: disable-magisk-termux-notification [disable|enable]' ;;
  esac

  if ! magisk_set_policy_notification_for_package com.termux "$value"; then
    warn 'Magisk policy row for Termux does not exist yet; grant root to Termux once and rerun this step'
  fi
}
