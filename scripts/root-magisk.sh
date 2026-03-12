#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd adb
require_cmd fastboot
require_cmd python3
require_manifest
assert_adb_device
ensure_dirs

magisk_apk_name=$(manifest_value magisk.apk_name)
host_patch_name=$(manifest_value magisk.host_patch_name)
magisk_apk="$DOWNLOAD_DIR/$magisk_apk_name"
host_patch="$DOWNLOAD_DIR/$host_patch_name"
grapheneos_init_boot_img=$(find "$PROJECT_ROOT/artifacts/$DEVICE_CODENAME/grapheneos/release" -type f -path '*/init_boot.img' 2>/dev/null | sort | tail -n1 || true)
init_boot_img=${BOOT_IMAGE:-$grapheneos_init_boot_img}
patched_img="$ARTIFACT_ROOT/patched-init_boot.img"

for file in "$magisk_apk" "$host_patch" "$init_boot_img"; do
  [[ -f "$file" ]] || die "missing required file: $file"
done

log "Using boot image: $init_boot_img"

if adb_root id >/dev/null 2>&1; then
  log "Magisk root is already available; skipping root installation."
  exit 0
fi

if adb_package_installed com.topjohnwu.magisk; then
  log "Magisk app already installed; skipping app install"
else
  log "Installing Magisk app"
  adb install -r "$magisk_apk" >/dev/null
fi

busybox_tmp=$(mktemp)
python3 - <<'PY' "$magisk_apk" "$busybox_tmp"
import sys, zipfile
apk, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk) as zf:
    with zf.open('lib/arm64-v8a/libbusybox.so') as src, open(out, 'wb') as dst:
        dst.write(src.read())
PY

log "Pushing Magisk patch helper files to the phone"
adb push "$busybox_tmp" /data/local/tmp/busybox >/dev/null
adb push "$host_patch" /data/local/tmp/host_patch.sh >/dev/null
adb push "$magisk_apk" /data/local/tmp/magisk.apk >/dev/null
adb push "$init_boot_img" /data/local/tmp/init_boot.img >/dev/null
rm -f "$busybox_tmp"

log "Patching init_boot.img on the device with Magisk tools"
adb shell sh /data/local/tmp/host_patch.sh /data/local/tmp/init_boot.img
adb pull /data/local/tmp/init_boot.img.magisk "$patched_img" >/dev/null

warn "About to flash the Magisk-patched init_boot image."
maybe_prompt_destructive "Continue with root installation?" || die "aborted"

adb reboot bootloader
sleep 5
assert_fastboot_device
fastboot flash init_boot "$patched_img"
fastboot reboot

cat <<EOF

Magisk root image flashed.
After Android finishes booting:
  - Unlock the device.
  - Open the Magisk app once if it asks for additional setup.
  - Re-enable USB debugging if Android reset the authorization.
Then run ./scripts/postflash-provision.sh.
EOF
