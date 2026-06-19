#!/usr/bin/env bash
#
# src/repair/manager.sh - Detect + fix common breakage without a full reinstall.
#
# Runs a battery of probes for the things that most often go wrong on a
# Calagopus host and fixes them in place. Each probe is independent so a
# failure in one area doesn't block repair of another. Designed to be safe to
# run repeatedly (idempotent) and to log every change it makes.

if [ -n "${CALAGOPUS_LIB_REPAIR:-}" ]; then return 0; fi
CALAGOPUS_LIB_REPAIR=1

repair_run_all() {
	log_info "running repair probes"
	local rc=0
	repair_missing_files     || rc=1
	repair_panel_service     || rc=1
	repair_wings_service     || rc=1
	repair_database          || rc=1
	repair_docker            || rc=1
	repair_permissions       || rc=1
	repair_ssl               || rc=1
	repair_proxy             || rc=1
	log_ok "repair pass complete (see log for any warnings)"
	return "$rc"
}

# 1. Missing files: re-fetch the panel/wings binary or compose file if absent.
repair_missing_files() {
	if config_is_installed PANEL; then
		if [ "${CFG[INSTALLED_PANEL_MODE]:-}" = "native" ] && [ ! -x "$CALAGOPUS_PANEL_BIN" ]; then
			log_warn "panel binary missing - re-downloading"
			local url; url="$(panel_binary_url)"
			curl -fsSL "$url" -o /tmp/calagopus-panel
			system_as_root install -m0755 /tmp/calagopus-panel "$CALAGOPUS_PANEL_BIN"
			rm -f /tmp/calagopus-panel
		fi
		if [ "${CFG[INSTALLED_PANEL_MODE]:-}" = "docker" ] && [ ! -f "${CALAGOPUS_PANEL_DIR}/compose.yml" ]; then
			log_warn "panel compose file missing - re-fetching"
			local key; { panel_is_aio && key="panel_aio"; } || key="panel_basic"
			docker_fetch_compose "$CALAGOPUS_PANEL_DIR" "$key"
		fi
	fi
	if config_is_installed WINGS && [ "${CFG[INSTALLED_WINGS_MODE]:-}" = "native" ] && [ ! -x "$CALAGOPUS_WINGS_BIN" ]; then
		log_warn "wings binary missing - re-downloading"
		local url; url="$(wings_binary_url)"
		curl -fsSL "$url" -o /tmp/wings
		system_as_root install -m0755 /tmp/wings "$CALAGOPUS_WINGS_BIN"
		rm -f /tmp/wings
	fi
}

# 2. Panel service: ensure the unit exists + is enabled + running.
repair_panel_service() {
	if ! config_is_installed PANEL; then return 0; fi
	if [ "${CFG[INSTALLED_PANEL_MODE]:-}" = "native" ]; then
		if ! common_unit_exists "$CALAGOPUS_PANEL_SERVICE"; then
			log_warn "panel service missing - re-registering"
			"$CALAGOPUS_PANEL_BIN" service-install 2>&1 | tee -a "$CALAGOPUS_LOGFILE" >/dev/null || true
		fi
		system_as_root systemctl enable "$CALAGOPUS_PANEL_SERVICE" 2>/dev/null || true
		system_as_root systemctl restart "$CALAGOPUS_PANEL_SERVICE" 2>/dev/null || true
	else
		( cd "$CALAGOPUS_PANEL_DIR" && docker compose up -d ) 2>/dev/null || true
	fi
}

# 3. Wings service.
repair_wings_service() {
	if ! config_is_installed WINGS; then return 0; fi
	if wings_is_aio_bundled; then return 0; fi
	if [ "${CFG[INSTALLED_WINGS_MODE]:-}" = "native" ]; then
		if ! common_unit_exists "$CALAGOPUS_WINGS_SERVICE"; then
			log_warn "wings service missing - re-registering"
			"$CALAGOPUS_WINGS_BIN" service-install 2>&1 | tee -a "$CALAGOPUS_LOGFILE" >/dev/null || true
		fi
		system_as_root systemctl enable "$CALAGOPUS_WINGS_SERVICE" 2>/dev/null || true
		system_as_root systemctl restart "$CALAGOPUS_WINGS_SERVICE" 2>/dev/null || true
	else
		( cd "$CALAGOPUS_WINGS_DIR" && docker compose up -d ) 2>/dev/null || true
	fi
}

# 4. Database: restart local postgres + verify connectivity.
repair_database() {
	if ! config_is_installed DB; then return 0; fi
	if [ "${CFG[DB_REMOTE]:-local}" != "remote" ]; then
		system_as_root systemctl restart postgresql 2>/dev/null \
			|| system_as_root systemctl restart postgresql-18 2>/dev/null || true
	fi
	if ! db_reachable; then
		log_warn "database still unreachable after restart"
	fi
}

# 5. Docker: restart daemon + recreate network if missing.
repair_docker() {
	if ! config_is_installed DOCKER; then return 0; fi
	if ! docker_health; then
		log_warn "docker daemon down - restarting"
		system_as_root systemctl restart docker
		sleep 2
	fi
	docker_ensure_network
}

# 6. Permissions: ensure config dir + env files have safe modes.
repair_permissions() {
	system_as_root chmod 0750 "$CALAGOPUS_ETC_DIR" 2>/dev/null || true
	system_as_root chmod 0640 "$CALAGOPUS_PANEL_ENV" 2>/dev/null || true
	system_as_root chmod 0640 "$CALAGOPUS_CONFIG_FILE" 2>/dev/null || true
	system_as_root chmod 0640 "$CALAGOPUS_STATE_FILE" 2>/dev/null || true
	if [ -f "${CALAGOPUS_PANEL_DIR}/.env" ]; then
		system_as_root chmod 0640 "${CALAGOPUS_PANEL_DIR}/.env" 2>/dev/null || true
	fi
}

# 7. SSL: re-validate; if expired + letsencrypt, attempt renewal.
repair_ssl() {
	if ! config_is_installed SSL; then return 0; fi
	if ! ssl_validate; then
		if [ "${CFG[SSL_PROVIDER]:-}" = "letsencrypt" ] && command -v certbot >/dev/null 2>&1; then
			log_warn "certificate expired - attempting renewal"
			system_as_root certbot renew 2>&1 | tee -a "$CALAGOPUS_LOGFILE" >/dev/null || true
			system_as_root systemctl reload nginx 2>/dev/null || true
		fi
	fi
}

# 8. Reverse proxy: reload + re-test config.
repair_proxy() {
	if ! config_is_installed PROXY; then return 0; fi
	case "${CFG[PROXY_ENGINE]:-nginx}" in
		nginx)
			if system_as_root nginx -t 2>/dev/null; then
				system_as_root systemctl reload nginx
			else
				log_warn "nginx config broken - re-running proxy_setup"
				proxy_setup_nginx
			fi
			;;
		caddy)
			system_as_root systemctl reload caddy 2>/dev/null || system_as_root systemctl restart caddy
			;;
	esac
}
