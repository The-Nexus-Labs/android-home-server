step_id() {
  printf 'verify-final-state\n'
}

step_name() {
  printf 'Verify SSH and re-check every step\n'
}

step_state_key() {
  printf 'STATE_FINAL_VERIFIED\n'
}

verified_step_keys() {
  local dir key self

  self=$(step_id)
  shopt -s nullglob
  for dir in "$STEPS_ROOT"/??-*; do
    key=${dir##*/}
    key=${key#??-}
    [[ "$key" == "$self" ]] && continue
    printf '%s\n' "$key"
  done
  shopt -u nullglob
}

all_steps_verified() {
  local step_key

  while IFS= read -r step_key; do
    [[ -n "$step_key" ]] || continue
    "$RUN_STEP" "$step_key" test || return 1
  done < <(verified_step_keys)
}

step_is_done() {
  all_steps_verified
}

step_guide() {
  cat <<'EOF'
This final step confirms that the Android device behaves like a home server and reruns every earlier step check.

If SSH is not reachable yet, finish these actions on the phone:
  1. Make sure the Termux root authorization step has completed.
  2. Open Termux.
  3. Run:
       ./setup.sh
  4. Leave Termux open for a few seconds.
EOF
}

step_apply() {
  local wifi_ip step_key step_name green reset
  local -a failed_steps=()

  refresh_runtime_state

  if [[ "$RUNTIME_SSH_READY" == '1' && "$RUNTIME_TERMUX_SETUP_HELPER_READY" == '1' && "$RUNTIME_TERMUX_BOOT_SCRIPT_READY" == '1' ]]; then
    if reconcile_runtime_policies; then
      log 'Runtime policies are already applied.'
    else
      log 'Runtime policies drifted and were repaired.'
    fi
  fi

  refresh_runtime_state
  wifi_ip=${RUNTIME_WIFI_IP:-}
  [[ -n "$wifi_ip" ]] || die 'failed to detect wlan0 IP after provisioning'

  if [[ "$RUNTIME_SSH_READY" != '1' ]]; then
    if ! termux_root_grants_present; then
      "$RUN_STEP" authorize-termux-root apply
      refresh_runtime_state
    fi
    wait_for_termux_bootstrap "$wifi_ip"
  fi

  if ! ssh_port_open "$wifi_ip" "$TERMUX_SSH_PORT"; then
    die "SSH port $TERMUX_SSH_PORT is not reachable on $wifi_ip"
  fi

  wait_for_termux_runtime_validation

  refresh_runtime_state
  if reconcile_runtime_policies; then
    log 'All runtime policies still match the expected configuration.'
  else
    log 'Runtime policy drift was repaired before the final verification pass.'
  fi

  while IFS= read -r step_key; do
    [[ -n "$step_key" ]] || continue
    if ! "$RUN_STEP" "$step_key" test; then
      step_name=$("$RUN_STEP" "$step_key" name)
      failed_steps+=("$step_name")
    fi
  done < <(verified_step_keys)

  if [[ "${#failed_steps[@]}" -gt 0 ]]; then
    printf 'Final verification failed for these steps:\n'
    for step_name in "${failed_steps[@]}"; do
      printf '  - %s\n' "$step_name"
    done
    exit 1
  fi

  green=$(color_green 2>/dev/null || true)
  reset=$(color_reset 2>/dev/null || true)

  printf '\nAndroid home server setup completed.\n\n'
  printf '%sSSH endpoint:\n' "$green"
  printf '  host: %s\n' "$wifi_ip"
  printf '  port: %s\n' "$TERMUX_SSH_PORT"
  printf '  password: %s%s\n\n' "$TERMUX_SSH_PASSWORD" "$reset"
  printf 'Every individual step check passed in the final verification run.\n'
}