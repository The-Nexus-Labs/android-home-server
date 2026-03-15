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