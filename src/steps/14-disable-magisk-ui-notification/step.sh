step_id() {
  printf 'disable-magisk-ui-notification\n'
}

step_name() {
  printf 'Disable the Magisk UI Superuser notification\n'
}

step_state_key() {
  printf 'STATE_MAGISK_UI_NOTIFICATION_DISABLED\n'
}

step_is_done() {
  [[ "$(magisk_su_notification_ui_effective_value)" == '0' ]]
}

step_guide() {
  cat <<'EOF'
This step turns the Magisk UI Superuser notification to OFF for unattended operation.

Manual action is not normally required.
EOF
}

step_apply() {
  local action value

  require_cmd adb
  require_cmd python3
  assert_adb_device
  adb_root id >/dev/null 2>&1 || die 'root is not available yet; run ./src/run-step.sh install-magisk-root apply first'

  action=${1:-disable}
  case "$action" in
    disable) value=0 ;;
    enable) value=1 ;;
    *) die 'usage: disable-magisk-ui-notification [disable|enable]' ;;
  esac

  magisk_set_su_notification_ui_value "$value"
  if [[ "$value" == '0' ]]; then
    log 'Magisk UI Superuser notification set to OFF'
  else
    log 'Magisk UI Superuser notification set to TOAST'
  fi
}
