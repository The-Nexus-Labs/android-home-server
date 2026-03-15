MAGISK_SERVICE_STEP_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

step_id() {
  printf 'install-magisk-service\n'
}

step_name() {
  printf 'Install the Magisk battery tuning service\n'
}

step_state_key() {
  printf 'STATE_MAGISK_SERVICE_INSTALLED\n'
}

step_is_done() {
  adb_root 'test -f /data/adb/service.d/20-home-server-tuning.sh' >/dev/null 2>&1
}

step_guide() {
  cat <<'EOF'
This step installs a Magisk service script so Android keeps the Termux-based server alive.

Manual action is not normally required.
EOF
}

step_apply() {
  local idle_script_local idle_script_generated idle_script_remote wifi_send_device_name_restriction

  require_cmd adb
  require_cmd python3
  assert_adb_device
  adb_root id >/dev/null 2>&1 || die 'root is not available yet; run ./src/run-step.sh install-magisk-root apply first'

  idle_script_local="$MAGISK_SERVICE_STEP_DIR/assets/magisk-disable-idle.sh"
  idle_script_generated="$ARTIFACT_ROOT/magisk-disable-idle.generated.sh"
  idle_script_remote=/data/local/tmp/20-home-server-tuning.sh
  [[ -f "$idle_script_local" ]] || die "missing required file: $idle_script_local"

  wifi_send_device_name_restriction=0
  if is_grapheneos_build && [[ -n "${WIFI_SSID:-}" ]]; then
    wifi_send_device_name_restriction=$(wifi_send_device_name_restriction_flags_for_profile)
  fi

  python3 - <<'PY' "$idle_script_local" "$idle_script_generated" "$wifi_send_device_name_restriction"
from pathlib import Path
import sys

src, dst, restriction = sys.argv[1:4]
content = Path(src).read_text(encoding='utf-8')
content = content.replace('__WIFI_SEND_DHCP_HOSTNAME_RESTRICTION__', restriction)
Path(dst).write_text(content, encoding='utf-8')
PY

  log 'Installing battery-tuning script into Magisk service.d'
  adb push "$idle_script_generated" "$idle_script_remote" >/dev/null
  adb_root "mkdir -p /data/adb/service.d && cat '$idle_script_remote' > /data/adb/service.d/20-home-server-tuning.sh && chmod 755 /data/adb/service.d/20-home-server-tuning.sh && /data/adb/service.d/20-home-server-tuning.sh"
}