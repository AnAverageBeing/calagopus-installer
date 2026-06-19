#!/usr/bin/env bash
#
# install.sh - Calagopus Installer bootstrap entrypoint.
#
# This is the thin, curl-friendly bootstrap. It fetches the full modular
# installer tree from GitHub (as a tarball), extracts it to a temp directory,
# and hands control over to src/installer.sh.
#
#   bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh)
#
# For non-interactive use, append -- and any installer flags:
#   bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh) -- --help
#
# If you already cloned this repository, run `src/installer.sh` directly
# instead - this bootstrap is only needed for the one-line remote install.
#
# Calagopus Installer
# Copyright (C) 2026 Calagopus Installer contributors
# Licensed under the MIT License.

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Release configuration (updated per release by maintainers - see CONTRIBUTING)
# -----------------------------------------------------------------------------
GITHUB_REPO="https://github.com/AnAverageBeing/calagopus-installer"
GITHUB_ARCHIVE="https://github.com/AnAverageBeing/calagopus-installer/archive/refs/heads"
SCRIPT_RELEASE="v1.0.0"
INSTALLER_BRANCH="${CALAGOPUS_INSTALLER_BRANCH:-main}"

# -----------------------------------------------------------------------------
# Bootstrap helpers
# -----------------------------------------------------------------------------
bootstrap_log() { printf '[bootstrap] %s\n' "$*" >&2; }
bootstrap_die() { bootstrap_log "error: $*"; exit 1; }

# -----------------------------------------------------------------------------
# Sanity checks before doing anything
# -----------------------------------------------------------------------------
require_bash() {
	if [ -z "${BASH_VERSION:-}" ]; then
		bootstrap_die "This installer must be run with bash, not sh."
	fi
}

require_curl() {
	if ! command -v curl >/dev/null 2>&1; then
		bootstrap_die "curl is required to bootstrap the installer. Install it and re-run."
	fi
}

# Download the full repo tarball from GitHub and extract it.
# Echoes the path to the extracted tree (containing src/, templates/, etc.).
fetch_repo_to_temp() {
	local archive_url="${GITHUB_ARCHIVE}/${INSTALLER_BRANCH}.tar.gz"
	local tmp_dir
	tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cal-installer.XXXXXX")"

	bootstrap_log "downloading installer from ${archive_url}"
	if ! curl -fsSL "$archive_url" -o "${tmp_dir}/repo.tar.gz"; then
		rm -rf "$tmp_dir"
		return 1
	fi

	# Extract; GitHub names the top dir <repo>-<branch>.
	tar -xzf "${tmp_dir}/repo.tar.gz" -C "$tmp_dir" 2>/dev/null || {
		rm -rf "$tmp_dir"
		return 1
	}
	rm -f "${tmp_dir}/repo.tar.gz"

	# Find the extracted directory (GitHub names it calagopus-installer-<branch>).
	local extracted
	extracted="$(find "$tmp_dir" -maxdepth 1 -type d -name 'calagopus-installer*' | head -1)"
	[ -n "$extracted" ] || {
		rm -rf "$tmp_dir"
		return 1
	}

	printf '%s\n' "$extracted"
}

# -----------------------------------------------------------------------------
# Main bootstrap flow
# -----------------------------------------------------------------------------
main() {
	require_bash
	require_curl

	bootstrap_log "Calagopus Installer ${SCRIPT_RELEASE} bootstrap"

	local repo_dir
	repo_dir="$(fetch_repo_to_temp)" \
		|| bootstrap_die "failed to download the installer from GitHub."

	# Propagate original CLI args to the modular installer.
	local args=()
	if [ "$#" -gt 0 ]; then
		args=("$@")
	fi

	# shellcheck source=/dev/null
	if ! bash "${repo_dir}/src/installer.sh" "${args[@]+"${args[@]}"}"; then
		local rc=$?
		rm -rf "$(dirname "$repo_dir")"
		bootstrap_die "installer exited with code ${rc}. See logs above."
	fi

	rm -rf "$(dirname "$repo_dir")"
}

main "$@"
