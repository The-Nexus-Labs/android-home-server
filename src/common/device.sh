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