#!/usr/bin/env bash
#
# src/os/detect.sh - Operating system detection and supported-distro matrix.
#
# Detects the distribution id + version in a portable way (without relying on
# the `lsb_release` command being installed) and matches it against the list of
# OSes Calagopus officially supports (per the Panel Overview "Minimum
# Requirements"). Unsupported distros fail gracefully with a clear message.
#
# Detected facts are exposed via the OS_* globals so other modules can branch:
#   OS_ID        - lowercase distro id (ubuntu, debian, rocky, almalinux, ...)
#   OS_FAMILY    - debian | rhel | arch | suse | unknown
#   OS_VERSION   - major version string (e.g. "22.04", "11", "9")
#   OS_VERSION_ID- numeric version id from os-release
#   OS_PRETTY    - human-readable name
#   OS_SUPPORTED - 1 if the matrix says we can proceed, 0 otherwise

if [ -n "${CALAGOPUS_LIB_OS_DETECT:-}" ]; then return 0; fi
CALAGOPUS_LIB_OS_DETECT=1

OS_ID=""
OS_FAMILY=""
OS_VERSION=""
OS_VERSION_ID=""
OS_PRETTY=""
OS_SUPPORTED=0

# -----------------------------------------------------------------------------
# Detection
# -----------------------------------------------------------------------------
os_detect() {
	local rel="/etc/os-release"
	if [ ! -r "$rel" ]; then
		rel="/usr/lib/os-release"
	fi
	if [ ! -r "$rel" ]; then
		log_error "no os-release file found; cannot detect distribution"
		OS_ID="unknown"; OS_FAMILY="unknown"; OS_SUPPORTED=0
		return 1
	fi
	# shellcheck disable=SC1090
	. "$rel"
	OS_ID="${ID:-unknown}"
	OS_ID="${OS_ID,,}"                    # lowercase
	OS_VERSION_ID="${VERSION_ID:-}"
	OS_PRETTY="${PRETTY_NAME:-$ID}"
	OS_VERSION="${OS_VERSION_ID}"

	# Resolve family from ID_LIKE when the exact id is non-canonical.
	case "$OS_ID" in
		ubuntu|debian|linuxmint|raspbian|kali) OS_FAMILY="debian" ;;
		rocky|almalinux|centos|rhel|fedora|ol|cloudlinux|amzn) OS_FAMILY="rhel" ;;
		arch|manjaro|endeavouros|garuda|cachyos) OS_FAMILY="arch" ;;
		opensuse*|sles|suse) OS_FAMILY="suse" ;;
		*)
			case "${ID_LIKE:-}" in
				*debian*) OS_FAMILY="debian" ;;
				*rhel*|*fedora*|*centos*) OS_FAMILY="rhel" ;;
				*arch*) OS_FAMILY="arch" ;;
				*suse*) OS_FAMILY="suse" ;;
				*) OS_FAMILY="unknown" ;;
			esac
			;;
	esac

	# Normalise a couple of derivatives onto their upstream id for matching.
	case "$OS_ID" in
		linuxmint|raspbian|kali) OS_ID_BASE="debian" ;;
		*) OS_ID_BASE="$OS_ID" ;;
	esac

	os_check_supported
}

# -----------------------------------------------------------------------------
# Supported-distro matrix (per Calagopus docs: Ubuntu 22.04+, Debian 11+, and
# anything that runs modern Docker; we additionally allow RHEL-family 8+/9,
# Fedora, Arch, and SUSE as the upstream binaries are static Rust builds).
# Returns 0 if supported, 1 otherwise. Sets OS_SUPPORTED accordingly.
# -----------------------------------------------------------------------------
os_check_supported() {
	local major
	major="$(printf '%s' "${OS_VERSION_ID:-0}" | cut -d. -f1)"
	OS_SUPPORTED=0

	_debian_min() { [ "${major:-0}" -ge "$1" ] 2>/dev/null; }

	case "$OS_ID" in
		ubuntu)    _debian_min 22 && OS_SUPPORTED=1 ;;
		debian)    _debian_min 11 && OS_SUPPORTED=1 ;;
		raspbian)  _debian_min 11 && OS_SUPPORTED=1 ;;
		rocky|almalinux|centos|rhel|ol) _debian_min 8 && OS_SUPPORTED=1 ;;
		fedora)    _debian_min 38 && OS_SUPPORTED=1 ;;
		amzn)      _debian_min 2023 && OS_SUPPORTED=1 ;;
		arch|manjaro|endeavouros) OS_SUPPORTED=1 ;;
		opensuse*|suse) OS_SUPPORTED=1 ;;
		linuxmint|kali) _debian_min 21 && OS_SUPPORTED=1 ;;
		*) OS_SUPPORTED=0 ;;
	esac

	# Soft-support: even if not in the explicit matrix, anything that already
	# has Docker working is accepted with a warning (matches Calagopus' own
	# "anything that supports modern Docker" guidance).
	if [ "$OS_SUPPORTED" -eq 0 ] && common_cmd_exists docker; then
		OS_SUPPORTED=2  # "soft" supported
	fi
}

# Human-readable support verdict.
os_support_label() {
	case "$OS_SUPPORTED" in
		1) printf 'supported' ;;
		2) printf 'community-supported (Docker present)' ;;
		*) printf 'unsupported' ;;
	esac
}

# Fail-fast gate used by the installer before doing anything destructive.
os_require_supported() {
	os_detect
	if [ "$OS_SUPPORTED" -eq 0 ]; then
		log_error "unsupported operating system: ${OS_PRETTY:-$OS_ID} ${OS_VERSION_ID:-}"
		log_error "Calagopus officially supports Ubuntu 22.04+, Debian 11+, or any host"
		log_error "that can run modern Docker. See https://calagopus.com/docs/panel/overview"
		if [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 1 ] && [ "${CALAGOPUS_ASSUME_YES:-0}" -eq 0 ]; then
			ui_confirm "Continue anyway (unsupported)?" "n" || log_die "aborted"
		else
			return 1
		fi
	fi
	log_ok "OS: ${OS_PRETTY:-$OS_ID} ($OS_ID $OS_VERSION) -> $(os_support_label)"
	return 0
}

# -----------------------------------------------------------------------------
# Package-manager facade. Every per-OS module sets these so dependencies/
# has a single, uniform interface regardless of distro.
#   OS_PKGINSTALL  - command prefix to install packages
#   OS_PKGUPDATE   - command to refresh package metadata
#   OS_PKGQUERY    - command that returns 0 if a package is installed
#   OS_PKGREMOVE   - command prefix to remove packages
# -----------------------------------------------------------------------------
os_setup_pkg_facade() {
	case "$OS_FAMILY" in
		debian)
			OS_PKGINSTALL=(apt-get install -y)
			OS_PKGUPDATE=(apt-get update -y)
			OS_PKGQUERY=(dpkg -s)
			OS_PKGREMOVE=(apt-get remove -y)
			;;
		rhel)
			OS_PKGINSTALL=(dnf install -y)
			OS_PKGUPDATE=(dnf check-update -y)
			OS_PKGQUERY=(rpm -q)
			OS_PKGREMOVE=(dnf remove -y)
			# Older RHEL 8 may still use yum.
			if ! command -v dnf >/dev/null 2>&1; then
				OS_PKGINSTALL=(yum install -y)
				OS_PKGUPDATE=(yum check-update -y)
				OS_PKGREMOVE=(yum remove -y)
			fi
			;;
		arch)
			OS_PKGINSTALL=(pacman -S --noconfirm --needed)
			OS_PKGUPDATE=(pacman -Sy --noconfirm)
			OS_PKGQUERY=(pacman -Qi)
			OS_PKGREMOVE=(pacman -R --noconfirm)
			;;
		suse)
			OS_PKGINSTALL=(zypper install -y)
			OS_PKGUPDATE=(zypper refresh)
			OS_PKGQUERY=(rpm -q)
			OS_PKGREMOVE=(zypper remove -y)
			;;
		*)
			log_warn "no package manager facade for family '$OS_FAMILY'"
			OS_PKGINSTALL=(); OS_PKGUPDATE=(); OS_PKGQUERY=(); OS_PKGREMOVE=()
			;;
	esac
}

# Public helper: refresh metadata once per run (idempotent).
os_pkg_refresh() {
	[ "${#OS_PKGUPDATE[@]}" -gt 0 ] || return 0
	[ "${OS_PKG_REFRESHED:-0}" -eq 1 ] && return 0
	log_run "refreshing package metadata" -- system_as_root "${OS_PKGUPDATE[@]}" || true
	OS_PKG_REFRESHED=1
}

# Public helper: install one or more packages if not already present.
# Usage: os_pkg_install pkg1 pkg2 ...
os_pkg_install() {
	[ "$#" -gt 0 ] || return 0
	[ "${#OS_PKGINSTALL[@]}" -gt 0 ] || { log_error "no package manager configured"; return 1; }
	local missing=() pkg
	for pkg in "$@"; do
		if [ "${#OS_PKGQUERY[@]}" -gt 0 ]; then
			if system_as_root "${OS_PKGQUERY[@]}" "$pkg" >/dev/null 2>&1; then
				log_debug "already installed: $pkg"
				continue
			fi
		fi
		missing+=("$pkg")
	done
	[ "${#missing[@]}" -eq 0 ] && return 0
	os_pkg_refresh
	log_run "installing: ${missing[*]}" -- system_as_root "${OS_PKGINSTALL[@]}" "${missing[@]}"
}

# Public helper: remove packages (best-effort).
os_pkg_remove() {
	[ "$#" -gt 0 ] || return 0
	[ "${#OS_PKGREMOVE[@]}" -gt 0 ] || return 0
	log_run "removing: $*" -- system_as_root "${OS_PKGREMOVE[@]}" "$@" || true
}

# Source the per-family module that supplies family-specific tweaks (repo
# setup for postgres, docker, etc.). Each defines os_family_prepare.
os_load_family_module() {
	local mod
	case "$OS_FAMILY" in
		debian) mod="src/os/debian.sh" ;;
		rhel)   mod="src/os/rhel.sh"   ;;
		arch)   mod="src/os/arch.sh"   ;;
		suse)   mod="src/os/suse.sh"   ;;
		*) log_warn "no family module for '$OS_FAMILY'"; return 0 ;;
	esac
	# shellcheck source=/dev/null
	. "${CALAGOPUS_ROOT}/${mod}"
}
