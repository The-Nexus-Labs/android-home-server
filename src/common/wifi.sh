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

wifi_service_ready() {
  adb shell service check wifi 2>/dev/null \
    | tr -d '\r' \
    | grep -Eq 'Service[[:space:]]+wifi:[[:space:]]+found'
}

wait_for_wifi_service_ready() {
  local attempt

  for attempt in {1..20}; do
    if ! adb_ready; then
      warn 'ADB disconnected while applying Wi-Fi settings; waiting for the device to reconnect.'
      wait_for_adb_ready
    fi

    if wifi_service_ready; then
      adb_wait_for_root || true
      return 0
    fi

    sleep 2
  done

  return 1
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
  wait_for_wifi_service_ready
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
    elif send_node.get('value') != 'true':
        send_node.set('value', 'true')

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