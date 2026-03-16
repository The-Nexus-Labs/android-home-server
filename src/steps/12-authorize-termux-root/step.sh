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
This step triggers a real Termux root request and waits until Magisk Superuser access has been granted to Termux.

On the phone:
  1. Open Magisk.
  2. Approve the Termux root prompt if it appears.
  3. In Superuser, confirm that Termux is listed and allowed.
  4. If Termux is still missing, open Termux once.
  5. Return to the workflow.
EOF
}

step_apply() {
  require_cmd adb
  assert_adb_device
  adb_root id >/dev/null 2>&1 || die 'root is not available yet; run ./src/run-step.sh install-magisk-root apply first'

  if ! adb_package_installed com.termux; then
    die 'Termux is not installed yet; run ./src/run-step.sh install-termux apply first'
  fi

  if termux_root_grants_present; then
    log 'Termux already has Magisk root access.'
    return 0
  fi

  log 'Triggering a Termux root request so Magisk can show the Termux entry.'
  wait_for_termux_root_access 'Grant Termux root in Magisk now.'
}