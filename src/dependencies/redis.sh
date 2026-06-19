#!/usr/bin/env bash
#
# src/dependencies/redis.sh - Redis / Valkey cache provisioning.
#
# Prefers Valkey (the Calagopus docs' recommendation - it is a drop-in Redis
# fork and noticeably faster). Falls back to Redis where Valkey is unavailable
# (older distros). The database/ module is responsible for any credential
# wiring; here we only ensure the server is installed and running.

if [ -n "${CALAGOPUS_LIB_DEPS_REDIS:-}" ]; then return 0; fi
CALAGOPUS_LIB_DEPS_REDIS=1

redis_installed() {
	command -v redis-cli >/dev/null 2>&1 || command -v valkey-cli >/dev/null 2>&1 \
		|| systemctl list-unit-files 2>/dev/null | grep -qE 'redis|valkey'
}

redis_version() { redis-cli --version 2>/dev/null | awk '{print $3}' || valkey-cli --version 2>/dev/null | awk '{print $3}'; }

redis_health() {
	systemctl is-active --quiet redis 2>/dev/null && return 0
	systemctl is-active --quiet redis-server 2>/dev/null && return 0
	systemctl is-active --quiet valkey 2>/dev/null && return 0
	systemctl is-active --quiet valkey-server 2>/dev/null && return 0
	return 1
}

_redis_pkgs() {
	case "$OS_FAMILY" in
		debian) printf '%s\n' valkey redis-server ;;
		rhel)   printf '%s\n' valkey redis ;;
		arch)   printf '%s\n' valkey redis ;;
		suse)   printf '%s\n' redis-server ;;
		*)      printf '%s\n' redis-server ;;
	esac
}

redis_install() {
	local pkgs avail installed_one=""
	while IFS= read -r p; do
		# Try valkey first; if the package query fails, fall back to next.
		if [ "${#OS_PKGQUERY[@]}" -gt 0 ] && system_as_root "${OS_PKGQUERY[@]}" "$p" >/dev/null 2>&1; then
			installed_one="$p"; break
		fi
		# Also attempt an actual install of valkey and bail on success.
		if [ -z "$installed_one" ]; then
			if os_pkg_install "$p" 2>/dev/null; then
				installed_one="$p"; break
			fi
		fi
	done < <(_redis_pkgs)
	[ -n "$installed_one" ] || { log_error "could not install redis/valkey"; return 1; }
	log_debug "installed cache package: $installed_one"
	system_as_root systemctl enable --now redis-server 2>/dev/null \
		|| system_as_root systemctl enable --now redis 2>/dev/null \
		|| system_as_root systemctl enable --now valkey-server 2>/dev/null \
		|| system_as_root systemctl enable --now valkey 2>/dev/null || true
}
