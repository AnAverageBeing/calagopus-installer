#!/usr/bin/env bash
#
# src/proxy/manager.sh - Reverse proxy configuration (Nginx or Caddy).
#
# Generates a site config for the chosen engine that:
#   * terminates TLS (using cert/key paths from ssl/manager.sh),
#   * proxies to the panel on its BIND/PORT,
#   * upgrades WebSocket connections (needed for the panel's live UI),
#   * adds a basic set of security headers,
#   * trusts the panel's APP_TRUSTED_PROXIES so the panel sees real client IPs.
#
# Idempotent: existing site files are backed up before being overwritten.

if [ -n "${CALAGOPUS_LIB_PROXY_MANAGER:-}" ]; then return 0; fi
CALAGOPUS_LIB_PROXY_MANAGER=1

proxy_choose_engine() {
	if [ -n "${CFG[PROXY_ENGINE]:-}" ]; then return 0; fi
	local pick
	pick="$(ui_choice "Which reverse proxy?" "Nginx (recommended)|Caddy" "${CFG[PROXY_ENGINE]:-1}")"
	case "$pick" in
		Nginx*) CFG[PROXY_ENGINE]="nginx" ;;
		Caddy*) CFG[PROXY_ENGINE]="caddy" ;;
	esac
}

# The upstream panel address the proxy forwards to.
proxy_upstream() {
	local host="${CFG[BIND]:-127.0.0.1}"
	local port="${CFG[PANEL_PORT]:-${CALAGOPUS_PORTS[panel_http]}}"
	printf '%s:%s' "$host" "$port"
}

# ----------------------------------------------------------------------------
# Nginx
# ----------------------------------------------------------------------------
proxy_setup_nginx() {
	dep_provision nginx
	local tmpl="${CALAGOPUS_ROOT}/templates/nginx/panel.conf.tmpl"
	local site="/etc/nginx/sites-available/calagopus.conf"
	local enabled="/etc/nginx/sites-enabled/calagopus.conf"
	system_as_root install -d -m0755 /etc/nginx/sites-available /etc/nginx/sites-enabled

	local fqdn="${CFG[PANEL_FQDN]:-_}"
	local rendered
	rendered="$(PANEL_FQDN="$fqdn" \
		SSL_CERT="${CFG[SSL_CERT]:-}" SSL_KEY="${CFG[SSL_KEY]:-}" \
		UPSTREAM="$(proxy_upstream)" \
		envsubst < "$tmpl")"
	[ -f "$site" ] && config_backup_file "$site" >/dev/null
	system_as_root tee "$site" >/dev/null <<<"$rendered"
	system_as_root ln -sf "$site" "$enabled"
	# Remove the default site if present (so ours takes precedence).
	system_as_root rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
	if system_as_root nginx -t 2>/dev/null; then
		system_as_root systemctl reload nginx
		log_ok "nginx configured for ${fqdn}"
	else
		log_error "nginx config test failed - check $site"
		return 1
	fi
}

# ----------------------------------------------------------------------------
# Caddy
# ----------------------------------------------------------------------------
proxy_setup_caddy() {
	dep_provision caddy
	local tmpl="${CALAGOPUS_ROOT}/templates/caddy/Caddyfile.tmpl"
	local caddyfile="/etc/caddy/Caddyfile"
	local fqdn="${CFG[PANEL_FQDN]:-}"
	[ -n "$fqdn" ] || { log_error "Caddy auto-HTTPS needs a FQDN"; return 1; }

	local rendered
	rendered="$(PANEL_FQDN="$fqdn" \
		SSL_CERT="${CFG[SSL_CERT]:-}" SSL_KEY="${CFG[SSL_KEY]:-}" \
		UPSTREAM="$(proxy_upstream)" \
		envsubst < "$tmpl")"
	[ -f "$caddyfile" ] && config_backup_file "$caddyfile" >/dev/null
	system_as_root tee "$caddyfile" >/dev/null <<<"$rendered"
	system_as_root systemctl reload caddy 2>/dev/null \
		|| system_as_root systemctl restart caddy
	log_ok "caddy configured for ${fqdn}"
}

# ----------------------------------------------------------------------------
# Public entry
# ----------------------------------------------------------------------------
proxy_setup() {
	proxy_choose_engine
	case "${CFG[PROXY_ENGINE]:-nginx}" in
		nginx) proxy_setup_nginx ;;
		caddy) proxy_setup_caddy ;;
		none)  log_info "reverse proxy skipped"; return 0 ;;
		*) log_error "unknown proxy engine"; return 1 ;;
	esac
	config_mark_installed PROXY
}

proxy_remove() {
	case "${CFG[PROXY_ENGINE]:-nginx}" in
		nginx)
			system_as_root rm -f /etc/nginx/sites-enabled/calagopus.conf /etc/nginx/sites-available/calagopus.conf
			system_as_root systemctl reload nginx 2>/dev/null || true
			;;
		caddy)
			system_as_root rm -f /etc/caddy/Caddyfile
			system_as_root systemctl stop caddy 2>/dev/null || true
			;;
	esac
	config_mark_uninstalled PROXY
}
