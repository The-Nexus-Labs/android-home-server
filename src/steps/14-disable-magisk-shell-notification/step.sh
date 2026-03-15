step_id() {
  printf 'disable-magisk-shell-notification\n'
}

step_name() {
  printf 'Disable the Magisk shell grant notification\n'
}

step_state_key() {
  printf 'STATE_MAGISK_SHELL_NOTIFICATION_DISABLED\n'
}

step_is_done() {
  [[ "$(magisk_policy_notification_effective_value_by_uid 2000)" == '0' ]]
}

step_guide() {
  cat <<'EOF'
This step disables the Magisk notification for shell root grants.

If Magisk says the shell policy row does not exist yet:
  1. Trigger one shell root request from the workflow.
  2. Approve it in Magisk once.
  3. Rerun this step.
EOF
}

step_apply() {
  local action value

  require_cmd adb
  assert_adb_device
  adb_root id >/dev/null 2>&1 || die 'root is not available yet; run ./src/run-step.sh install-magisk-root apply first'

  action=${1:-disable}
  case "$action" in
    disable) value=0 ;;
    enable) value=1 ;;
    *) die 'usage: disable-magisk-shell-notification [disable|enable]' ;;
  esac

  if ! magisk_set_policy_notification_by_uid 2000 "$value" shell; then
    warn 'Magisk policy row for shell does not exist yet; grant shell root once and rerun this step'
  fi
}
