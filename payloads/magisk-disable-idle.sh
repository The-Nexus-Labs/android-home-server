#!/system/bin/sh
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
