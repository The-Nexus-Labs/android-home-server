#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd adb
require_manifest
assert_adb_device
ensure_dirs

"$SCRIPT_DIR/configure-system-updater.sh" disable

termux_apk="$DOWNLOAD_DIR/$(manifest_value termux.apk_name)"
termux_boot_apk="$DOWNLOAD_DIR/$(manifest_value termux_boot.apk_name)"
idle_script_local="$PROJECT_ROOT/payloads/magisk-disable-idle.sh"
bootstrap_local="$PROJECT_ROOT/payloads/termux-bootstrap.sh"
bootstrap_generated="$ARTIFACT_ROOT/termux-bootstrap.generated.sh"
connection_out="$ARTIFACT_ROOT/ssh-connection.txt"
idle_script_remote=/data/local/tmp/20-home-server-tuning.sh
bootstrap_remote=/data/local/tmp/setup.sh

for file in "$termux_apk" "$termux_boot_apk" "$idle_script_local" "$bootstrap_local"; do
  [[ -f "$file" ]] || die "missing required file: $file"
done

log "Checking that Magisk root is available"
adb_root id >/dev/null 2>&1 || die "root is not available yet; run ./scripts/root-magisk.sh first"

if [[ -n "${WIFI_SSID:-}" ]]; then
  log "Connecting device Wi-Fi to $WIFI_SSID"
  adb shell cmd wifi set-wifi-enabled enabled
  if [[ "$WIFI_SECURITY" == "open" ]]; then
    adb shell cmd wifi connect-network "$WIFI_SSID" open
  else
    adb shell cmd wifi connect-network "$WIFI_SSID" "$WIFI_SECURITY" "$WIFI_PASSPHRASE"
  fi
  sleep 8
else
  warn "WIFI_SSID is empty in $PROFILE_FILE; skipping Wi-Fi provisioning"
fi

log "Installing battery-tuning script into Magisk service.d"
adb push "$idle_script_local" "$idle_script_remote" >/dev/null
adb_root "mkdir -p /data/adb/service.d && cat '$idle_script_remote' > /data/adb/service.d/20-home-server-tuning.sh && chmod 755 /data/adb/service.d/20-home-server-tuning.sh && /data/adb/service.d/20-home-server-tuning.sh"

if adb_package_installed com.termux; then
  log "Termux already installed; skipping APK install"
else
  log "Installing Termux"
  adb install -r "$termux_apk" >/dev/null
fi

if adb_package_installed com.termux.boot; then
  log "Termux:Boot already installed; skipping APK install"
else
  log "Installing Termux:Boot"
  adb install -r "$termux_boot_apk" >/dev/null
fi

log "Re-applying battery and background execution tuning now that Termux packages exist"
adb_root '/data/adb/service.d/20-home-server-tuning.sh'

log "Launching Termux once to initialize its private directories"
adb shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 10

termux_uid=$(adb_root 'stat -c %u /data/data/com.termux' | tr -d '\r')
termux_user=$(adb_root 'stat -c %U /data/data/com.termux' | tr -d '\r')
[[ -n "$termux_uid" ]] || die "failed to resolve com.termux uid"

log "Copying bootstrap payloads into Termux home"
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

log "Attempting automatic Termux bootstrap"
adb shell am startservice \
  -n com.termux/.app.RunCommandService \
  -a com.termux.RUN_COMMAND \
  --es com.termux.RUN_COMMAND_PATH /data/data/com.termux/files/usr/bin/bash \
  --esa com.termux.RUN_COMMAND_ARGUMENTS /data/data/com.termux/files/home/setup.sh \
  --es com.termux.RUN_COMMAND_WORKDIR /data/data/com.termux/files/home \
  --ez com.termux.RUN_COMMAND_BACKGROUND true \
  --es com.termux.RUN_COMMAND_RUNNER app-shell >/dev/null 2>&1 || true
sleep 20

wifi_ip=$(adb shell ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 | tr -d '\r')

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
