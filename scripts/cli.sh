#!/usr/bin/env bash
#
# scripts/cli.sh - Installed `calagopus-installer` CLI wrapper.
#
# A tiny shim installed to /usr/local/bin/calagopus-installer that dispatches
# the post-install commands (status, doctor, logs, repair, backup, restore,
# upgrade, reconfigure, remove) by re-invoking the modular installer with the
# right --action flag. This keeps the operator-facing CLI small while all the
# real logic lives in the versioned module tree.
#
# The shim looks for the installer library tree in:
#   1. /var/lib/calagopus-installer/src  (installed copy)
#   2. the directory it was installed from (dev mode)
# and falls back to re-downloading itself if neither is present.

set -Eeuo pipefail

CALAGOPUS_CLI_VERSION="1.0.0"
CALAGOPUS_LIB_ROOT="${CALAGOPUS_LIB_ROOT:-/var/lib/calagopus-installer}"

cli_usage() {
	cat <<'USAGE'
Calagopus Installer CLI

Usage: calagopus-installer <command> [args]

Commands:
  status         Show system status
  doctor         Run health checks
  logs [N]       Show last N log lines (or follow with -f)
  repair         Repair common issues
  backup         Create a backup bundle
  restore [file] Restore from a backup bundle
  upgrade        Upgrade panel + wings to latest
  reconfigure    Re-run configuration prompts + restart
  remove         Uninstall Calagopus
  version        Show CLI version
  help           Show this help

Flags:
  --non-interactive   Run without prompts (use stored config / defaults)
  --yes               Assume yes to all confirmations
  --verbose           Verbose logging
  --quiet             Suppress non-error output
  --channel <ch>      Override release channel (stable|beta|nightly)
USAGE
}

cli_resolve_root() {
	if [ -d "${CALAGOPUS_LIB_ROOT}/src/installer.sh" ]; then return 0; fi
	if [ -f "$(dirname "$(readlink -f "$0")")/src/installer.sh" ]; then
		CALAGOPUS_LIB_ROOT="$(dirname "$(readlink -f "$0")")"; return 0
	fi
	echo "error: installer library tree not found at ${CALAGOPUS_LIB_ROOT}" >&2
	return 1
}

main() {
	local cmd="${1:-help}"; shift || true
	local extra=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-f|--follow) extra+=("--follow"); CALAGOPUS_FOLLOW=1; shift ;;
			*) extra+=("$1"); shift ;;
		esac
	done

	case "$cmd" in
		status)       cli_resolve_root && CALAGOPUS_ACTION=status       exec bash "${CALAGOPUS_LIB_ROOT}/src/installer.sh" --action status --non-interactive "${extra[@]+"${extra[@]}"}" ;;
		doctor)       cli_resolve_root && CALAGOPUS_ACTION=doctor       exec bash "${CALAGOPUS_LIB_ROOT}/src/installer.sh" --action doctor --non-interactive "${extra[@]+"${extra[@]}"}" ;;
		logs)         cli_resolve_root && CALAGOPUS_ACTION=logs         exec bash "${CALAGOPUS_LIB_ROOT}/src/installer.sh" --action logs --non-interactive "${extra[@]+"${extra[@]}"}" ;;
		repair)       cli_resolve_root && CALAGOPUS_ACTION=repair       exec bash "${CALAGOPUS_LIB_ROOT}/src/installer.sh" --action repair --yes "${extra[@]+"${extra[@]}"}" ;;
		backup)       cli_resolve_root && CALAGOPUS_ACTION=backup       exec bash "${CALAGOPUS_LIB_ROOT}/src/installer.sh" --action backup --non-interactive "${extra[@]+"${extra[@]}"}" ;;
		restore)      cli_resolve_root && CALAGOPUS_ACTION=restore      exec bash "${CALAGOPUS_LIB_ROOT}/src/installer.sh" --action restore --yes "${extra[@]+"${extra[@]}"}" ;;
		upgrade)      cli_resolve_root && CALAGOPUS_ACTION=upgrade      exec bash "${CALAGOPUS_LIB_ROOT}/src/installer.sh" --action upgrade --yes "${extra[@]+"${extra[@]}"}" ;;
		reconfigure)  cli_resolve_root && CALAGOPUS_ACTION=reconfigure  exec bash "${CALAGOPUS_LIB_ROOT}/src/installer.sh" --action reconfigure "${extra[@]+"${extra[@]}"}" ;;
		remove)       cli_resolve_root && CALAGOPUS_ACTION=remove       exec bash "${CALAGOPUS_LIB_ROOT}/src/installer.sh" --action remove "${extra[@]+"${extra[@]}"}" ;;
		version)      echo "calagopus-installer CLI v${CALAGOPUS_CLI_VERSION}" ;;
		help|-h|--help) cli_usage ;;
		*) echo "unknown command: $cmd" >&2; cli_usage; exit 1 ;;
	esac
}

main "$@"
