#!/system/bin/sh
wifi_send_dhcp_hostname_restriction=__WIFI_SEND_DHCP_HOSTNAME_RESTRICTION__

package_uid() {
	local package="$1"
	cmd package list packages -U "$package" 2>/dev/null \
		| sed -n 's/.* uid:\([0-9][0-9]*\).*/\1/p' \
		| head -n1
}

whitelist_restrict_background() {
	local package="$1"
	local uid
	uid=$(package_uid "$package")
	if [ -n "$uid" ]; then
		cmd netpolicy add restrict-background-whitelist "$uid" || true
	fi
}

apply_wifi_send_device_name_restriction() {
	local restriction="$1"
	local attempt=0

	[ "$restriction" -gt 0 ] || return 0

	while [ "$attempt" -lt 30 ]; do
		if service call wifi 198 s16 com.android.shell i32 "$restriction" >/dev/null 2>&1; then
			return 0
		fi
		attempt=$((attempt + 1))
		sleep 5
	done

	return 1
}

cmd deviceidle disable all || true
cmd deviceidle whitelist +com.termux || true
cmd deviceidle whitelist +com.termux.boot || true
cmd appops set com.termux RUN_IN_BACKGROUND allow || true
cmd appops set com.termux RUN_ANY_IN_BACKGROUND allow || true
cmd appops set com.termux.boot RUN_IN_BACKGROUND allow || true
cmd appops set com.termux.boot RUN_ANY_IN_BACKGROUND allow || true
whitelist_restrict_background com.termux
whitelist_restrict_background com.termux.boot
am set-standby-bucket com.termux active || true
am set-standby-bucket com.termux.boot active || true
settings put global low_power 0 || true
apply_wifi_send_device_name_restriction "$wifi_send_dhcp_hostname_restriction" || true
