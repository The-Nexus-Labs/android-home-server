#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
DEFAULT_PROFILE_FILE="$PROJECT_ROOT/config/cheetah.env"
GLOBAL_ENV_FILE="$PROJECT_ROOT/config/global.env"

adb_connected_serials() {
  adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" {print $1}'
}

fastboot_connected_serials() {
  fastboot devices 2>/dev/null | awk 'NF >= 1 {print $1}'
}

describe_adb_device() {
  local serial=$1
  local model codename
  model=$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
  codename=$(adb -s "$serial" shell getprop ro.product.device 2>/dev/null | tr -d '\r')
  printf 'adb %s - %s (%s)\n' "$serial" "${model:-unknown}" "${codename:-unknown}"
}

describe_fastboot_device() {
  local serial=$1
  local product
  product=$(fastboot -s "$serial" getvar product 2>&1 | awk -F': *' '/product:/ {print $2}' | tail -n1 | tr -d '\r')
  printf 'fastboot %s - %s\n' "$serial" "${product:-unknown}"
}

select_target_device() {
  local -a adb_serials=() fastboot_serials=() choices=() descriptions=()
  local total index selection selected_serial

[[ -n "${ANDROID_SERIAL:-}" ]] && return 0

if command -v adb >/dev/null 2>&1; then
  mapfile -t adb_serials < <(adb_connected_serials)
fi

if command -v fastboot >/dev/null 2>&1; then
  mapfile -t fastboot_serials < <(fastboot_connected_serials)
fi

total=$(( ${#adb_serials[@]} + ${#fastboot_serials[@]} ))
[[ "$total" -gt 0 ]] || return 0

if [[ "$total" -eq 1 ]]; then
  if [[ "${#adb_serials[@]}" -eq 1 ]]; then
    export ANDROID_SERIAL="${adb_serials[0]}"
  else
    export ANDROID_SERIAL="${fastboot_serials[0]}"
  fi
  return 0
fi

if [[ ! -t 0 ]]; then
  printf '[x] multiple devices detected. Set ANDROID_SERIAL to the target device serial before running this script.\n' >&2
  exit 1
fi

for selected_serial in "${adb_serials[@]}"; do
  choices+=("$selected_serial")
  descriptions+=("$(describe_adb_device "$selected_serial")")
done

for selected_serial in "${fastboot_serials[@]}"; do
  choices+=("$selected_serial")
  descriptions+=("$(describe_fastboot_device "$selected_serial")")
done

printf 'Multiple devices detected. Select the target device:\n'
index=1
for selection in "${descriptions[@]}"; do
  printf '  %d) %s\n' "$index" "$selection"
  index=$((index + 1))
done

while true; do
  printf 'Selection [1-%d]: ' "${#choices[@]}"
  read -r selection
  [[ "$selection" =~ ^[0-9]+$ ]] || continue
  if (( selection >= 1 && selection <= ${#choices[@]} )); then
    export ANDROID_SERIAL="${choices[selection-1]}"
    return 0
  fi
done
}

select_target_device

resolve_connected_codename() {
  local codename=

  if command -v adb >/dev/null 2>&1; then
    if [[ "$(adb get-state 2>/dev/null || true)" == "device" ]]; then
      codename=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r')
      [[ -n "$codename" ]] && printf '%s\n' "$codename" && return 0
    fi
  fi

  if command -v fastboot >/dev/null 2>&1; then
    codename=$(fastboot getvar product 2>&1 | awk -F': *' '/product:/ {print $2}' | tail -n1 | tr -d '\r')
    [[ -n "$codename" ]] && printf '%s\n' "$codename" && return 0
  fi

  return 1
}

resolve_profile_file() {
  local requested_profile=${PROFILE:-}
  local connected_codename candidate

  if [[ -n "$requested_profile" ]]; then
    if [[ -f "$requested_profile" ]]; then
      printf '%s\n' "$requested_profile"
      return 0
    fi

    candidate="$PROJECT_ROOT/$requested_profile"
    [[ -f "$candidate" ]] || {
      printf '[x] profile file not found: %s\n' "$requested_profile" >&2
      exit 1
    }
    printf '%s\n' "$candidate"
    return 0
  fi

  if connected_codename=$(resolve_connected_codename); then
    candidate="$PROJECT_ROOT/config/${connected_codename}.env"
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  printf '%s\n' "$DEFAULT_PROFILE_FILE"
}

PROFILE_FILE=$(resolve_profile_file)

if [[ -f "$GLOBAL_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$GLOBAL_ENV_FILE"
fi

if [[ -f "$PROJECT_ROOT/config/local.env" ]]; then
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/config/local.env"
fi
# shellcheck disable=SC1090
source "$PROFILE_FILE"

ARTIFACT_ROOT="$PROJECT_ROOT/artifacts/$DEVICE_CODENAME"
MANIFEST_PATH="$ARTIFACT_ROOT/manifest.json"
DOWNLOAD_DIR="$ARTIFACT_ROOT/downloads"
GRAPHENEOS_ROOT="$ARTIFACT_ROOT/grapheneos"
GRAPHENEOS_RELEASE_DIR="$GRAPHENEOS_ROOT/release"
PLATFORM_TOOLS_DIR="$GRAPHENEOS_ROOT/platform-tools"
BOOTSTRAP_STATE_PATH="$ARTIFACT_ROOT/bootstrap-interactive.state"

log() {
  printf '[+] %s\n' "$*"
}

warn() {
  printf '[!] %s\n' "$*" >&2
}

die() {
  printf '[x] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

configure_platform_tools_path() {
  if [[ -d "$PLATFORM_TOOLS_DIR" ]]; then
    PATH="$PLATFORM_TOOLS_DIR:$PATH"
    export PATH
  fi
}

ensure_dirs() {
  mkdir -p "$ARTIFACT_ROOT" "$DOWNLOAD_DIR" "$GRAPHENEOS_ROOT" "$GRAPHENEOS_RELEASE_DIR"
}

adb_one() {
  adb "$@"
}

adb_wait() {
  adb wait-for-device >/dev/null
}

adb_package_installed() {
  local package=$1
  adb shell pm list packages "$package" 2>/dev/null | tr -d '\r' | grep -qx "package:$package"
}

adb_package_uid() {
  local package=$1
  adb shell cmd package list packages -U "$package" 2>/dev/null \
    | tr -d '\r' \
    | sed -n 's/.* uid:\([0-9][0-9]*\).*/\1/p' \
    | head -n1
}

adb_root() {
  local cmd="$*"
  local quoted
  quoted=$(printf '%q' "$cmd")
  adb shell "if command -v su >/dev/null 2>&1; then su -c $quoted; else /debug_ramdisk/magisk su -c $quoted; fi"
}

magisk_pref_path() {
  printf '%s\n' '/data/user_de/0/com.topjohnwu.magisk/shared_prefs/com.topjohnwu.magisk_preferences.xml'
}

magisk_su_notification_ui_value() {
  local local_xml remote_xml value

  local_xml=$(mktemp)
  remote_xml=/data/local/tmp/magisk-prefs-read.xml

  adb_root "cp '$(magisk_pref_path)' '$remote_xml' && chmod 644 '$remote_xml'" >/dev/null 2>&1 || {
    rm -f "$local_xml"
    return 1
  }
  adb pull "$remote_xml" "$local_xml" >/dev/null

  value=$(python3 - <<'PY' "$local_xml"
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
try:
    root = ET.parse(path).getroot()
except Exception:
    print(1)
    raise SystemExit(0)

for node in root.findall('string'):
    if node.get('name') == 'su_notification':
        print((node.text or '1').strip() or '1')
        raise SystemExit(0)

print(1)
PY
)

  rm -f "$local_xml"
  adb_root "rm -f '$remote_xml'" >/dev/null 2>&1 || true
  printf '%s\n' "$value"
}

magisk_set_su_notification_ui_value() {
  local value=$1
  local app_uid local_xml remote_xml

  [[ "$value" == "0" || "$value" == "1" ]] || die "invalid Magisk UI notification value: $value"

  app_uid=$(adb_package_uid com.topjohnwu.magisk)
  [[ -n "$app_uid" ]] || die "Magisk app is not installed"

  local_xml=$(mktemp)
  remote_xml=/data/local/tmp/magisk-prefs-write.xml

  adb_root "am force-stop com.topjohnwu.magisk >/dev/null 2>&1 || true"
  if ! adb_root "cp '$(magisk_pref_path)' '$remote_xml' && chmod 644 '$remote_xml'" >/dev/null 2>&1; then
    : > "$local_xml"
  else
    adb pull "$remote_xml" "$local_xml" >/dev/null
  fi

  python3 - <<'PY' "$local_xml" "$value"
import sys
import xml.etree.ElementTree as ET

path, value = sys.argv[1], sys.argv[2]

try:
    tree = ET.parse(path)
    root = tree.getroot()
except Exception:
    root = ET.Element('map')
    tree = ET.ElementTree(root)

node = None
for child in root.findall('string'):
    if child.get('name') == 'su_notification':
        node = child
        break

if node is None:
    node = ET.SubElement(root, 'string', {'name': 'su_notification'})

node.text = value
tree.write(path, encoding='utf-8', xml_declaration=True)
PY

  adb push "$local_xml" "$remote_xml" >/dev/null
  adb_root "cat '$remote_xml' > '$(magisk_pref_path)' && chown ${app_uid}:${app_uid} '$(magisk_pref_path)' && chmod 660 '$(magisk_pref_path)' && am force-stop com.topjohnwu.magisk >/dev/null 2>&1 || true"
  rm -f "$local_xml"
  adb_root "rm -f '$remote_xml'" >/dev/null 2>&1 || true
}

magisk_set_policy_notification_by_uid() {
  local uid=$1
  local value=$2
  local label=${3:-uid:$uid}
  local local_db remote_db updated

  [[ "$uid" =~ ^[0-9]+$ ]] || die "invalid Magisk policy uid: $uid"
  [[ "$value" == "0" || "$value" == "1" ]] || die "invalid Magisk notification value: $value"

  local_db=$(mktemp)
  remote_db=/data/local/tmp/magisk-policy.db

  adb_root "cp /data/adb/magisk.db '$remote_db' && chmod 644 '$remote_db'"
  adb pull "$remote_db" "$local_db" >/dev/null

  updated=$(python3 - <<'PY' "$local_db" "$uid" "$value"
import sqlite3
import sys

path, uid, value = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
conn = sqlite3.connect(path)
cur = conn.cursor()
cur.execute('UPDATE policies SET notification=? WHERE uid=?', (value, uid))
print(cur.rowcount)
if cur.rowcount:
    conn.commit()
conn.close()
PY
)

  if [[ "$updated" =~ ^[1-9][0-9]*$ ]]; then
    adb push "$local_db" "$remote_db" >/dev/null
    adb_root "cat '$remote_db' > /data/adb/magisk.db && chown 0:0 /data/adb/magisk.db && chmod 000 /data/adb/magisk.db"
    rm -f "$local_db"
    adb_root "rm -f '$remote_db'" >/dev/null 2>&1 || true
    log "Magisk root notification disabled for $label"
    return 0
  fi

  rm -f "$local_db"
  adb_root "rm -f '$remote_db'" >/dev/null 2>&1 || true
  return 1
}

magisk_set_policy_notification_for_package() {
  local package=$1
  local value=$2
  local uid

  uid=$(adb_package_uid "$package")
  [[ -n "$uid" ]] || return 1
  magisk_set_policy_notification_by_uid "$uid" "$value" "$package"
}

magisk_policy_notification_value_by_uid() {
  local uid=$1
  local local_db remote_db value

  [[ "$uid" =~ ^[0-9]+$ ]] || die "invalid Magisk policy uid: $uid"

  local_db=$(mktemp)
  remote_db=/data/local/tmp/magisk-policy-read.db

  adb_root "cp /data/adb/magisk.db '$remote_db' && chmod 644 '$remote_db'" >/dev/null 2>&1 || {
    rm -f "$local_db"
    return 1
  }
  adb pull "$remote_db" "$local_db" >/dev/null

  value=$(python3 - <<'PY' "$local_db" "$uid"
import sqlite3
import sys

path, uid = sys.argv[1], int(sys.argv[2])
conn = sqlite3.connect(path)
cur = conn.cursor()
row = cur.execute('SELECT notification FROM policies WHERE uid=?', (uid,)).fetchone()
if row is not None:
    print(row[0])
conn.close()
PY
)

  rm -f "$local_db"
  adb_root "rm -f '$remote_db'" >/dev/null 2>&1 || true
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}

magisk_policy_notification_value_for_package() {
  local package=$1
  local uid

  uid=$(adb_package_uid "$package")
  [[ -n "$uid" ]] || return 1
  magisk_policy_notification_value_by_uid "$uid"
}

device_prop() {
  adb shell getprop "$1" | tr -d '\r'
}

device_codename() {
  device_prop ro.product.device
}

profile_codename() {
  printf '%s\n' "$DEVICE_CODENAME"
}

assert_device_matches_profile() {
  local actual=$1
  local expected=$2
  local suggested_profile="$PROJECT_ROOT/config/${actual}.env"

  [[ "$actual" == "$expected" ]] && return 0

  if [[ -f "$suggested_profile" ]]; then
    die "connected device codename is $actual but active profile is $expected. Rerun with PROFILE=config/${actual}.env or leave PROFILE unset for auto-detection."
  fi

  die "connected device codename is $actual but active profile is $expected. No profile exists yet for $actual under $PROJECT_ROOT/config/. Add config/${actual}.env first."
}

device_lock_state() {
  device_prop ro.boot.flash.locked
}

is_grapheneos_build() {
  local fingerprint description host display incremental
  fingerprint=$(device_prop ro.build.fingerprint)
  description=$(device_prop ro.build.description)
  host=$(device_prop ro.build.host)
  display=$(device_prop ro.build.display.id)
  incremental=$(device_prop ro.build.version.incremental)

  if printf '%s\n%s\n%s\n' "$fingerprint" "$description" "$host" | grep -qi 'grapheneos'; then
    return 0
  fi

  if [[ "$display" == "$GRAPHENEOS_VERSION" || "$incremental" == "$GRAPHENEOS_VERSION" ]]; then
    return 0
  fi

  adb_package_installed app.grapheneos.apps \
    || adb_package_installed app.grapheneos.setupwizard \
    || adb_package_installed android.overlay.grapheneos
}

magisk_runtime_present() {
  adb shell 'test -x /debug_ramdisk/magisk || command -v su >/dev/null 2>&1' >/dev/null 2>&1
}

assert_adb_device() {
  local state
  state=$(adb get-state 2>/dev/null || true)
  [[ "$state" == "device" ]] || die "adb device not in 'device' state"
}

assert_fastboot_device() {
  fastboot devices | grep -q '[[:alnum:]]' || die "no fastboot device detected"
}

require_manifest() {
  [[ -f "$MANIFEST_PATH" ]] || die "manifest not found; run ./scripts/download-assets.sh --manifest-only first"
}

manifest_value() {
  local key=$1
  python3 - <<'PY' "$MANIFEST_PATH" "$key"
import json, sys
manifest_path, key = sys.argv[1], sys.argv[2]
with open(manifest_path, 'r', encoding='utf-8') as f:
    data = json.load(f)
parts = key.split('.')
cur = data
for part in parts:
    cur = cur[part]
print(cur)
PY
}

maybe_prompt_destructive() {
  local prompt=$1
  if [[ "${FORCE:-0}" == "1" ]]; then
    return 0
  fi
  printf '%s [y/N] ' "$prompt"
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

wait_for_enter() {
  local prompt=${1:-Press Enter to continue}
  if [[ "${FORCE:-0}" == "1" ]]; then
    return 0
  fi
  printf '%s' "$prompt"
  read -r _
}

print_manual_block() {
  printf '\n%s\n\n' "$1"
}

configure_platform_tools_path
