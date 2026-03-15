#!/system/bin/sh
wifi_send_dhcp_hostname_restriction=__WIFI_SEND_DHCP_HOSTNAME_RESTRICTION__

package_uid() {
	local package="$1"
	cmd package list packages -U "$package" 2>/dev/null \
		| sed -n 's/.* uid:\([0-9][0-9]*\).*/\1/p' \
		| head -n1
}

package_installed() {
	local package="$1"
	pm list packages "$package" 2>/dev/null | grep -qx "package:$package"
}

whitelist_restrict_background() {
	local package="$1"
	local uid
	uid=$(package_uid "$package")
	if [ -n "$uid" ]; then
		cmd netpolicy add restrict-background-whitelist "$uid" || true
	fi
}

apply_package_keepalive_policy() {
	local package="$1"

	package_installed "$package" || return 0

	cmd deviceidle whitelist +"$package" || true
	cmd appops set "$package" RUN_IN_BACKGROUND allow || true
	cmd appops set "$package" RUN_ANY_IN_BACKGROUND allow || true
	whitelist_restrict_background "$package"
	am set-standby-bucket "$package" active || true
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
apply_package_keepalive_policy com.termux
apply_package_keepalive_policy com.termux.boot
settings put global low_power 0 || true
apply_wifi_send_device_name_restriction "$wifi_send_dhcp_hostname_restriction" || true
