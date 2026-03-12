#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
DEFAULT_PROFILE_FILE="$PROJECT_ROOT/config/cheetah.env"
GLOBAL_ENV_FILE="$PROJECT_ROOT/config/global.env"

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
