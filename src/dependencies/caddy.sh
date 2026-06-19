#!/usr/bin/env bash
#
# src/dependencies/caddy.sh - Caddy reverse-proxy provisioning (optional).
#
# Installs Caddy from the official copr / APT repo (Debian) or EPEL-style copr
# (RHEL). Caddy handles TLS automatically via Let's Encrypt, which makes it an
# attractive low-config option; we still generate an explicit Caddyfile in the
# proxy module so the setup is reproducible.

if [ -n "${CALAGOPUS_LIB_DEPS_CADDY:-}" ]; then return 0; fi
CALAGOPUS_LIB_DEPS_CADDY=1

caddy_installed() { command -v caddy >/dev/null 2>&1; }
caddy_version()   { caddy version 2>/dev/null | awk '{print $1}'; }
caddy_health()    { systemctl is-active --quiet caddy 2>/dev/null; }

caddy_install() {
	case "$OS_FAMILY" in
		debian)
			os_pkg_install debian-keyring debian-archive-keyring curl gnupg
			system_as_root install -d -m0755 /etc/apt/keyrings
			curl -fsSL "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" \
				| gpg --dearmor | system_as_root tee /etc/apt/keyrings/caddy-stable.gpg >/dev/null
			curl -fsSL "https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" \
				| system_as_root tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
			OS_PKG_REFRESHED=0; os_pkg_refresh
			os_pkg_install caddy
			;;
		rhel)
			system_as_root dnf install -y 'dnf-command(copr)' 2>/dev/null || true
			system_as_root dnf copr enable -y @caddy/caddy 2>/dev/null || true
			os_pkg_install caddy
			;;
		arch) os_pkg_install caddy ;;
		suse) os_pkg_install caddy ;;
		*)
			# Fallback: download the static binary (works everywhere, incl. ARM64).
			local arch; arch="$(system_arch)"
			local url="https://github.com/caddyserver/caddy/releases/latest/download/caddy_${arch}_linux"
			curl -fsSL "$url" -o /tmp/caddy
			system_as_root install -m0755 /tmp/caddy /usr/bin/caddy
			rm -f /tmp/caddy
			;;
	esac
	system_as_root systemctl enable --now caddy 2>/dev/null || true
}
