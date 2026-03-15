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

if [[ "${COMMON_SKIP_DEVICE_DISCOVERY:-0}" != "1" ]]; then
  select_target_device
fi

resolve_connected_codename() {
  local codename=
  local -a fastboot_serials=()

  if command -v adb >/dev/null 2>&1; then
    if [[ "$(adb get-state 2>/dev/null || true)" == "device" ]]; then
      codename=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r')
      [[ -n "$codename" ]] && printf '%s\n' "$codename" && return 0
    fi
  fi

  if command -v fastboot >/dev/null 2>&1; then
    mapfile -t fastboot_serials < <(fastboot_connected_serials)
    if [[ "${#fastboot_serials[@]}" -gt 0 ]]; then
      codename=$(fastboot getvar product 2>&1 | awk -F': *' '/product:/ {print $2}' | tail -n1 | tr -d '\r')
      [[ -n "$codename" ]] && printf '%s\n' "$codename" && return 0
    fi
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

  if [[ "${COMMON_SKIP_DEVICE_DISCOVERY:-0}" != "1" ]] && connected_codename=$(resolve_connected_codename); then
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

supports_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ -n "${FORCE_COLOR:-}" ]] && return 0
  [[ -n "${CLICOLOR_FORCE:-}" ]] && return 0
  [[ -t 1 || -n "${TERM_PROGRAM:-}" ]]
  [[ "${TERM:-}" != 'dumb' ]]
}

color_yellow() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput setaf 3
    return 0
  fi
  printf '\033[33m'
}

color_cyan() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput setaf 6
    return 0
  fi
  printf '\033[36m'
}

color_green() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput setaf 2
    return 0
  fi
  printf '\033[32m'
}

color_bold() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput bold
    return 0
  fi
  printf '\033[1m'
}

color_reset() {
  supports_color || return 1
  if command -v tput >/dev/null 2>&1; then
    tput sgr0
    return 0
  fi
  printf '\033[0m'
}

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

print_step_header() {
  local text=$1
  local yellow reset

  yellow=$(color_yellow 2>/dev/null || true)
  reset=$(color_reset 2>/dev/null || true)
  printf '\n%s[+] %s%s\n' "$yellow" "$text" "$reset"
}

print_step_detail() {
  printf '    %s\n' "$1"
}

print_bootstrap_header() {
  local device_name=$1
  local device_model=$2
  local device_codename=$3
  local cyan bold reset

  cyan=$(color_cyan 2>/dev/null || true)
  bold=$(color_bold 2>/dev/null || true)
  reset=$(color_reset 2>/dev/null || true)

  printf '%s%sAndroid Home Server Bootstrap%s\n' "$bold" "$cyan" "$reset"
  printf '  Device: %s\n' "$device_name"
  printf '  Model: %s (%s)\n\n' "$device_model" "$device_codename"
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

adb_wait_for_boot_completed() {
  local boot_completed

  adb_wait
  while true; do
    boot_completed=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r[:space:]')
    [[ "$boot_completed" == "1" ]] && return 0
    sleep 2
  done
}

adb_wait_for_root() {
  local attempt

  for attempt in {1..30}; do
    if adb_root true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
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

connect_profile_wifi() {
  local -a wifi_randomization_args=()

  [[ -n "${WIFI_SSID:-}" ]] || die "WIFI_SSID is empty in $PROFILE_FILE"

  adb shell cmd wifi set-wifi-enabled enabled
  if is_grapheneos_build; then
    wifi_randomization_args=(-r none)
  fi

  if [[ "$WIFI_SECURITY" == "open" ]]; then
    adb shell cmd wifi add-network "$WIFI_SSID" open "${wifi_randomization_args[@]}" >/dev/null
    adb shell cmd wifi connect-network "$WIFI_SSID" open "${wifi_randomization_args[@]}"
  else
    adb shell cmd wifi add-network "$WIFI_SSID" "$WIFI_SECURITY" "$WIFI_PASSPHRASE" "${wifi_randomization_args[@]}" >/dev/null
    adb shell cmd wifi connect-network "$WIFI_SSID" "$WIFI_SECURITY" "$WIFI_PASSPHRASE" "${wifi_randomization_args[@]}"
  fi
}

wifi_config_store_path() {
  printf '%s\n' '/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml'
}

wifi_send_device_name_enabled_for_profile() {
  local value

  [[ -n "${WIFI_SSID:-}" ]] || return 1

  value=$(adb shell dumpsys wifi 2>/dev/null | awk -v ssid="$WIFI_SSID" '
    index($0, "SSID: \"" ssid "\"") { seen = 1 }
    seen && /mIsSendDhcpHostnameEnabled:/ {
      print $2
      exit
    }
  ' | tr '[:upper:]' '[:lower:]')

  [[ "$value" == 'true' ]]
}

wifi_send_device_name_restriction_flags_for_profile() {
  case "${WIFI_SECURITY:-open}" in
    open|owe)
      printf '%s\n' '1'
      ;;
    *)
      printf '%s\n' '2'
      ;;
  esac
}

wifi_send_device_name_restriction_value() {
  adb shell dumpsys wifi 2>/dev/null \
    | awk -F= '/mSendDhcpHostnameRestriction=/ {print $2; exit}' \
    | tr -d '\r[:space:]'
}

wifi_send_device_name_restriction_enabled_for_profile() {
  local current required

  required=$(wifi_send_device_name_restriction_flags_for_profile)
  current=$(wifi_send_device_name_restriction_value)
  [[ "$current" =~ ^[0-9]+$ ]] || return 1

  (( (current & required) == required ))
}

wifi_set_send_device_name_restriction_for_profile() {
  local current required target

  required=$(wifi_send_device_name_restriction_flags_for_profile)
  current=$(wifi_send_device_name_restriction_value)
  [[ "$current" =~ ^[0-9]+$ ]] || current=0

  if (( (current & required) == required )); then
    return 0
  fi

  target=$(( current | required ))
  adb_root "service call wifi 198 s16 com.android.shell i32 $target >/dev/null"
  sleep 1

  current=$(wifi_send_device_name_restriction_value)
  [[ "$current" =~ ^[0-9]+$ ]] || return 1
  (( (current & required) == required )) || return 1

  log "Enabled the GrapheneOS Wi-Fi Send device name restriction for $WIFI_SSID"
}

wifi_reload_config_store_offline() {
  local staged_xml=$1

  adb_root "cmd wifi set-wifi-enabled disabled >/dev/null 2>&1 || true; stop; sleep 5; cat '$staged_xml' > '$(wifi_config_store_path)' && chown system:system '$(wifi_config_store_path)' && chmod 600 '$(wifi_config_store_path)' && restorecon '$(wifi_config_store_path)'; start"
  adb_wait_for_boot_completed
  adb_wait_for_root
}

wifi_set_send_device_name_enabled_for_profile() {
  local local_xml remote_xml prepared

  [[ -n "${WIFI_SSID:-}" ]] || die "WIFI_SSID is empty in $PROFILE_FILE"

  local_xml=$(mktemp)
  remote_xml=/data/local/tmp/WifiConfigStore.xml

  adb_root "cat '$(wifi_config_store_path)'" > "$local_xml" || {
    rm -f "$local_xml"
    return 1
  }

  prepared=$(python3 - <<'PY' "$local_xml" "$WIFI_SSID"
import sys
import xml.etree.ElementTree as ET

path, ssid = sys.argv[1], sys.argv[2]
quoted_ssid = f'"{ssid}"'

tree = ET.parse(path)
root = tree.getroot()
network_list = root.find('NetworkList')
if network_list is None:
    print(0)
    raise SystemExit(0)

changed = False
found = False
for network in network_list.findall('Network'):
    wifi_config = network.find('WifiConfiguration')
    if wifi_config is None:
        continue
    ssid_node = None
    for child in wifi_config.findall('string'):
        if child.get('name') == 'SSID':
            ssid_node = child
            break
    if ssid_node is None or (ssid_node.text or '') != quoted_ssid:
        continue

    found = True

    send_node = None
    insert_after = None
    for child in list(wifi_config):
        if child.get('name') == 'SendDhcpHostname2':
            send_node = child
            break
        if child.get('name') in ('EnableWifi7', 'SecurityParamsList'):
            insert_after = child

    if send_node is None:
        send_node = ET.Element('boolean', {'name': 'SendDhcpHostname2', 'value': 'true'})
        children = list(wifi_config)
        if insert_after is not None and insert_after in children:
            index = children.index(insert_after) + 1
            wifi_config.insert(index, send_node)
        else:
            wifi_config.append(send_node)
        changed = True
    elif send_node.get('value') != 'true':
        send_node.set('value', 'true')
        changed = True

if found:
    tree.write(path, encoding='utf-8', xml_declaration=True)
    print(1)
else:
    print(0)
PY
)

  if [[ "$prepared" == "1" ]]; then
    adb push "$local_xml" "$remote_xml" >/dev/null
    wifi_reload_config_store_offline "$remote_xml"
    wifi_set_send_device_name_restriction_for_profile || return 1
    adb shell cmd wifi set-wifi-enabled enabled >/dev/null 2>&1 || true
    log "Enabled Wi-Fi Send device name for $WIFI_SSID in the persisted Wi-Fi config store and reloaded Wi-Fi configuration"
  else
    rm -f "$local_xml"
    adb_root "rm -f '$remote_xml'" >/dev/null 2>&1 || true
    return 1
  fi

  rm -f "$local_xml"
  adb_root "rm -f '$remote_xml'" >/dev/null 2>&1 || true
  sleep 8

  return 0
}

saved_wifi_network_ids_for_profile() {
  [[ -n "${WIFI_SSID:-}" ]] || return 1

  adb shell cmd wifi list-networks 2>/dev/null \
    | awk -v ssid="$WIFI_SSID" 'NR > 1 && $2 == ssid { print $1 }' \
    | awk '!seen[$0]++'
}

forget_profile_wifi_networks() {
  local network_id

  while IFS= read -r network_id; do
    [[ -n "$network_id" ]] || continue
    adb shell cmd wifi forget-network "$network_id" >/dev/null 2>&1 || true
  done < <(saved_wifi_network_ids_for_profile)
}

wifi_current_mac_for_profile() {
  [[ -n "${WIFI_SSID:-}" ]] || return 1

  adb shell dumpsys wifi 2>/dev/null \
    | awk -v ssid="$WIFI_SSID" '
      index($0, "mWifiInfo SSID: \"" ssid "\"") {
        if (match($0, /MAC: ([0-9A-Fa-f:]{17})/, parts)) {
          print parts[1]
          exit
        }
      }
    '
}

mac_address_is_locally_administered() {
  local mac=$1
  local first_octet

  [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || return 1
  first_octet=${mac%%:*}
  (( (16#$first_octet & 2) != 0 ))
}

ensure_profile_wifi_connected_without_randomization() {
  ensure_profile_wifi_connected_with_stable_mac

  if is_grapheneos_build && ! wifi_send_device_name_enabled_for_profile; then
    wifi_set_send_device_name_enabled_for_profile
    sleep 8
  fi
}

ensure_profile_wifi_connected_with_stable_mac() {
  connect_profile_wifi
  sleep 8

  if [[ -n "$(wifi_current_mac_for_profile 2>/dev/null || true)" ]] \
    && mac_address_is_locally_administered "$(wifi_current_mac_for_profile)"; then
    log "Saved Wi-Fi profile still has a locally administered MAC; recreating the saved network"
    forget_profile_wifi_networks
    connect_profile_wifi
    sleep 8
  fi
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

magisk_su_notification_ui_effective_value() {
  local value

  value=$(magisk_su_notification_ui_value 2>/dev/null || true)
  if [[ "$value" == "0" ]]; then
    printf '0\n'
  else
    printf '1\n'
  fi
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

magisk_sqlite() {
  local sql=$1
  local quoted_sql

  printf -v quoted_sql '%q' "$sql"
  adb_root "/debug_ramdisk/magisk --sqlite $quoted_sql"
}

magisk_sqlite_scalar() {
  local sql=$1
  local line

  line=$(magisk_sqlite "$sql" | tr -d '\r' | tail -n1)
  [[ -n "$line" ]] || return 1
  printf '%s\n' "${line##*=}"
}

magisk_set_policy_notification_by_uid() {
  local uid=$1
  local value=$2
  local label=${3:-uid:$uid}
  local updated

  [[ "$uid" =~ ^[0-9]+$ ]] || die "invalid Magisk policy uid: $uid"
  [[ "$value" == "0" || "$value" == "1" ]] || die "invalid Magisk notification value: $value"

  updated=$(magisk_sqlite_scalar "UPDATE policies SET notification=${value} WHERE uid=${uid}; SELECT changes();")

  if [[ "$updated" =~ ^[1-9][0-9]*$ ]]; then
    if [[ "$value" == "0" ]]; then
      log "Magisk root notification disabled for $label"
    else
      log "Magisk root notification enabled for $label"
    fi
    return 0
  fi

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
  local value

  [[ "$uid" =~ ^[0-9]+$ ]] || die "invalid Magisk policy uid: $uid"

  value=$(magisk_sqlite_scalar "SELECT notification FROM policies WHERE uid=${uid};")
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}

magisk_policy_notification_effective_value_by_uid() {
  local uid=$1
  local value

  value=$(magisk_policy_notification_value_by_uid "$uid" 2>/dev/null || true)
  if [[ "$value" == "0" ]]; then
    printf '0\n'
  else
    printf '1\n'
  fi
}

magisk_policy_notification_value_for_package() {
  local package=$1
  local uid

  uid=$(adb_package_uid "$package")
  [[ -n "$uid" ]] || return 1
  magisk_policy_notification_value_by_uid "$uid"
}

magisk_policy_notification_effective_value_for_package() {
  local package=$1
  local value

  value=$(magisk_policy_notification_value_for_package "$package" 2>/dev/null || true)
  if [[ "$value" == "0" ]]; then
    printf '0\n'
  else
    printf '1\n'
  fi
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
  [[ -f "$MANIFEST_PATH" ]] || die "manifest not found; run ./src/run-step.sh prepare-assets apply --manifest-only first"
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
