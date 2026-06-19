#!/usr/bin/env bash
#
# src/dependencies/certbot.sh - Certbot (Let's Encrypt client) provisioning.
#
# Prefers the distro package; falls back to snap on systems that ship it, and
# finally to pip3 in a venv so we never hard-fail just because a package is
# missing on an unusual distro.

if [ -n "${CALAGOPUS_LIB_DEPS_CERTBOT:-}" ]; then return 0; fi
CALAGOPUS_LIB_DEPS_CERTBOT=1

certbot_installed() { command -v certbot >/dev/null 2>&1; }
certbot_version()   { certbot --version 2>&1 | awk '{print $3}'; }
certbot_health()    { certbot_installed; }   # no daemon; "healthy" == present

certbot_install() {
	if certbot_installed; then log_debug "certbot already present"; return 0; fi
	case "$OS_FAMILY" in
		debian) os_pkg_install certbot ;;
		rhel)   os_pkg_install certbot python3-certbot-nginx 2>/dev/null || os_pkg_install certbot ;;
		arch)   os_pkg_install certbot ;;
		suse)   os_pkg_install certbot ;;
		*)
			if command -v snap >/dev/null 2>&1; then
				system_as_root snap install --classic certbot 2>/dev/null && return 0
			fi
			os_pkg_install python3 python3-venv
			system_as_root python3 -m venv /opt/certbot
			system_as_root /opt/certbot/bin/pip install --upgrade certbot
			system_as_root ln -sf /opt/certbot/bin/certbot /usr/local/bin/certbot
			;;
	esac
}
