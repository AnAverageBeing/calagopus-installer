#!/usr/bin/env bash
#
# src/os/arch.sh - Arch Linux / derivatives family prep.
#
# Arch keeps Docker, PostgreSQL, Nginx, Caddy, Certbot in the official repos
# (or the AUR for a couple). No third-party repo setup is required, so this
# module is intentionally small: it just warns about AUR-only packages and
# makes sure pacman keys are initialised.

if [ -n "${CALAGOPUS_LIB_OS_ARCH:-}" ]; then return 0; fi
CALAGOPUS_LIB_OS_ARCH=1

arch_add_docker_repo()   { :; }   # docker is in [extra]
arch_add_postgres_repo() { :; }   # postgresql is in [core]

os_family_prepare() {
	if ! command -v pacman >/dev/null 2>&1; then
		log_warn "pacman not found despite arch family - skipping prep"
		return 0
	fi
	# Ensure the keyring is usable (commonly an issue on fresh Arch ARM images).
	system_as_root pacman-key --init 2>/dev/null || true
	system_as_root pacman-key --populate archlinux 2>/dev/null || true
	log_ok "arch family prepared (no extra repos needed)"
}

# Arch-specific package name overrides (handled via dependency manager).
arch_pkg_name() {
	case "$1" in
		postgresql)   printf 'postgresql' ;;
		redis)        printf 'redis' ;;
		nginx)        printf 'nginx' ;;
		caddy)        printf 'caddy' ;;
		certbot)      printf 'certbot' ;;
		ufw)          printf 'ufw' ;;
		firewalld)    printf 'firewalld' ;;
		docker-ce)    printf 'docker' ;;
		docker-compose-plugin) printf 'docker-compose' ;;
		*) printf '%s' "$1" ;;
	esac
}
