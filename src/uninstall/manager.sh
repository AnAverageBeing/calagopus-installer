#!/usr/bin/env bash
#
# src/uninstall/manager.sh - Full clean removal of Calagopus Panel + Wings.
#
# Removes everything Calagopus-specific:
#   * Systemd services (panel, wings, backup timer)
#   * Docker containers + compose stacks + volumes + images
#   * Native binaries (calagopus-panel, wings)
#   * Installed CLI shim + state directory
#   * Configuration directory (/etc/calagopus, incl. .env, SSL certs)
#   * Application data directories (/var/lib/calagopus/panel, /var/lib/calagopus/wings)
#   * Reverse proxy configs (nginx sites, Caddyfile)
#   * SSL certificates (optionally - letsencrypt certs for this FQDN)
#   * Firewall rules (calagopus-specific)
#   * Log directory (optionally)
#   * Backup directory (optionally)
#   * Database + database user (optionally)
#
# Major dependencies (Docker, PostgreSQL, Redis, Nginx, Caddy) are LEFT
# INSTALLED because they may be used by other projects on the host.
#
# Every step asks for confirmation (unless --yes). The user can keep the
# database, backups, and logs if they want to reinstall later.

if [ -n "${CALAGOPUS_LIB_UNINSTALL:-}" ]; then return 0; fi
CALAGOPUS_LIB_UNINSTALL=1

# -----------------------------------------------------------------------------
# Confirmation + option gathering
# -----------------------------------------------------------------------------
uninstall_confirm() {
	if [ "${CALAGOPUS_ASSUME_YES:-0}" -eq 1 ]; then return 0; fi
	ui_warn "This will remove the Calagopus Panel, Wings, and all related files."
	ui_warn "Major dependencies (Docker, PostgreSQL, Nginx, etc.) will be left installed."
	printf '\n'
	ui_confirm "Proceed with uninstall?" "n" || { log_info "uninstall cancelled"; exit 0; }
}

# Ask what to keep vs remove. Sets the UNINSTALL_* flags.
uninstall_gather_options() {
	UNINSTALL_DROP_DB=0
	UNINSTALL_DROP_DB_USER=0
	UNINSTALL_REMOVE_SSL=0
	UNINSTALL_REMOVE_PROXY=1
	UNINSTALL_REMOVE_BACKUPS=0
	UNINSTALL_REMOVE_LOGS=0
	UNINSTALL_REMOVE_FW_RULES=1
	UNINSTALL_REMOVE_DOCKER_IMAGES=1

	if [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 0 ]; then
		# Non-interactive: use defaults (remove app files, keep DB + backups + logs).
		return 0
	fi
	if [ "${CALAGOPUS_ASSUME_YES:-0}" -eq 1 ]; then
		# --yes: full clean (drop everything except major deps).
		UNINSTALL_DROP_DB=1
		UNINSTALL_DROP_DB_USER=1
		UNINSTALL_REMOVE_SSL=1
		UNINSTALL_REMOVE_BACKUPS=1
		UNINSTALL_REMOVE_LOGS=1
		return 0
	fi

	printf '\n'
	ui_title "Uninstall Options"
	ui_confirm "Remove reverse proxy configs (nginx/caddy)?" "y" || UNINSTALL_REMOVE_PROXY=0
	if config_is_installed SSL; then
		ui_confirm "Remove SSL certificates for this installation?" "n" || UNINSTALL_REMOVE_SSL=0
	fi
	if config_is_installed DB; then
		ui_confirm "Drop the Calagopus database?" "n" && UNINSTALL_DROP_DB=1
		ui_confirm "Also drop the database user?" "n" && UNINSTALL_DROP_DB_USER=1
	fi
	if config_is_installed DOCKER; then
		ui_confirm "Remove Calagopus Docker images?" "y" || UNINSTALL_REMOVE_DOCKER_IMAGES=0
	fi
	ui_confirm "Remove backup bundles?" "n" && UNINSTALL_REMOVE_BACKUPS=1
	ui_confirm "Remove log files?" "n" && UNINSTALL_REMOVE_LOGS=1
	ui_confirm "Remove firewall rules created by the installer?" "y" || UNINSTALL_REMOVE_FW_RULES=0
}

# -----------------------------------------------------------------------------
# Individual cleanup steps
# -----------------------------------------------------------------------------

# Stop + disable + remove a systemd unit.
_uninstall_remove_unit() {
	local svc="$1" unit="/etc/systemd/system/${1}.service"
	system_as_root systemctl stop "$svc" 2>/dev/null || true
	system_as_root systemctl disable "$svc" 2>/dev/null || true
	system_as_root rm -f "$unit"
	system_as_root systemctl daemon-reload 2>/dev/null || true
	system_as_root systemctl reset-failed "$svc" 2>/dev/null || true
	log_debug "removed systemd unit: $svc"
}

# Stop + remove docker compose stacks + their volumes + images.
uninstall_docker_artifacts() {
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would remove docker containers/volumes/images"
		return 0
	fi

	# Panel compose stack.
	if [ -f "${CALAGOPUS_PANEL_DIR}/compose.yml" ]; then
		log_info "stopping + removing panel docker stack"
		( cd "$CALAGOPUS_PANEL_DIR" && docker compose down -v --remove-orphans ) 2>/dev/null || true
	fi

	# Wings compose stack.
	if [ -f "${CALAGOPUS_WINGS_DIR}/compose.yml" ]; then
		log_info "stopping + removing wings docker stack"
		( cd "$CALAGOPUS_WINGS_DIR" && docker compose down -v --remove-orphans ) 2>/dev/null || true
	fi

	# Remove Calagopus docker images.
	if [ "$UNINSTALL_REMOVE_DOCKER_IMAGES" = "1" ]; then
		docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
			| grep -iE 'calagopus|ghcr.io/calagopus' \
			| while read -r img; do
				log_debug "removing docker image: $img"
				docker rmi -f "$img" 2>/dev/null || true
			done
	fi

	# Remove the calagopus bridge network.
	docker network rm "$CALAGOPUS_DOCKER_NETWORK" 2>/dev/null || true

	# Clean up any dangling calagopus volumes.
	docker volume ls --format '{{.Name}}' 2>/dev/null \
		| grep -iE 'calagopus' \
		| while read -r vol; do
			docker volume rm "$vol" 2>/dev/null || true
		done
}

# Remove native binaries.
uninstall_native_binaries() {
	for bin in "$CALAGOPUS_PANEL_BIN" "$CALAGOPUS_WINGS_BIN" "$CALAGOPUS_CLI_BIN"; do
		if [ -f "$bin" ]; then
			log_debug "removing binary: $bin"
			system_as_root rm -f "$bin"
		fi
	done
}

# Remove application data directories.
uninstall_app_dirs() {
	for dir in "$CALAGOPUS_PANEL_DIR" "$CALAGOPUS_WINGS_DIR"; do
		if [ -d "$dir" ]; then
			log_debug "removing directory: $dir"
			system_as_root rm -rf "$dir"
		fi
	done
}

# Remove config directory (/etc/calagopus - env files, SSL certs, installer state).
uninstall_config_dir() {
	if [ -d "$CALAGOPUS_ETC_DIR" ]; then
		log_debug "removing config directory: $CALAGOPUS_ETC_DIR"
		system_as_root rm -rf "$CALAGOPUS_ETC_DIR"
	fi
}

# Remove the installer's own state directory + CLI shim files.
uninstall_installer_state() {
	if [ -d "$CALAGOPUS_LIB_DIR" ]; then
		log_debug "removing installer state: $CALAGOPUS_LIB_DIR"
		system_as_root rm -rf "$CALAGOPUS_LIB_DIR"
	fi
}

# Remove reverse proxy configs.
uninstall_reverse_proxy() {
	[ "$UNINSTALL_REMOVE_PROXY" = "1" ] || return 0

	# Nginx.
	local nginx_site="/etc/nginx/sites-available/calagopus.conf"
	local nginx_enabled="/etc/nginx/sites-enabled/calagopus.conf"
	if [ -f "$nginx_site" ] || [ -L "$nginx_enabled" ]; then
		log_info "removing nginx config"
		system_as_root rm -f "$nginx_site" "$nginx_enabled"
		system_as_root systemctl reload nginx 2>/dev/null || true
	fi

	# Caddy.
	if [ -f /etc/caddy/Caddyfile ]; then
		# Only remove if it looks like ours (check for calagopus or panel FQDN).
		if grep -qiE 'calagopus|'"${CFG[PANEL_FQDN]:-__nope__}" /etc/caddy/Caddyfile 2>/dev/null; then
			log_info "removing caddy config"
			config_backup_file /etc/caddy/Caddyfile >/dev/null 2>/dev/null || true
			system_as_root rm -f /etc/caddy/Caddyfile
			system_as_root systemctl restart caddy 2>/dev/null || true
		fi
	fi
}

# Remove SSL certificates.
uninstall_ssl() {
	[ "$UNINSTALL_REMOVE_SSL" = "1" ] || return 0
	local fqdn="${CFG[PANEL_FQDN]:-}"
	if [ -n "$fqdn" ] && [ -d "/etc/letsencrypt/live/${fqdn}" ]; then
		log_info "removing Let's Encrypt certificate for ${fqdn}"
		system_as_root certbot delete --cert-name "$fqdn" --non-interactive 2>/dev/null || true
	fi
	# Self-signed / cloudflare certs live in the config dir (removed by uninstall_config_dir).
}

# Drop database + user.
uninstall_database() {
	if [ "$UNINSTALL_DROP_DB" = "1" ]; then
		local db="${CFG[DB_NAME]:-panel}"
		log_info "dropping database: $db"
		db_local_psql "DROP DATABASE IF EXISTS ${db};" 2>/dev/null || true
	fi
	if [ "$UNINSTALL_DROP_DB_USER" = "1" ]; then
		local user="${CFG[DB_USER]:-calagopus}"
		log_info "dropping database user: $user"
		db_local_psql "DROP ROLE IF EXISTS ${user};" 2>/dev/null || true
	fi
}

# Remove firewall rules created by the installer.
uninstall_firewall() {
	[ "$UNINSTALL_REMOVE_FW_RULES" = "1" ] || return 0
	case "${CFG[FIREWALL_ENGINE]:-}" in
		ufw)
			# Remove calagopus-specific rules (best-effort).
			system_as_root ufw delete allow "${CFG[PANEL_PORT]:-8000}/tcp" 2>/dev/null || true
			system_as_root ufw delete allow "${CALAGOPUS_PORTS[panel_https]}/tcp" 2>/dev/null || true
			if [ "${CFG[INSTALL_TARGET]:-}" != "panel" ]; then
				system_as_root ufw delete allow "${CALAGOPUS_PORTS[wings]}/tcp" 2>/dev/null || true
			fi
			log_debug "removed ufw rules"
			;;
		firewalld)
			system_as_root firewall-cmd --permanent --remove-port="${CFG[PANEL_PORT]:-8000}/tcp" 2>/dev/null || true
			system_as_root firewall-cmd --permanent --remove-port="${CALAGOPUS_PORTS[panel_https]}/tcp" 2>/dev/null || true
			system_as_root firewall-cmd --reload 2>/dev/null || true
			log_debug "removed firewalld rules"
			;;
		*) log_debug "firewall rule cleanup skipped for ${CFG[FIREWALL_ENGINE]:-unknown}" ;;
	esac
}

# Remove backup bundles.
uninstall_backups() {
	[ "$UNINSTALL_REMOVE_BACKUPS" = "1" ] || return 0
	if [ -d "$CALAGOPUS_BACKUP_DIR" ]; then
		log_info "removing backup directory"
		system_as_root rm -rf "$CALAGOPUS_BACKUP_DIR"
	fi
}

# Remove logs.
uninstall_logs() {
	[ "$UNINSTALL_REMOVE_LOGS" = "1" ] || return 0
	if [ -d "$CALAGOPUS_LOG_DIR" ]; then
		log_info "removing log directory"
		system_as_root rm -rf "$CALAGOPUS_LOG_DIR"
	fi
}

# -----------------------------------------------------------------------------
# Main uninstall flow
# -----------------------------------------------------------------------------
uninstall_run() {
	uninstall_confirm
	uninstall_gather_options

	ui_title "Uninstalling Calagopus"
	ui_step_begin "Stopping + removing systemd services"
	_uninstall_remove_unit "$CALAGOPUS_PANEL_SERVICE"
	_uninstall_remove_unit "$CALAGOPUS_WINGS_SERVICE"
	_uninstall_remove_unit "calagopus-backup.timer"
	_uninstall_remove_unit "calagopus-backup.service"
	ui_step_end 0

	ui_step_begin "Removing Docker containers, volumes, and images"
	uninstall_docker_artifacts
	ui_step_end 0

	ui_step_begin "Removing native binaries"
	uninstall_native_binaries
	ui_step_end 0

	ui_step_begin "Removing application data directories"
	uninstall_app_dirs
	ui_step_end 0

	ui_step_begin "Removing reverse proxy configurations"
	uninstall_reverse_proxy
	ui_step_end 0

	ui_step_begin "Removing SSL certificates"
	uninstall_ssl
	ui_step_end 0

	ui_step_begin "Removing configuration directory"
	uninstall_config_dir
	ui_step_end 0

	ui_step_begin "Removing installer state"
	uninstall_installer_state
	ui_step_end 0

	ui_step_begin "Removing firewall rules"
	uninstall_firewall
	ui_step_end 0

	ui_step_begin "Dropping database (if selected)"
	uninstall_database
	ui_step_end 0

	ui_step_begin "Removing backup bundles (if selected)"
	uninstall_backups
	ui_step_end 0

	ui_step_begin "Removing log files (if selected)"
	uninstall_logs
	ui_step_end 0

	# Clear installed state.
	CFG[INSTALLED_PANEL]="no"
	CFG[INSTALLED_WINGS]="no"
	CFG[INSTALLED_DB]="no"
	CFG[INSTALLED_REDIS]="no"
	CFG[INSTALLED_DOCKER]="no"
	CFG[INSTALLED_PROXY]="no"
	CFG[INSTALLED_SSL]="no"
	CFG[INSTALLED_FIREWALL]="no"

	printf '\n'
	log_ok "Calagopus installation fully removed"
	log_info "Major dependencies (Docker, PostgreSQL, Redis, Nginx, Caddy) were left installed."
	log_info "You can remove them manually if no other project uses them."
}
