#!/usr/bin/env bash
#
# src/backup/manager.sh - Backup + restore for the whole Calagopus installation.
#
# A backup bundle is a tar.gz containing:
#   * db.sql.gz        - pg_dump of the panel database
#   * config/          - /etc/calagopus (env, installer config/state, ssl)
#   * panel/           - panel install dir (compose, volumes for docker mode)
#   * wings/           - wings install dir (compose, config)
#   * manifest.json    - what was backed up + versions + timestamp
#
# Restore validates the bundle, stops services, replaces files, restores the
# DB, and starts services again. Retention policy keeps the last N bundles.

if [ -n "${CALAGOPUS_LIB_BACKUP:-}" ]; then return 0; fi
CALAGOPUS_LIB_BACKUP=1

backup_dir() { printf '%s' "${CALAGOPUS_BACKUP_DIR}"; }

# Default retention: keep last 7 backups.
backup_retention() { printf '%s' "${CFG[BACKUP_RETENTION]:-7}"; }

# Create a timestamped bundle. Echoes its path.
backup_create() {
	system_as_root install -d -m0750 "$(backup_dir)"
	local ts; ts="$(date +%Y%m%d-%H%M%S)"
	local work; work="$(mktemp -d)"
	local bundle; bundle="$(backup_dir)/calagopus-${ts}.tar.gz"
	log_info "creating backup bundle -> $bundle"

	# 1. Database dump (only if DB is installed + reachable).
	if config_is_installed DB && db_reachable; then
		db_dump "${work}/db.sql.gz" >/dev/null || log_warn "db dump failed (continuing)"
	else
		log_debug "DB not installed/unreachable - skipping db dump"
	fi

	# 2. Config tree.
	if [ -d "$CALAGOPUS_ETC_DIR" ]; then
		system_as_root cp -a "$CALAGOPUS_ETC_DIR" "${work}/config"
	fi

	# 3. Panel + wings dirs.
	if [ -d "$CALAGOPUS_PANEL_DIR" ]; then system_as_root cp -a "$CALAGOPUS_PANEL_DIR" "${work}/panel"; fi
	if [ -d "$CALAGOPUS_WINGS_DIR" ]; then system_as_root cp -a "$CALAGOPUS_WINGS_DIR" "${work}/wings"; fi

	# 4. Manifest (no secrets - APP_ENCRYPTION_KEY etc. live inside the config
	#    copy which is already 0600; the manifest itself records versions only).
	cat > "${work}/manifest.json" <<EOF
{
	"timestamp": "${ts}",
	"installer_version": "${CALAGOPUS_INSTALLER_VERSION}",
	"panel_version": "$(panel_version 2>/dev/null || echo unknown)",
	"wings_version": "$(wings_version 2>/dev/null || echo unknown)",
	"panel_mode": "${CFG[INSTALLED_PANEL_MODE]:-}",
	"wings_mode": "${CFG[INSTALLED_WINGS_MODE]:-}",
	"deploy_mode": "${CFG[DEPLOY_MODE]:-}",
	"channel": "${CFG[RELEASE_CHANNEL]:-}"
}
EOF

	# 5. Tar it up.
	tar -czf "$bundle" -C "$work" . 2>/dev/null
	chmod 0600 "$bundle"
	rm -rf "$work"
	backup_prune
	log_ok "backup created: $bundle"
	printf '%s' "$bundle"
}

# Remove old bundles beyond retention count.
backup_prune() {
	local keep; keep="$(backup_retention)"
	local n=0 f
	while IFS= read -r f; do
		n=$((n+1))
		if [ "$n" -gt "$keep" ]; then
			log_debug "pruning old backup: $f"
			rm -f "$f"
		fi
	done < <(find "$(backup_dir)" -name 'calagopus-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
}

# Restore from a bundle. Stops services, replaces files, restores DB, restarts.
backup_restore() {
	local bundle="${1:-}"
	if [ -z "$bundle" ]; then
		bundle="$(ui_prompt_default "Path to backup bundle" "$(find "$(backup_dir)" -name 'calagopus-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)}")"
	fi
	[ -f "$bundle" ] || { log_error "bundle not found: $bundle"; return 1; }

	log_info "restoring from $bundle"
	local work; work="$(mktemp -d)"
	tar -xzf "$bundle" -C "$work"

	# Stop services first.
	backup_stop_services

	# Restore config tree.
	if [ -d "${work}/config" ]; then
		system_as_root rm -rf "$CALAGOPUS_ETC_DIR"
		system_as_root cp -a "${work}/config" "$CALAGOPUS_ETC_DIR"
		system_as_root chmod 0750 "$CALAGOPUS_ETC_DIR"
	fi

	# Reload installer state from the restored config.
	config_load

	# Restore panel + wings dirs.
	if [ -d "${work}/panel" ]; then { system_as_root rm -rf "$CALAGOPUS_PANEL_DIR"; system_as_root cp -a "${work}/panel" "$CALAGOPUS_PANEL_DIR"; } fi
	if [ -d "${work}/wings" ]; then { system_as_root rm -rf "$CALAGOPUS_WINGS_DIR"; system_as_root cp -a "${work}/wings" "$CALAGOPUS_WINGS_DIR"; } fi

	# Restore database.
	if [ -f "${work}/db.sql.gz" ] && config_is_installed DB; then
		db_restore "${work}/db.sql.gz" || log_warn "db restore had errors"
	fi

	# Start services.
	backup_start_services
	rm -rf "$work"
	log_ok "restore complete"
}

backup_stop_services() {
	system_as_root systemctl stop "$CALAGOPUS_PANEL_SERVICE" 2>/dev/null || true
	system_as_root systemctl stop "$CALAGOPUS_WINGS_SERVICE" 2>/dev/null || true
	if [ -f "${CALAGOPUS_PANEL_DIR}/compose.yml" ]; then docker_compose_down "$CALAGOPUS_PANEL_DIR"; fi
	if [ -f "${CALAGOPUS_WINGS_DIR}/compose.yml" ]; then docker_compose_down "$CALAGOPUS_WINGS_DIR"; fi
}

backup_start_services() {
	if [ "${CFG[INSTALLED_PANEL_MODE]:-}" = "native" ]; then
		system_as_root systemctl start "$CALAGOPUS_PANEL_SERVICE" 2>/dev/null || true
	else
	if [ -f "${CALAGOPUS_PANEL_DIR}/compose.yml" ]; then docker_compose_up "$CALAGOPUS_PANEL_DIR"; fi
	fi
	if [ "${CFG[INSTALLED_WINGS_MODE]:-}" = "native" ]; then
		system_as_root systemctl start "$CALAGOPUS_WINGS_SERVICE" 2>/dev/null || true
	else
	if [ -f "${CALAGOPUS_WINGS_DIR}/compose.yml" ]; then docker_compose_up "$CALAGOPUS_WINGS_DIR"; fi
	fi
}

# Install a systemd timer for periodic backups (schedule from config).
backup_install_schedule() {
	local schedule="${CFG[BACKUP_SCHEDULE]:-daily}"
	local oncalendar
	case "$schedule" in
		hourly)  oncalendar="hourly" ;;
		daily)   oncalendar="daily" ;;
		weekly)  oncalendar="weekly" ;;
		monthly) oncalendar="monthly" ;;
		*) oncalendar="daily" ;;
	esac
	system_as_root tee "/etc/systemd/system/calagopus-backup.timer" >/dev/null <<EOF
[Unit]
Description=Calagopus periodic backup

[Timer]
OnCalendar=${oncalendar}
Persistent=true

[Install]
WantedBy=timers.target
EOF
	system_as_root tee "/etc/systemd/system/calagopus-backup.service" >/dev/null <<EOF
[Unit]
Description=Calagopus backup
After=docker.service

[Service]
Type=oneshot
ExecStart=${CALAGOPUS_CLI_BIN} backup
EOF
	system_as_root systemctl daemon-reload
	system_as_root systemctl enable --now calagopus-backup.timer
	log_ok "backup schedule installed: ${oncalendar}"
}
