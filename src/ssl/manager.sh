#!/usr/bin/env bash
#
# src/ssl/manager.sh - SSL/TLS certificate provisioning for the panel.
#
# Supports the four modes Calagopus users typically want:
#   1. letsencrypt  - certbot + webroot (requires a resolvable FQDN + 80/443)
#   2. selfsigned   - openssl-generated, for homelabs / testing
#   3. existing     - operator supplies paths to fullchain + privkey
#   4. cloudflare   - Cloudflare Origin Certificate (operator pastes it in)
#
# All modes normalise the result into:
#   CFG[SSL_CERT] -> path to fullchain.pem
#   CFG[SSL_KEY]  -> path to privkey.pem
# so the reverse-proxy module has a single contract. Renewal monitoring is set
# up for the letsencrypt path; the others are static.

if [ -n "${CALAGOPUS_LIB_SSL_MANAGER:-}" ]; then return 0; fi
CALAGOPUS_LIB_SSL_MANAGER=1

SSL_LE_DIR="/etc/letsencrypt/live"
SSL_LOCAL_DIR="${CALAGOPUS_ETC_DIR}/ssl"

ssl_choose_provider() {
	if [ -n "${CFG[SSL_PROVIDER]:-}" ]; then return 0; fi
	local pick
	pick="$(ui_choice "How would you like to handle SSL?" \
		"Let's Encrypt (recommended)|Self-signed|Existing certificates|Cloudflare Origin Certificate" \
		"${CFG[SSL_PROVIDER]:-1}")"
	case "$pick" in
		Let\'s*)   CFG[SSL_PROVIDER]="letsencrypt" ;;
		Self*)     CFG[SSL_PROVIDER]="selfsigned" ;;
		Existing*) CFG[SSL_PROVIDER]="existing" ;;
		Cloudflare*) CFG[SSL_PROVIDER]="cloudflare" ;;
	esac
}

ssl_dir_ensure() { system_as_root install -d -m0750 "$SSL_LOCAL_DIR"; }

# ----------------------------------------------------------------------------
# Let's Encrypt
# ----------------------------------------------------------------------------
ssl_provision_letsencrypt() {
	dep_provision certbot
	local fqdn="${CFG[PANEL_FQDN]:-}"
	[ -n "$fqdn" ] || { log_error "Let's Encrypt requires PANEL_FQDN"; return 1; }
	local webroot="/var/www/letsencrypt"
	system_as_root install -d -m0755 "$webroot"

	if [ -d "${SSL_LE_DIR}/${fqdn}" ]; then
		log_ok "certificate for ${fqdn} already exists"
	else
		log_info "requesting Let's Encrypt certificate for ${fqdn}"
		system_as_root certbot certonly --webroot -w "$webroot" \
			-d "$fqdn" --non-interactive --agree-tos --register-unsafely-without-email \
			--keep-until-expiring 2>&1 | tee -a "$CALAGOPUS_LOGFILE" >/dev/null \
			|| { log_error "certbot failed for ${fqdn}"; return 1; }
	fi
	CFG[SSL_CERT]="${SSL_LE_DIR}/${fqdn}/fullchain.pem"
	CFG[SSL_KEY]="${SSL_LE_DIR}/${fqdn}/privkey.pem"
	ssl_install_renew_hook
}

# Install a post-renew hook so nginx/caddy reload after certbot renews.
ssl_install_renew_hook() {
	local hook="/etc/letsencrypt/renewal-hooks/deploy/calagopus-reload.sh"
	system_as_root install -d -m0755 "$(dirname "$hook")"
	system_as_root tee "$hook" >/dev/null <<'EOF'
#!/usr/bin/env bash
# Reload reverse proxy after cert renewal. Calagopus Installer.
systemctl reload nginx 2>/dev/null || true
systemctl reload caddy 2>/dev/null || true
EOF
	system_as_root chmod +x "$hook"
}

# ----------------------------------------------------------------------------
# Self-signed
# ----------------------------------------------------------------------------
ssl_provision_selfsigned() {
	local fqdn="${CFG[PANEL_FQDN]:-localhost}"
	ssl_dir_ensure
	local cert="${SSL_LOCAL_DIR}/${fqdn}.crt"
	local key="${SSL_LOCAL_DIR}/${fqdn}.key"
	if [ -f "$cert" ] && [ -f "$key" ]; then
		log_debug "self-signed cert for ${fqdn} already present"
	else
		log_info "generating self-signed certificate for ${fqdn}"
		system_as_root openssl req -x509 -nodes -days 365 \
			-newkey rsa:2048 -keyout "$key" -out "$cert" \
			-subj "/CN=${fqdn}" 2>/dev/null
		system_as_root chmod 0600 "$key"
		system_as_root chmod 0644 "$cert"
	fi
	CFG[SSL_CERT]="$cert"; CFG[SSL_KEY]="$key"
}

# ----------------------------------------------------------------------------
# Existing certificates (operator supplies paths)
# ----------------------------------------------------------------------------
ssl_provision_existing() {
	local cert key
	cert="$(ui_prompt_default "Path to fullchain.pem" "${CFG[SSL_CERT]:-}")"
	key="$(ui_prompt_default "Path to privkey.pem"   "${CFG[SSL_KEY]:-}")"
	[ -f "$cert" ] || { log_error "certificate not found: $cert"; return 1; }
	[ -f "$key" ]  || { log_error "private key not found: $key"; return 1; }
	CFG[SSL_CERT]="$cert"; CFG[SSL_KEY]="$key"
	log_ok "using existing certificate at $cert"
}

# ----------------------------------------------------------------------------
# Cloudflare Origin Certificate
# ----------------------------------------------------------------------------
ssl_provision_cloudflare() {
	ssl_dir_ensure
	local fqdn="${CFG[PANEL_FQDN]:-}"
	local cert="${SSL_LOCAL_DIR}/${fqdn}.origin.crt"
	local key="${SSL_LOCAL_DIR}/${fqdn}.origin.key"
	if [ ! -f "$cert" ]; then
		log_info "Paste your Cloudflare Origin Certificate (end with a blank line):"
		local line body=""
		while IFS= read -r line && [ -n "$line" ]; do body+="${line}\n"; done
		printf '%b' "$body" | system_as_root tee "$cert" >/dev/null
	fi
	if [ ! -f "$key" ]; then
		log_info "Paste your Cloudflare Origin Private Key (end with a blank line):"
		local line body=""
		while IFS= read -r line && [ -n "$line" ]; do body+="${line}\n"; done
		printf '%b' "$body" | system_as_root tee "$key" >/dev/null
		system_as_root chmod 0600 "$key"
	fi
	CFG[SSL_CERT]="$cert"; CFG[SSL_KEY]="$key"
}

# ----------------------------------------------------------------------------
# Public entry
# ----------------------------------------------------------------------------
ssl_provision() {
	ssl_choose_provider
	case "${CFG[SSL_PROVIDER]:-letsencrypt}" in
		letsencrypt) ssl_provision_letsencrypt ;;
		selfsigned)  ssl_provision_selfsigned ;;
		existing)    ssl_provision_existing ;;
		cloudflare)  ssl_provision_cloudflare ;;
		none)        log_info "SSL disabled (plain HTTP)"; return 0 ;;
		*) log_error "unknown SSL provider: ${CFG[SSL_PROVIDER]}"; return 1 ;;
	esac
	ssl_validate
	config_mark_installed SSL
}

# Validate that the cert + key exist and the cert is not expired.
ssl_validate() {
	[ -f "${CFG[SSL_CERT]:-}" ] || { log_warn "SSL cert path missing"; return 1; }
	[ -f "${CFG[SSL_KEY]:-}" ]  || { log_warn "SSL key path missing";  return 1; }
	if command -v openssl >/dev/null 2>&1; then
		local end
		end="$(openssl x509 -enddate -noout -in "${CFG[SSL_CERT]}" 2>/dev/null | cut -d= -f2)"
		if [ -n "$end" ]; then
			local end_ts now_ts
			end_ts="$(date -d "$end" +%s 2>/dev/null || echo 0)"
			now_ts="$(date +%s)"
			if [ "$end_ts" -gt 0 ] && [ "$end_ts" -lt "$now_ts" ]; then
				log_warn "certificate expired on $end"
				return 1
			fi
			log_ok "certificate valid until $end"
		fi
	fi
	return 0
}

# Echo days-until-expiry (used by monitoring/doctor).
ssl_days_until_expiry() {
	local end
	end="$(openssl x509 -enddate -noout -in "${CFG[SSL_CERT]:-}" 2>/dev/null | cut -d= -f2)"
	[ -n "$end" ] || { echo -1; return; }
	local end_ts now_ts
	end_ts="$(date -d "$end" +%s 2>/dev/null || echo 0)"
	now_ts="$(date +%s)"
	echo $(( (end_ts - now_ts) / 86400 ))
}
