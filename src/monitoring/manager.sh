#!/usr/bin/env bash
#
# src/monitoring/manager.sh - status / doctor / logs commands.
#
# These are the read-only commands the installed `calagopus-installer` CLI
# exposes so operators can check on their installation without re-running the
# full installer. Each is also callable directly from the main installer.sh
# via `--action status|doctor|logs`.

if [ -n "${CALAGOPUS_LIB_MONITORING:-}" ]; then return 0; fi
CALAGOPUS_LIB_MONITORING=1

# Pretty "service is active/inactive" string.
_mon_svc_label() {
	if systemctl is-active --quiet "$1" 2>/dev/null; then printf '%sactive%s' "$C_GREEN" "$C_RESET"
	else printf '%sinactive%s' "$C_RED" "$C_RESET"; fi
}

# Health wrappers for engines that don't have a dedicated *_health function.
_mon_proxy_health() { systemctl is-active --quiet "${CFG[PROXY_ENGINE]:-nginx}" 2>/dev/null; }
_mon_fw_health()    { systemctl is-active --quiet "${CFG[FIREWALL_ENGINE]:-ufw}" 2>/dev/null; }

# Show an at-a-glance status table.
monitoring_status() {
	ui_title "Calagopus System Status"
	printf 'Installer:     %s v%s\n' "$(ui_brand 'Calagopus Installer')" "$CALAGOPUS_INSTALLER_VERSION"
	printf 'Host:          %s %s (%s)\n' "${OS_PRETTY:-?}" "${OS_VERSION_ID:-}" "$(system_arch)"
	printf 'Deploy mode:   %s  |  Channel: %s\n' "${CFG[DEPLOY_MODE]:-?}" "${CFG[RELEASE_CHANNEL]:-?}"
	printf 'Installed at:  %s\n' "${CFG[INSTALLED_AT]:-not recorded}"
	printf '\n'

	_mon_row "Panel"      config_is_installed PANEL     panel_health
	_mon_row "Wings"      config_is_installed WINGS     wings_health
	_mon_row "Database"   config_is_installed DB        db_reachable
	_mon_row "Redis"      config_is_installed REDIS     redis_health
	_mon_row "Docker"     config_is_installed DOCKER    docker_health
	_mon_row "Reverse proxy" config_is_installed PROXY  _mon_proxy_health
	_mon_row "SSL"        config_is_installed SSL       ssl_validate
	_mon_row "Firewall"   config_is_installed FIREWALL  _mon_fw_health

	printf '\n'
	printf 'Versions:\n'
	printf '  panel: %s\n' "$(panel_version 2>/dev/null   || echo n/a)"
	printf '  wings: %s\n' "$(wings_version 2>/dev/null   || echo n/a)"
	printf '  docker: %s\n' "$(docker_version 2>/dev/null || echo n/a)"
	printf '  postgres: %s\n' "$(postgres_version 2>/dev/null || echo n/a)"

	# SSL expiry.
	if config_is_installed SSL; then
		local days; days="$(ssl_days_until_expiry)"
		if [ "${days:-0}" -ge 0 ]; then
			printf '  ssl cert expires in: %s days\n' "$days"
		fi
	fi

	# Resource usage snapshot.
	printf '\nResources:\n'
	printf '  RAM: %s MiB  |  Disk free: %s MiB\n' "$(system_ram_mib)" "$(system_free_mib "$CALAGOPUS_INSTALL_DIR")"
}

# Print one installed/healthy row. Args: label  is_installed_fn  health_fn
_mon_row() {
	local label="$1" installed_fn="$2" health_fn="$3"
	local inst health
	if "$installed_fn"; then inst="${C_GREEN}installed${C_RESET}"; else inst="${C_GREY}not installed${C_RESET}"; fi
	if "$health_fn" 2>/dev/null; then health="${C_GREEN}healthy${C_RESET}"; else health="${C_YELLOW}?${C_RESET}"; fi
	printf '  %-16s %-18s %s\n' "$label" "$inst" "$health"
}

# Deep health check - exit non-zero if anything critical is broken.
monitoring_doctor() {
	ui_title "Calagopus Doctor"
	local rc=0
	system_preflight || rc=1
	if config_is_installed PANEL    && ! panel_health;    then log_error "panel unhealthy";        rc=1; fi
	if config_is_installed WINGS    && ! wings_health;    then log_error "wings unhealthy";        rc=1; fi
	if config_is_installed DB       && ! db_reachable;    then log_error "database unreachable";   rc=1; fi
	if config_is_installed DOCKER   && ! docker_health;   then log_error "docker daemon down";     rc=1; fi
	if config_is_installed SSL      && ! ssl_validate;    then log_warn  "SSL cert issue";          fi
	if config_is_installed PROXY; then
		case "${CFG[PROXY_ENGINE]:-nginx}" in
			nginx) system_as_root nginx -t 2>/dev/null || { log_error "nginx config invalid"; rc=1; } ;;
			caddy) caddy validate --config /etc/caddy/Caddyfile 2>/dev/null || { log_warn "caddy config issue"; } ;;
		esac
	fi
	if [ "$rc" -eq 0 ]; then log_ok "all checks passed"; else log_error "doctor found issues (see above)"; fi
	return "$rc"
}

# Tail the installer log.
monitoring_logs() {
	local n="${1:-50}"
	if [ -n "${CALAGOPUS_FOLLOW:-}" ]; then
		tail -n "$n" -f "$CALAGOPUS_LOGFILE" 2>/dev/null || log_error "log file not found"
	else
		tail -n "$n" "$CALAGOPUS_LOGFILE" 2>/dev/null || log_error "log file not found"
	fi
}
