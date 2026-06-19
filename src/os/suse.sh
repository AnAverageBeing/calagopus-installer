#!/usr/bin/env bash
#
# src/os/suse.sh - openSUSE / SLES family prep.
#
# Adds the Docker upstream repo (Virtualization:containers) on openSUSE.
# PostgreSQL is available from the standard OSS / server:database repos.

if [ -n "${CALAGOPUS_LIB_OS_SUSE:-}" ]; then return 0; fi
CALAGOPUS_LIB_OS_SUSE=1

suse_add_docker_repo() {
	if system_as_root zypper lr 2>/dev/null | grep -qi 'Virtualization:containers'; then
		log_debug "docker repo present"; return 0
	fi
	system_as_root zypper ar -f https://download.opensuse.org/repositories/Virtualization:containers/openSUSE_Tumbleweed/Virtualization:containers.repo 2>/dev/null || true
	system_as_root zypper --gpg-auto-import-keys refresh 2>/dev/null || true
}

suse_add_postgres_repo() { :; }  # in standard repos

os_family_prepare() {
	os_pkg_install curl ca-certificates
	system_as_root zypper --gpg-auto-import-keys refresh 2>/dev/null || true
}
