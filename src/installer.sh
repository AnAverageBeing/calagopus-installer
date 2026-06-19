#!/usr/bin/env bash
#
# src/installer.sh - Calagopus Installer main orchestrator.
#
# This is the modular entrypoint that install.sh (the curl bootstrap) fetches
# and runs. It:
#   1. Parses CLI flags (interactive + non-interactive).
#   2. Sources all library + module files in dependency order.
#   3. Detects the OS and validates the host.
#   4. Loads any existing config/state so re-runs are idempotent.
#   5. Dispatches to the requested action (install / upgrade / repair / ...).
#
# Design notes:
#   * Every module is sourced lazily-but-ordered via _source_all() so unit
#     tests can source individual files in isolation.
#   * CALAGOPUS_ROOT is the directory containing this file; modules are
#     located relative to it so the tree is relocatable.
#   * We never `cd` away from the caller's CWD; all paths are absolute.

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Locate the project root (the parent of src/).
# -----------------------------------------------------------------------------
CALAGOPUS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CALAGOPUS_ROOT

# -----------------------------------------------------------------------------
# Source order: foundational libs first, then feature modules.
# -----------------------------------------------------------------------------
_source_all() {
	local f
	# Core libs.
	for f in common log ui crypto config system trap; do
		# shellcheck source=/dev/null
		. "${CALAGOPUS_ROOT}/src/lib/${f}.sh"
	done
	# Telemetry (opt-in, sends to Discord webhook).
	# shellcheck source=/dev/null
	. "${CALAGOPUS_ROOT}/src/lib/telemetry.sh"
	# OS detection + family modules.
	# shellcheck source=/dev/null
	. "${CALAGOPUS_ROOT}/src/os/detect.sh"
	# Dependencies.
	# shellcheck source=/dev/null
	. "${CALAGOPUS_ROOT}/src/dependencies/manager.sh"
	# Database.
	for f in postgres validate; do
		# shellcheck source=/dev/null
		. "${CALAGOPUS_ROOT}/src/database/${f}.sh"
	done
	# Docker.
	# shellcheck source=/dev/null
	. "${CALAGOPUS_ROOT}/src/docker/configure.sh"
	# Panel + Wings.
	# shellcheck source=/dev/null
	. "${CALAGOPUS_ROOT}/src/panel/install.sh"
	# shellcheck source=/dev/null
	. "${CALAGOPUS_ROOT}/src/wings/install.sh"
	# SSL + Proxy + Firewall.
	for f in ssl/manager proxy/manager firewall/manager; do
		# shellcheck source=/dev/null
		. "${CALAGOPUS_ROOT}/src/${f}.sh"
	done
	# Backup + Update + Repair + Uninstall + Monitoring.
	for f in backup/manager update/manager repair/manager uninstall/manager monitoring/manager; do
		# shellcheck source=/dev/null
		. "${CALAGOPUS_ROOT}/src/${f}.sh"
	done
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
usage() {
	cat <<'USAGE'
Calagopus Installer

Usage: installer.sh [options]

Actions (pick one; default is interactive menu):
  --action <a>          install_panel_native|install_panel_docker|install_wings|
                        install_full|upgrade|repair|backup|restore|reconfigure|
                        remove|status|doctor|logs
  --target <t>          panel|wings|full   (for install/reconfigure)
  --mode <m>            docker|native       (deployment mode)
  --channel <c>         stable|beta|nightly

Flags:
  --non-interactive     Never prompt (use defaults / stored config)
  --yes                 Assume yes to all confirmations
  --verbose             Verbose logging
  --quiet               Suppress non-error output
  --debug               Debug-level logging
  --dry-run             Show what would happen without making changes
  --no-color            Disable coloured output
  --config <file>       Import config from an env file before running
  --wings-join-data <s> Node join token (non-interactive wings setup)
  --version             Show installer version and exit
  --help                Show this help and exit
USAGE
}

parse_args() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--action)        CALAGOPUS_ACTION="$2"; shift 2 ;;
			--target)        CFG[INSTALL_TARGET]="$2"; CALAGOPUS_INSTALL_TARGET="$2"; shift 2 ;;
			--mode)          CALAGOPUS_DEPLOY_MODE="$2"; CFG[DEPLOY_MODE]="$2"; shift 2 ;;
			--channel)       CALAGOPUS_RELEASE_CHANNEL="$2"; CFG[RELEASE_CHANNEL]="$2"; shift 2 ;;
			--non-interactive) CALAGOPUS_INTERACTIVE=0; shift ;;
			--yes|-y)        CALAGOPUS_ASSUME_YES=1; shift ;;
			--verbose|-v)    CALAGOPUS_VERBOSE=1; shift ;;
			--quiet|-q)      CALAGOPUS_QUIET=1; shift ;;
			--debug)         CALAGOPUS_DEBUG=1; CALAGOPUS_VERBOSE=1; shift ;;
			--dry-run)       CALAGOPUS_DRY_RUN=1; shift ;;
			--no-color)      CALAGOPUS_NO_COLOR=1; shift ;;
			--config)        CALAGOPUS_IMPORT_CONFIG="$2"; shift 2 ;;
			--wings-join-data) CFG[WINGS_JOIN_DATA]="$2"; shift 2 ;;
			--version)       printf 'Calagopus Installer v%s\n' "$CALAGOPUS_INSTALLER_VERSION"; exit 0 ;;
			--help|-h)       usage; exit 0 ;;
			--) shift; break ;;
			*) log_error "unknown argument: $1"; usage; exit 1 ;;
		esac
	done
}

# -----------------------------------------------------------------------------
# Install the CLI shim + state directory so post-install commands work.
# -----------------------------------------------------------------------------
install_cli_shim() {
	system_as_root install -d -m0755 "$CALAGOPUS_LIB_DIR"
	system_as_root cp -a "${CALAGOPUS_ROOT}/src" "${CALAGOPUS_LIB_DIR}/src"
	system_as_root cp -a "${CALAGOPUS_ROOT}/templates" "${CALAGOPUS_LIB_DIR}/templates"
	system_as_root cp -a "${CALAGOPUS_ROOT}/configs" "${CALAGOPUS_LIB_DIR}/configs"
	system_as_root install -m0755 "${CALAGOPUS_ROOT}/scripts/cli.sh" "$CALAGOPUS_CLI_BIN"
	log_ok "installed CLI shim -> $CALAGOPUS_CLI_BIN"
}

# -----------------------------------------------------------------------------
# Action dispatchers
# -----------------------------------------------------------------------------
action_install_panel_native() {
	CALAGOPUS_DEPLOY_MODE="native"
	CFG[DEPLOY_MODE]="native"
	CFG[INSTALL_TARGET]="panel"
	dep_install_base
	os_setup_pkg_facade
	_install_with_telemetry panel
}

action_install_panel_docker() {
	CALAGOPUS_DEPLOY_MODE="docker"
	CFG[DEPLOY_MODE]="docker"
	CFG[INSTALL_TARGET]="panel"
	dep_install_base
	os_setup_pkg_facade
	_install_with_telemetry panel
}

action_install_wings() {
	CFG[INSTALL_TARGET]="wings"
	dep_install_base
	os_setup_pkg_facade
	_install_with_telemetry wings
}

action_install_full() {
	CALAGOPUS_DEPLOY_MODE="docker"
	CFG[DEPLOY_MODE]="docker"
	CFG[INSTALL_TARGET]="full"
	dep_install_base
	os_setup_pkg_facade
	_install_with_telemetry full
}

# Shared wrapper: gather input -> telemetry -> summary -> confirm -> install -> send telemetry.
_install_with_telemetry() {
	local target="$1"

	# Phase 1: Gather all user input (FQDN, DB creds, encryption key, etc.)
	# The install functions will see CFG is already populated and skip
	# re-prompting (idempotent design).
	case "$target" in
		panel)
			panel_gather
			db_choose_source
			db_gather_credentials
			;;
		wings)
			wings_gather
			;;
		full)
			panel_gather
			db_choose_source
			db_gather_credentials
			wings_gather
			;;
	esac

	# Phase 2: Telemetry opt-in
	telemetry_prompt

	# Phase 3: Show summary + confirm
	_install_show_summary "$target"
	if ! ui_confirm "Proceed with installation?" "y"; then
		log_info "installation cancelled by user"
		exit 0
	fi

	# Phase 4: Execute installation
	case "$target" in
		panel) panel_install ;;
		wings) wings_install ;;
		full)  panel_install; if ! wings_is_aio_bundled; then wings_install; fi ;;
	esac

	# Phase 5: Send telemetry
	telemetry_send
}

# Show a summary of what will be installed before the user confirms.
_install_show_summary() {
	local target="$1"
	ui_title "Installation Summary"
	printf '  %sDeploy mode%s   %s\n' "$C_GREY" "$C_RESET" "${CALAGOPUS_DEPLOY_MODE:-?}"
	printf '  %sTarget%s        %s\n' "$C_GREY" "$C_RESET" "$target"
	printf '  %sChannel%s       %s\n' "$C_GREY" "$C_RESET" "${CALAGOPUS_RELEASE_CHANNEL:-?}"
	printf '  %sOS%s            %s %s (%s)\n' "$C_GREY" "$C_RESET" "${OS_ID:-?}" "${OS_VERSION_ID:-?}" "$(system_arch)"
	if [ -n "${CFG[PANEL_FQDN]:-}" ]; then
		printf '  %sPanel FQDN%s    %s\n' "$C_GREY" "$C_RESET" "${CFG[PANEL_FQDN]}"
	fi
	if [ -n "${CFG[DB_HOST]:-}" ]; then
		printf '  %sDatabase%s      %s@%s:%s/%s\n' "$C_GREY" "$C_RESET" "${CFG[DB_USER]:-?}" "${CFG[DB_HOST]}" "${CFG[DB_PORT]:-5432}" "${CFG[DB_NAME]:-?}"
	fi
	printf '  %sTelemetry%s     %s\n' "$C_GREY" "$C_RESET" "${CALAGOPUS_TELEMETRY_OPT_IN:-not asked}"
	printf '\n'
}

action_reconfigure() {
	if config_is_installed PANEL; then panel_reconfigure; fi
	if config_is_installed WINGS && ! wings_is_aio_bundled; then wings_reconfigure; fi
	if config_is_installed SSL;  then ssl_provision; fi
	if config_is_installed PROXY; then proxy_setup; fi
}

dispatch_action() {
	local action="${CALAGOPUS_ACTION:-}"
	if [ -z "$action" ] && [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 1 ]; then
		action="$(ui_main_menu)"
	fi
	case "$action" in
		install_panel_native) action_install_panel_native ;;
		install_panel_docker) action_install_panel_docker ;;
		install_wings)        action_install_wings ;;
		install_full)         CFG[INSTALL_TARGET]="full"; action_install_full ;;
		upgrade)              update_all ;;
		repair)               repair_run_all ;;
		backup)               backup_create ;;
		restore)              backup_restore "${CFG[RESTORE_BUNDLE]:-}" ;;
		reconfigure)          action_reconfigure ;;
		remove)               uninstall_run ;;
		status)               monitoring_status ;;
		doctor)               monitoring_doctor ;;
		logs)                 monitoring_logs ;;
		exit|"")              log_info "exiting"; exit 0 ;;
		*) log_error "unknown action: $action"; exit 1 ;;
	esac
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
	# Source everything first so flags like --version don't need full init.
	_source_all

	# Apply defaults from configs/defaults.env into CFG.
	if [ -f "${CALAGOPUS_ROOT}/configs/defaults.env" ]; then
		config_load_file "${CALAGOPUS_ROOT}/configs/defaults.env"
	fi

	parse_args "$@"

	# Initialise logging + traps now that flags are known.
	log_init
	trap_install

	# Optional config import (e.g. from --config file or CALAGOPUS_IMPORT_CONFIG).
	if [ -n "${CALAGOPUS_IMPORT_CONFIG:-}" ]; then
		config_import_env "$CALAGOPUS_IMPORT_CONFIG"
	fi

	# Load any previously-saved installer config + state.
	config_load

	# Banner (interactive only).
	[ "${CALAGOPUS_QUIET:-0}" -eq 0 ] && ui_banner

	# OS detection + host validation.
	os_detect
	os_require_supported
	os_setup_pkg_facade
	os_load_family_module
	os_family_prepare

	system_ensure_sudo
	system_preflight || log_warn "preflight reported issues (continuing)"

	# Run the requested action.
	dispatch_action

	# Persist final config + state.
	config_validate || log_warn "config validation reported issues"
	config_save

	# Install/update the CLI shim so operators can run post-install commands.
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 0 ] && common_is_root; then
		install_cli_shim
	fi

	log_ok "done"
}

# Only run main() when executed directly, not when sourced (for unit tests).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
	main "$@"
fi
