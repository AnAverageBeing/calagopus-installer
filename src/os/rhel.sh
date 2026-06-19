#!/usr/bin/env bash
#
# src/os/rhel.sh - RHEL / Rocky / AlmaLinux / Fedora / CentOS family prep.
#
# Adds the Docker CE upstream repo and (for native installs) the PostgreSQL
# upstream repo via dnf. Idempotent. Handles dnf vs yum and the
# EL8/EL9/Fedora differences in repo URLs.

if [ -n "${CALAGOPUS_LIB_OS_RHEL:-}" ]; then return 0; fi
CALAGOPUS_LIB_OS_RHEL=1

# EL major version (8/9) or 0 for Fedora.
_rhel_el_version() {
	case "$OS_ID" in
		rocky|almalinux|centos|rhel|ol) printf '%s' "$(printf '%s' "${OS_VERSION_ID}" | cut -d. -f1)" ;;
		*) printf '0' ;;
	esac
}

_rhel_add_docker_repo() {
	local repo="/etc/yum.repos.d/docker-ce.repo"
	if [ -f "$repo" ]; then log_debug "docker repo present"; return 0; fi
	os_pkg_install dnf-plugins-core curl
	if system_as_root dnf config-manager --add-repo \
		https://download.docker.com/linux/rhel/docker-ce.repo 2>/dev/null; then
		:
	else
		# Fedora uses the fedora repo path.
		system_as_root dnf config-manager --add-repo \
			https://download.docker.com/linux/fedora/docker-ce.repo
	fi
}

_rhel_add_postgres_repo() {
	local el; el="$(_rhel_el_version)"
	[ "$el" -ge 8 ] 2>/dev/null || { log_debug "postgres upstream repo skipped (non-EL)"; return 0; }
	local repo="/etc/yum.repos.d/pgdg-rpm.repo"
	if [ -f "$repo" ]; then log_debug "postgres repo present"; return 0; fi
	os_pkg_install curl
	system_as_root dnf install -y "https://download.postgresql.org/pub/repos/yum/reporpms/EL-${el}-x86_64/pgdg-redhat-repo-latest.noarch.rpm" 2>/dev/null || true
}

os_family_prepare() {
	os_pkg_install curl ca-certificates
	# disable the modular conflict for older EL8 if present
	if [ "$(_rhel_el_version)" = "8" ] && command -v dnf >/dev/null 2>&1; then
		system_as_root dnf -y module disable container-tools 2>/dev/null || true
	fi
}

rhel_add_docker_repo()   { _rhel_add_docker_repo; }
rhel_add_postgres_repo() { _rhel_add_postgres_repo; }
