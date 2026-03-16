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
This step stages a root-request helper in Termux and waits until Magisk Superuser access has been granted to Termux.

On the phone:
  1. Open Termux.
  2. Run:
       ./request-root.sh
  3. When Magisk opens or prompts, allow root for Termux.
  4. In Magisk -> Superuser, confirm that Termux is listed and allowed.
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

  log 'Staging request-root.sh in Termux home so root can be granted from the actual Termux app.'
  wait_for_termux_root_access 'Grant Termux root in Magisk now.'
}