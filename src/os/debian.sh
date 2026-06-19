#!/usr/bin/env bash
#
# src/os/debian.sh - Debian/Ubuntu family preparation.
#
# Provides os_family_prepare(): installs ca-certificates/ gnupg/ curl if
# missing and adds the upstream repositories the installer relies on
# (Docker's official repo, PostgreSQL APT repo). Idempotent: skips work that
# is already done so re-runs are safe and fast.

if [ -n "${CALAGOPUS_LIB_OS_DEBIAN:-}" ]; then return 0; fi
CALAGOPUS_LIB_OS_DEBIAN=1

# Codename (e.g. jammy, bookworm) - falls back to lsb_release if UBUNTU_CODENAME
# / DEBIAN_CODENAME is absent from os-release.
_debian_codename() {
	local cn="${UBUNTU_CODENAME:-${DEBIAN_CODENAME:-}}"
	if [ -z "$cn" ] && command -v lsb_release >/dev/null 2>&1; then
		cn="$(lsb_release -cs 2>/dev/null)"
	fi
	printf '%s' "$cn"
}

# Ensure APT uses HTTPS transport + basic key tooling.
_debian_ensure_apt_prereqs() {
	os_pkg_install ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common
}

# Add Docker's official APT repo (idempotent).
_debian_add_docker_repo() {
	local keyring="/etc/apt/keyrings/docker.asc" repo="/etc/apt/sources.list.d/docker.list"
	if [ -f "$repo" ] && [ -f "$keyring" ]; then
		log_debug "docker apt repo already configured"
		return 0
	fi
	_debian_ensure_apt_prereqs
	system_as_root install -d -m0755 /etc/apt/keyrings
	curl -fsSL "https://download.docker.com/linux/${OS_ID}.gpg" \
		| system_as_root tee "$keyring" >/dev/null
	system_as_root chmod a+r "$keyring"
	local arch; arch="$(uname -m)"; [ "$arch" = "aarch64" ] && arch="arm64"
	local cn; cn="$(_debian_codename)"
	local line="deb [arch=${arch} signed-by=${keyring}] https://download.docker.com/linux/${OS_ID} ${cn} stable"
	system_as_root tee "$repo" >/dev/null <<<"$line"
	OS_PKG_REFRESHED=0
	os_pkg_refresh
}

# Add PostgreSQL upstream APT repo (idempotent). We only need this for native
# (binary) panel installs that want a recent Postgres; the Docker path uses
# the official container instead.
_debian_add_postgres_repo() {
	local keyring="/etc/apt/keyrings/postgresql.asc" repo="/etc/apt/sources.list.d/pgdg.list"
	if [ -f "$repo" ] && [ -f "$keyring" ]; then
		log_debug "postgresql apt repo already configured"
		return 0
	fi
	_debian_ensure_apt_prereqs
	system_as_root install -d -m0755 /etc/apt/keyrings
	curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
		| system_as_root tee "$keyring" >/dev/null
	system_as_root chmod a+r "$keyring"
	local cn; cn="$(_debian_codename)"
	system_as_root tee "$repo" >/dev/null <<<"deb [signed-by=${keyring}] https://apt.postgresql.org/pub/repos/apt ${cn}-pgdg main"
	OS_PKG_REFRESHED=0
	os_pkg_refresh
}

# Public entry point invoked by detect.sh's os_load_family_module.
os_family_prepare() {
	_debian_ensure_apt_prereqs
	# We add repos lazily, only when a module actually needs them, to keep
	# plain panel installs lean. Dependencies/docker.sh calls _debian_add_docker_repo.
	:
}

# Exposed for the dependency modules.
debian_add_docker_repo()    { _debian_add_docker_repo; }
debian_add_postgres_repo()  { _debian_add_postgres_repo; }
