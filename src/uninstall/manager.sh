#!/usr/bin/env bash
#
# src/uninstall/manager.sh - Remove Calagopus Panel + Wings cleanly.
#
# Stops services, removes binaries / compose stacks / config, and optionally
# drops the database + purges backups. Always asks for confirmation unless
# --assume-yes is set. Never removes Docker itself (it may be used by other
# projects) - only Calagopus-owned artifacts.

if [ -n "${CALAGOPUS_LIB_UNINSTALL:-}" ]; then return 0; fi
CALAGOPUS_LIB_UNINSTALL=1

uninstall_confirm() {
	if [ "${CALAGOPUS_ASSUME_YES:-0}" -eq 1 ]; then return 0; fi
	ui_warn "This will remove the Calagopus Panel, Wings, and related config."
	ui_warn "Database data and backups can optionally be kept."
	ui_confirm "Proceed with uninstall?" "n" || { log_info "uninstall cancelled"; exit 0; }
}

# Remove a systemd unit (stop + disable + remove file).
_uninstall_remove_unit() {
	local svc="$1" unit="/etc/systemd/system/${1}.service"
	system_as_root systemctl stop "$svc" 2>/dev/null || true
	system_as_root systemctl disable "$svc" 2>/dev/null || true
	system_as_root rm -f "$unit"
	system_as_root systemctl daemon-reload 2>/dev/null || true
}

uninstall_run() {
	uninstall_confirm
	local drop_db keep_backups
	drop_db=0; keep_backups=1
	if config_is_installed DB && [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 1 ]; then
		ui_confirm "Also drop the database?" "n" && drop_db=1
		ui_confirm "Keep backup bundles?" "y" || keep_backups=0
	fi

	# Stop + remove services.
	_uninstall_remove_unit "$CALAGOPUS_PANEL_SERVICE"
	_uninstall_remove_unit "$CALAGOPUS_WINGS_SERVICE"
	_uninstall_remove_unit "calagopus-backup.timer"
	_uninstall_remove_unit "calagopus-backup.service"

	# Docker stacks down.
	docker_compose_down "$CALAGOPUS_PANEL_DIR"
	docker_compose_down "$CALAGOPUS_WINGS_DIR"

	# Remove binaries.
	system_as_root rm -f "$CALAGOPUS_PANEL_BIN" "$CALAGOPUS_WINGS_BIN" "$CALAGOPUS_CLI_BIN"

	# Remove install + config dirs.
	system_as_root rm -rf "$CALAGOPUS_PANEL_DIR" "$CALAGOPUS_WINGS_DIR"
	system_as_root rm -rf "$CALAGOPUS_ETC_DIR"
	system_as_root rm -rf "$CALAGOPUS_LIB_DIR"

	# Reverse proxy site.
	proxy_remove 2>/dev/null || true

	# Database (optional).
	if [ "$drop_db" = "1" ]; then
		db_local_psql "DROP DATABASE IF EXISTS ${CFG[DB_NAME]:-panel};" 2>/dev/null || true
		db_local_psql "DROP ROLE IF EXISTS ${CFG[DB_USER]:-calagopus};" 2>/dev/null || true
	fi

	# Backups.
	[ "$keep_backups" = "0" ] && system_as_root rm -rf "$CALAGOPUS_BACKUP_DIR"

	# Logs (keep for forensics by default).
	# system_as_root rm -rf "$CALAGOPUS_LOG_DIR"

	# Docker network (best-effort; ignore if in use by other containers).
	docker network rm "$CALAGOPUS_DOCKER_NETWORK" 2>/dev/null || true

	log_ok "Calagopus installation removed"
	log_info "Docker itself was left installed (it may be used by other projects)."
}
