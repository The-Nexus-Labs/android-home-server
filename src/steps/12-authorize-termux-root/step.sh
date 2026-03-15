step_id() {
  printf 'authorize-termux-root\n'
}

step_name() {
  printf 'Authorize Termux root in Magisk\n'
}

step_state_key() {
  printf 'STATE_TERMUX_ROOT_AUTHORIZED\n'
}

step_is_done() {
  termux_root_grants_present
}

step_guide() {
  cat <<'EOF'
This step waits until Magisk Superuser access has been granted to both Termux and Termux:Boot.

On the phone:
  1. Open Magisk.
  2. Go to Superuser.
  3. Grant root for Termux and Termux:Boot.
  4. Return to the workflow.
EOF
}

step_apply() {
  require_cmd adb
  assert_adb_device
  adb_root id >/dev/null 2>&1 || die 'root is not available yet; run ./src/run-step.sh install-magisk-root apply first'

  if ! adb_package_installed com.termux; then
    die 'Termux is not installed yet; run ./src/run-step.sh install-termux apply first'
  fi

  if ! adb_package_installed com.termux.boot; then
    die 'Termux:Boot is not installed yet; run ./src/run-step.sh install-termux apply first'
  fi

  if termux_root_grants_present; then
    log 'Termux and Termux:Boot already have Magisk root access.'
    return 0
  fi

  wait_for_termux_root_access 'Grant Termux root in Magisk now.'
}