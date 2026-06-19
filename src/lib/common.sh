#!/usr/bin/env bash
#
# src/lib/common.sh - Global constants, defaults, and shared state.
#
# Sourced by every other module. Holds the single source of truth for paths,
# versions, image tags, and the runtime "config" associative array that the
# rest of the installer reads from. Keeping these here lets every module stay
# idempotent: a function can ask "is this already configured?" via the helpers
# in config.sh instead of re-prompting the user or clobbering state.
#
# This file MUST NOT produce side effects on its own - it only declares data
# and trivial helpers so that sourcing it from unit tests is safe.

# Guard against double-sourcing.
if [ -n "${CALAGOPUS_LIB_COMMON:-}" ]; then return 0; fi
CALAGOPUS_LIB_COMMON=1

# -----------------------------------------------------------------------------
# Project metadata
# -----------------------------------------------------------------------------
CALAGOPUS_INSTALLER_NAME="Calagopus Installer"
CALAGOPUS_INSTALLER_VERSION="1.0.0"
CALAGOPUS_INSTALLER_CODENAME="anchor"
CALAGOPUS_INSTALLER_REPO="https://github.com/calagopus-installer/calagopus-installer"

# Upstream Calagopus references (used for downloads).
CALAGOPUS_PANEL_REPO="https://github.com/calagopus/panel"
CALAGOPUS_WINGS_REPO="https://github.com/calagopus/wings"
CALAGOPUS_PANEL_RAW="https://raw.githubusercontent.com/calagopus/panel/main"
CALAGOPUS_WINGS_RAW="https://raw.githubusercontent.com/calagopus/wings/main"
CALAGOPUS_PANEL_RELEASES="${CALAGOPUS_PANEL_REPO}/releases/latest/download"
CALAGOPUS_WINGS_RELEASES="${CALAGOPUS_WINGS_REPO}/releases/latest/download"

# Docker image tags per release channel. The channel selects the tag suffix.
declare -gA CALAGOPUS_IMAGE_TAGS=(
	[panel_stable]="ghcr.io/calagopus/panel:latest"
	[panel_beta]="ghcr.io/calagopus/panel:latest-pre"
	[panel_nightly]="ghcr.io/calagopus/panel:nightly"
	[panel_stable_heavy]="ghcr.io/calagopus/panel:heavy"
	[panel_beta_heavy]="ghcr.io/calagopus/panel:heavy-pre"
	[panel_nightly_heavy]="ghcr.io/calagopus/panel:nightly-heavy"
	[panel_aio_stable]="ghcr.io/calagopus/panel:aio"
	[panel_aio_heavy]="ghcr.io/calagopus/panel:heavy-aio"
	[panel_aio_nightly]="ghcr.io/calagopus/panel:nightly-aio"
	[panel_aio_nightly_heavy]="ghcr.io/calagopus/panel:nightly-heavy-aio"
	[wings_stable]="ghcr.io/calagopus/wings:latest"
	[wings_beta]="ghcr.io/calagopus/wings:latest-pre"
	[wings_nightly]="ghcr.io/calagopus/wings:nightly"
)

# Compose file basenames shipped in the upstream repos.
declare -gA CALAGOPUS_COMPOSE_FILES=(
	[panel_aio]="compose.aio.yml"
	[panel_basic]="compose.yml"
	[panel_heavy]="compose.heavy.yml"
	[panel_backups]="compose.with-db-backups.yml"
	[panel_minimal]="compose.minimal.yml"
	[wings_local]="compose.local.yml"
)

# -----------------------------------------------------------------------------
# Filesystem layout (where the installer puts things)
# Defaults use :? to respect pre-set values (e.g. from test harnesses).
# -----------------------------------------------------------------------------
CALAGOPUS_ETC_DIR="${CALAGOPUS_ETC_DIR:-/etc/calagopus}"
CALAGOPUS_INSTALL_DIR="${CALAGOPUS_INSTALL_DIR:-/var/lib/calagopus}"
CALAGOPUS_PANEL_DIR="${CALAGOPUS_PANEL_DIR:-${CALAGOPUS_INSTALL_DIR}/panel}"
CALAGOPUS_WINGS_DIR="${CALAGOPUS_WINGS_DIR:-${CALAGOPUS_INSTALL_DIR}/wings}"
CALAGOPUS_LOG_DIR="${CALAGOPUS_LOG_DIR:-/var/log/calagopus}"
CALAGOPUS_BACKUP_DIR="${CALAGOPUS_BACKUP_DIR:-/var/backups/calagopus}"
CALAGOPUS_LIB_DIR="${CALAGOPUS_LIB_DIR:-/var/lib/calagopus-installer}"
CALAGOPUS_STATE_FILE="${CALAGOPUS_STATE_FILE:-${CALAGOPUS_LIB_DIR}/state.env}"
CALAGOPUS_CONFIG_FILE="${CALAGOPUS_CONFIG_FILE:-${CALAGOPUS_ETC_DIR}/installer.env}"
CALAGOPUS_PANEL_ENV="${CALAGOPUS_PANEL_ENV:-${CALAGOPUS_ETC_DIR}/panel.env}"
CALAGOPUS_PANEL_BIN="${CALAGOPUS_PANEL_BIN:-/usr/local/bin/calagopus-panel}"
CALAGOPUS_WINGS_BIN="${CALAGOPUS_WINGS_BIN:-/usr/local/bin/wings}"
CALAGOPUS_PANEL_SERVICE="${CALAGOPUS_PANEL_SERVICE:-calagopus-panel}"
CALAGOPUS_WINGS_SERVICE="${CALAGOPUS_WINGS_SERVICE:-wings}"
CALAGOPUS_CLI_BIN="${CALAGOPUS_CLI_BIN:-/usr/local/bin/calagopus-installer}"

# Default network ports (overridable via config).
declare -gA CALAGOPUS_PORTS=(
	[panel_http]=8000
	[panel_https]=8443
	[wings]=443
	[postgres]=5432
	[redis]=6379
)

# -----------------------------------------------------------------------------
# Runtime behaviour flags (set by arg parser in src/installer.sh)
# All use :- so environment / test harness can pre-set them.
# -----------------------------------------------------------------------------
CALAGOPUS_INTERACTIVE="${CALAGOPUS_INTERACTIVE:-1}"
CALAGOPUS_VERBOSE="${CALAGOPUS_VERBOSE:-0}"
CALAGOPUS_QUIET="${CALAGOPUS_QUIET:-0}"
CALAGOPUS_DEBUG="${CALAGOPUS_DEBUG:-0}"
CALAGOPUS_DRY_RUN="${CALAGOPUS_DRY_RUN:-0}"
CALAGOPUS_ASSUME_YES="${CALAGOPUS_ASSUME_YES:-0}"
CALAGOPUS_NO_COLOR="${CALAGOPUS_NO_COLOR:-0}"
CALAGOPUS_RELEASE_CHANNEL="${CALAGOPUS_RELEASE_CHANNEL:-stable}"
CALAGOPUS_DEPLOY_MODE="${CALAGOPUS_DEPLOY_MODE:-docker}"
CALAGOPUS_ACTION="${CALAGOPUS_ACTION:-}"
CALAGOPUS_INSTALL_TARGET="${CALAGOPUS_INSTALL_TARGET:-}"
CALAGOPUS_LOGFILE="${CALAGOPUS_LOGFILE:-${CALAGOPUS_LOG_DIR}/installer.log}"

# Runtime config associative array - the shared "what did the user pick?" bag.
# Modules read/write this; config.sh persists/loads it.
declare -gA CFG=()

# -----------------------------------------------------------------------------
# Tiny shared helpers (side-effect free)
# -----------------------------------------------------------------------------

# true if running as root (uid 0)
common_is_root() { [ "$(id -u)" -eq 0 ]; }

# echo a value with a default fallback
common_default() { printf '%s' "${1:-$2}"; }

# truthy test for "yes"/"y"/"1"/"true" (case-insensitive)
common_is_yes() {
	case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
		y|yes|1|true) return 0 ;;
		*) return 1 ;;
	esac
}

# returns 0 if the given command exists on PATH
common_cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# returns 0 if the given systemd unit exists (active or not)
common_unit_exists() { systemctl list-unit-files "${1}.service" 2>/dev/null | grep -q "${1}.service"; }
