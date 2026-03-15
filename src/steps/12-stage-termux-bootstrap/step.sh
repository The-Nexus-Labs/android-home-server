TERMUX_BOOTSTRAP_STEP_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

step_id() {
  printf 'stage-termux-bootstrap\n'
}

step_name() {
  printf 'Stage the Termux bootstrap and SSH configuration\n'
}

step_state_key() {
  printf 'STATE_TERMUX_BOOTSTRAP_STAGED\n'
}

step_is_done() {
  termux_setup_helper_present && termux_boot_script_present
}

step_guide() {
  cat <<'EOF'
This step stages the Termux setup script and boot script over ADB.

If the final SSH bootstrap does not start automatically, you will finish it later by opening Termux and running:
  ./setup.sh
EOF
}

step_apply() {
  local bootstrap_local bootstrap_generated connection_out bootstrap_remote termux_uid termux_user wifi_ip

  require_cmd adb
  require_cmd python3
  require_manifest
  assert_adb_device
  adb_root id >/dev/null 2>&1 || die 'root is not available yet; run ./src/run-step.sh install-magisk-root apply first'

  if ! adb_package_installed com.termux; then
    die 'Termux is not installed yet; run ./src/run-step.sh install-termux apply first'
  fi

  bootstrap_local="$TERMUX_BOOTSTRAP_STEP_DIR/assets/termux-bootstrap.sh"
  bootstrap_generated="$ARTIFACT_ROOT/termux-bootstrap.generated.sh"
  connection_out="$ARTIFACT_ROOT/ssh-connection.txt"
  bootstrap_remote=/data/local/tmp/setup.sh

  [[ -f "$bootstrap_local" ]] || die "missing required file: $bootstrap_local"

  termux_uid=$(adb_root 'stat -c %u /data/data/com.termux' | tr -d '\r')
  termux_user=$(adb_root 'stat -c %U /data/data/com.termux' | tr -d '\r')
  [[ -n "$termux_uid" ]] || die 'failed to resolve com.termux uid'

  log 'Copying bootstrap payloads into Termux home'
  python3 - <<'PY' "$bootstrap_local" "$bootstrap_generated" "$TERMUX_SSH_PASSWORD" "$TERMUX_SSH_PORT"
from pathlib import Path
import sys

src, dst, password, port = sys.argv[1:5]
content = Path(src).read_text(encoding='utf-8')
content = content.replace('__TERMUX_SSH_PASSWORD__', password)
content = content.replace('__TERMUX_SSH_PORT__', port)
Path(dst).write_text(content, encoding='utf-8')
PY

  adb push "$bootstrap_generated" "$bootstrap_remote" >/dev/null
  adb_root "mkdir -p /data/data/com.termux/files/home/.termux /data/data/com.termux/files/home/.termux/boot && cat '$bootstrap_remote' > /data/data/com.termux/files/home/bootstrap-server.sh && cat '$bootstrap_remote' > /data/data/com.termux/files/home/setup.sh && printf 'allow-external-apps=true\n' > /data/data/com.termux/files/home/.termux/termux.properties && chown -R ${termux_uid}:${termux_uid} /data/data/com.termux/files/home && chmod 700 /data/data/com.termux/files/home/bootstrap-server.sh /data/data/com.termux/files/home/setup.sh"

  log 'Attempting automatic Termux bootstrap'
  adb shell am startservice \
    -n com.termux/.app.RunCommandService \
    -a com.termux.RUN_COMMAND \
    --es com.termux.RUN_COMMAND_PATH /data/data/com.termux/files/usr/bin/bash \
    --esa com.termux.RUN_COMMAND_ARGUMENTS /data/data/com.termux/files/home/setup.sh \
    --es com.termux.RUN_COMMAND_WORKDIR /data/data/com.termux/files/home \
    --ez com.termux.RUN_COMMAND_BACKGROUND true \
    --es com.termux.RUN_COMMAND_RUNNER app-shell >/dev/null 2>&1 || true
  sleep 20

  wifi_ip=$(detect_wifi_ip)

  cat > "$connection_out" <<EOF
host=${wifi_ip:-unknown}
port=$TERMUX_SSH_PORT
user=${termux_user:-unknown}
password=$TERMUX_SSH_PASSWORD
EOF

  cat <<EOF

Provisioning finished as far as adb could take it.
Connection details saved to: $connection_out

If sshd is not already running, do this once on the phone inside Termux:
  ./setup.sh

Expected SSH username: ${termux_user:-unknown}
Detected Wi-Fi IP: ${wifi_ip:-unknown}
EOF
}