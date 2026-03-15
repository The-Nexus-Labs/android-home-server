TERMUX_ROOT_STEP_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

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
  termux_root_enabled_present
}

step_guide() {
  cat <<'EOF'
This step stages a small helper in Termux and waits until Magisk root has been granted to the Termux app.

On the phone you will:
  1. Open Magisk.
  2. Open Termux.
  3. Run:
       ./grant-root.sh
  4. Approve the Termux root request.
EOF
}

step_apply() {
  local helper_local helper_remote termux_uid

  require_cmd adb
  assert_adb_device
  adb_root id >/dev/null 2>&1 || die 'root is not available yet; run ./src/run-step.sh install-magisk-root apply first'

  if ! adb_package_installed com.termux; then
    die 'Termux is not installed yet; run ./src/run-step.sh install-termux apply first'
  fi

  if termux_root_enabled_present; then
    log 'Termux already has Magisk root access.'
    return 0
  fi

  helper_local="$TERMUX_ROOT_STEP_DIR/assets/grant-termux-root.sh"
  helper_remote=/data/local/tmp/grant-termux-root.sh
  [[ -f "$helper_local" ]] || die "missing required file: $helper_local"

  termux_uid=$(adb_root 'stat -c %u /data/data/com.termux' | tr -d '\r')
  [[ -n "$termux_uid" ]] || die 'failed to resolve com.termux uid'

  log 'Staging the Termux root approval helper'
  adb push "$helper_local" "$helper_remote" >/dev/null
  adb_root "mkdir -p /data/data/com.termux/files/home/.termux && cat '$helper_remote' > /data/data/com.termux/files/home/grant-root.sh && printf 'allow-external-apps=true\n' > /data/data/com.termux/files/home/.termux/termux.properties && chown -R ${termux_uid}:${termux_uid} /data/data/com.termux/files/home && chmod 700 /data/data/com.termux/files/home/grant-root.sh"

  print_manual_block "Grant Termux root in Magisk now.

On the phone:
  1. Open Magisk.
  2. Open Termux.
  3. Run:
       ./grant-root.sh
  4. Approve the Termux root request if asked.
  5. Return here.
"
  wait_for_termux_root_access
}