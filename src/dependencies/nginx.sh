#!/usr/bin/env bash
#
# src/dependencies/nginx.sh - Nginx reverse-proxy provisioning.
#
# Installs the distro nginx package (good enough; the official nginx.org repo
# can be enabled via CALAGOPUS_NGINX_SOURCE=upstream if a newer build is
# needed). Ensures the service is enabled and a default site exists so the
# proxy module has something to drop configs into.

if [ -n "${CALAGOPUS_LIB_DEPS_NGINX:-}" ]; then return 0; fi
CALAGOPUS_LIB_DEPS_NGINX=1

nginx_installed() { command -v nginx >/dev/null 2>&1; }
nginx_version()   { nginx -v 2>&1 | sed -n 's#.*/\([0-9.]*\).*#\1#p'; }
nginx_health()    { systemctl is-active --quiet nginx 2>/dev/null; }

nginx_install() {
	if [ "${CALAGOPUS_NGINX_SOURCE:-distro}" = "upstream" ] && [ "$OS_FAMILY" = "debian" ]; then
		os_pkg_install curl gnupg
		system_as_root install -d -m0755 /etc/apt/keyrings
		curl -fsSL https://nginx.org/keys/nginx_signing.key \
			| gpg --dearmor | system_as_root tee /etc/apt/keyrings/nginx.gpg >/dev/null
		local cn; cn="$(. /etc/os-release; echo "${UBUNTU_CODENAME:-${DEBIAN_CODENAME:-}}")"
		system_as_root tee /etc/apt/sources.list.d/nginx.list >/dev/null \
			<<<"deb [signed-by=/etc/apt/keyrings/nginx.gpg] https://nginx.org/packages/${OS_ID} ${cn} nginx"
		OS_PKG_REFRESHED=0; os_pkg_refresh
	fi
	os_pkg_install nginx
	system_as_root systemctl enable --now nginx
}
