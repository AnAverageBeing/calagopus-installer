#!/usr/bin/env bash
#
# install.sh - Calagopus Installer bootstrap entrypoint.
#
# This is the thin, curl-friendly bootstrap. It fetches the full, modular
# installer from the project's GitHub release and hands control over to it.
#
#   bash <(curl -sSL https://calagopus-installer.se)            # interactive
#   bash <(curl -sSL https://calagopus-installer.se) -- --help  # see flags
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
GITHUB_SOURCE="https://github.com/calagopus-installer/calagopus-installer"
SCRIPT_RELEASE="v1.0.0"
INSTALLER_BRANCH="${CALAGOPUS_INSTALLER_BRANCH:-main}"
INSTALLER_REPO_RAW="https://raw.githubusercontent.com/calagopus-installer/calagopus-installer/${INSTALLER_BRANCH}"

# -----------------------------------------------------------------------------
# Bootstrap helpers
# -----------------------------------------------------------------------------
bootstrap_log() { printf '[bootstrap] %s\n' "$*" >&2; }
bootstrap_die() { bootstrap_log "error: $*"; exit 1; }

# Resolve the latest released installer URL. Falls back to the raw branch
# when no release assets are available (development / pre-release stage).
resolve_installer_url() {
	local url
	url="${GITHUB_SOURCE}/releases/latest/download/installer.sh"
	if curl -fsSL -o /dev/null --max-time 10 "$url"; then
		printf '%s\n' "$url"
		return 0
	fi
	# Fall back to the in-tree modular entrypoint on the configured branch.
	printf '%s/%s\n' "${INSTALLER_REPO_RAW}" "src/installer.sh"
}

# Download a remote file into a temp dir and echo its path.
fetch_to_temp() {
	local url="$1" dest
	dest="$(mktemp -d "${TMPDIR:-/tmp}/calagopus-installer.XXXXXX")"
	if ! curl -fsSL -o "${dest}/installer.sh" "$url"; then
		rm -rf "$dest"
		return 1
	fi
	printf '%s\n' "$dest"
}

# -----------------------------------------------------------------------------
# Sanity checks before doing anything destructive
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

# -----------------------------------------------------------------------------
# Main bootstrap flow
# -----------------------------------------------------------------------------
main() {
	require_bash
	require_curl

	bootstrap_log "Calagopus Installer ${SCRIPT_RELEASE} bootstrap"

	local installer_url tmp_dir
	installer_url="$(resolve_installer_url)" \
		|| bootstrap_die "could not resolve a downloadable installer."

	bootstrap_log "downloading installer from ${installer_url}"
	tmp_dir="$(fetch_to_temp "$installer_url")" \
		|| bootstrap_die "failed to download the installer."

	# Propagate original CLI args (after the leading --, if present) to the
	# real installer so non-interactive / --help / --mode flags still work.
	local args=()
	if [ "$#" -gt 0 ]; then
		args=("$@")
	fi

	# shellcheck source=/dev/null
	if ! bash "${tmp_dir}/installer.sh" "${args[@]+"${args[@]}"}"; then
		local rc=$?
		rm -rf "$tmp_dir"
		bootstrap_die "installer exited with code ${rc}. See logs above."
	fi

	rm -rf "$tmp_dir"
}

main "$@"
