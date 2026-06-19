#!/usr/bin/env bash
#
# src/panel/install.sh - Calagopus Panel installation (docker + native paths).
#
# Two deployment modes, matching the upstream docs:
#
#   docker:
#     * AIO compose (panel + wings in one container) when target=full on a
#       single host, OR standalone compose when target=panel only.
#     * We fetch the upstream compose file, set the image tag for the chosen
#       release channel, inject APP_ENCRYPTION_KEY + DATABASE_URL + REDIS_URL,
#       and `docker compose up -d`.
#   native:
#     * Download the per-arch Rust binary to /usr/local/bin/calagopus-panel.
#     * Write /etc/calagopus/panel.env with the required vars.
#     * Provision Postgres + Valkey on the host (via db_provision + redis dep).
#     * Run `calagopus-panel service-install` to register the systemd unit.
#
# Idempotent: re-runs detect an existing install and upgrade/reconfigure rather
# than wiping data.

if [ -n "${CALAGOPUS_LIB_PANEL_INSTALL:-}" ]; then return 0; fi
CALAGOPUS_LIB_PANEL_INSTALL=1

# Determine whether the user wants the heavy (extension-capable) image variant.
panel_is_heavy() { common_is_yes "${CFG[VARIANT]:-}" || [ "${CFG[VARIANT]:-}" = "heavy" ]; }

# Are we doing AIO? Only when target=full and deploy=docker on a single host.
panel_is_aio() {
	[ "${CFG[INSTALL_TARGET]:-}" = "full" ] && [ "${CALAGOPUS_DEPLOY_MODE:-docker}" = "docker" ]
}

# Resolve the per-arch binary download URL for the chosen channel.
panel_binary_url() {
	local arch; arch="$(system_arch)"
	# Upstream releases are tagged panel-rs-<arch>-linux. Channels map to
	# /latest, /latest-pre, or a specific nightly tag. We use latest for stable.
	case "${CALAGOPUS_RELEASE_CHANNEL:-stable}" in
		stable)  printf '%s/panel-rs-%s-linux' "$CALAGOPUS_PANEL_RELEASES" "$arch" ;;
		beta)    printf 'https://github.com/calagopus/panel/releases/download/latest-pre/panel-rs-%s-linux' "$arch" ;;
		nightly) printf 'https://github.com/calagopus/panel/releases/download/nightly/panel-rs-%s-linux' "$arch" ;;
	esac
}

panel_installed() {
	[ -x "$CALAGOPUS_PANEL_BIN" ] || common_unit_exists "$CALAGOPUS_PANEL_SERVICE" \
		|| [ -f "${CALAGOPUS_PANEL_DIR}/compose.yml" ]
}
panel_version() {
	[ -x "$CALAGOPUS_PANEL_BIN" ] && "$CALAGOPUS_PANEL_BIN" version 2>/dev/null | head -1
}
panel_health() {
	common_unit_exists "$CALAGOPUS_PANEL_SERVICE" && systemctl is-active --quiet "$CALAGOPUS_PANEL_SERVICE" 2>/dev/null && return 0
	# docker mode: check the container is up.
	if [ -f "${CALAGOPUS_PANEL_DIR}/compose.yml" ]; then
		( cd "${CALAGOPUS_PANEL_DIR}" && docker compose ps --status=running 2>/dev/null | grep -q . )
	fi
}

# -----------------------------------------------------------------------------
# Gather user inputs that affect either deploy mode (FQDN, port, encryption key)
# -----------------------------------------------------------------------------
panel_gather() {
	# FQDN: needed for SSL/proxy; optional otherwise.
	if [ -z "${CFG[PANEL_FQDN]:-}" ] && [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 1 ]; then
		CFG[PANEL_FQDN]="$(ui_prompt_default "Panel FQDN (e.g. panel.example.com; blank to skip)" "")"
	fi
	CFG[PANEL_PORT]="${CFG[PANEL_PORT]:-${CALAGOPUS_PORTS[panel_http]}}"

	# Encryption key: generate if missing, never prompt for one (random is safer).
	if [ -z "${CFG[APP_ENCRYPTION_KEY]:-}" ]; then
		CFG[APP_ENCRYPTION_KEY]="$(crypto_encryption_key)"
		log_ok "generated APP_ENCRYPTION_KEY (stored in ${CALAGOPUS_CONFIG_FILE}, mode 0600)"
	fi
}

# -----------------------------------------------------------------------------
# Docker deployment
# -----------------------------------------------------------------------------
panel_install_docker() {
	panel_gather
	dep_provision docker
	docker_configure_daemon
	docker_ensure_network

	# In full-stack single-host mode we use the AIO image; otherwise standalone.
	local compose_key image heavy=0 aio=0
	if panel_is_aio; then
		compose_key="panel_aio"; aio=1
	else
		compose_key="panel_basic"
	fi
	panel_is_heavy && heavy=1
	image="$(docker_resolve_image panel "${CALAGOPUS_RELEASE_CHANNEL}" "$heavy" "$aio")"
	CFG[PANEL_IMAGE]="$image"

	log_info "deploying panel via docker (image: $image, compose: $compose_key)"
	system_as_root install -d -m0755 "$CALAGOPUS_PANEL_DIR"
	docker_fetch_compose "$CALAGOPUS_PANEL_DIR" "$compose_key"
	docker_set_compose_image "${CALAGOPUS_PANEL_DIR}/compose.yml" "web" "$image" 2>/dev/null \
		|| docker_set_compose_image "${CALAGOPUS_PANEL_DIR}/compose.yml" "panel" "$image"

	# For AIO we must pre-create wings-config.yml so the bind mount is a file.
	if panel_is_aio; then
		[ -f "${CALAGOPUS_PANEL_DIR}/wings-config.yml" ] \
			|| echo 'app_name: Calagopus' > "${CALAGOPUS_PANEL_DIR}/wings-config.yml"
	fi

	panel_write_env_file "${CALAGOPUS_PANEL_DIR}/.env"
	# Inject our env into the compose stack by exporting before `up`.
	set -a
	# shellcheck source=/dev/null
	. "${CALAGOPUS_PANEL_DIR}/.env"
	set +a
	docker_compose_up "$CALAGOPUS_PANEL_DIR"

	CFG[INSTALLED_PANEL_MODE]="docker"
	config_mark_installed PANEL
	log_ok "panel deployed at http://${CFG[PANEL_FQDN]:-localhost}:${CFG[PANEL_PORT]}"
}

# -----------------------------------------------------------------------------
# Native (binary) deployment
# -----------------------------------------------------------------------------
panel_install_native() {
	panel_gather
	# Native needs DB + cache on the host.
	db_provision
	dep_provision redis

	local url; url="$(panel_binary_url)"
	log_info "downloading panel binary: $url"
	system_as_root install -d -m0755 "$(dirname "$CALAGOPUS_PANEL_BIN")"
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would install binary to $CALAGOPUS_PANEL_BIN"
	else
		curl -fsSL "$url" -o /tmp/calagopus-panel
		system_as_root install -m0755 /tmp/calagopus-panel "$CALAGOPUS_PANEL_BIN"
		rm -f /tmp/calagopus-panel
	fi
	"$CALAGOPUS_PANEL_BIN" version >/dev/null 2>&1 || log_warn "panel binary present but 'version' failed"

	# Env file + config dir.
	system_as_root install -d -m0750 "$CALAGOPUS_ETC_DIR"
	panel_write_env_file "$CALAGOPUS_PANEL_ENV"
	system_as_root chmod 0640 "$CALAGOPUS_PANEL_ENV"

	# Register systemd service via the binary's own installer.
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would run: $CALAGOPUS_PANEL_BIN service-install"
	else
		set -a
		# shellcheck source=/dev/null
		. "$CALAGOPUS_PANEL_ENV"
		set +a
		"$CALAGOPUS_PANEL_BIN" service-install 2>&1 | tee -a "$CALAGOPUS_LOGFILE" >/dev/null || true
		system_as_root systemctl enable --now "$CALAGOPUS_PANEL_SERVICE" 2>/dev/null || true
	fi

	CFG[INSTALLED_PANEL_MODE]="native"
	config_mark_installed PANEL
	log_ok "panel installed (native) at http://localhost:${CFG[PANEL_PORT]}"
}

# -----------------------------------------------------------------------------
# Write the panel .env file from CFG + defaults. Uses the upstream template.
# -----------------------------------------------------------------------------
panel_write_env_file() {
	local target="$1"
	local tmpl="${CALAGOPUS_ROOT}/templates/env/panel.env.tmpl"
	[ -f "$tmpl" ] || tmpl="${CALAGOPUS_ROOT}/templates/env/panel.env.example"
	if [ -f "$target" ]; then
		config_backup_file "$target" >/dev/null
	fi
	# Render the template: simple KEY=VALUE substitution of ${VAR} tokens.
	local rendered
	rendered="$(CALAGOPUS_RENDER=1 env \
		APP_ENCRYPTION_KEY="${CFG[APP_ENCRYPTION_KEY]}" \
		DATABASE_URL="${CFG[DATABASE_URL]}" \
		REDIS_URL="${CFG[REDIS_URL]:-redis://localhost}" \
		BIND="${CFG[BIND]:-0.0.0.0}" \
		PORT="${CFG[PANEL_PORT]}" \
		APP_DEBUG="${CFG[APP_DEBUG]:-false}" \
		SERVER_NAME="${CFG[SERVER_NAME]:-}" \
		envsubst < "$tmpl" 2>/dev/null || cat "$tmpl")"
	system_as_root tee "$target" >/dev/null <<<"$rendered"
}

# -----------------------------------------------------------------------------
# Public entry: dispatch based on deploy mode.
# -----------------------------------------------------------------------------
panel_install() {
	case "${CALAGOPUS_DEPLOY_MODE:-docker}" in
		docker) panel_install_docker ;;
		native) panel_install_native ;;
		*) log_die "unknown deploy mode: ${CALAGOPUS_DEPLOY_MODE}" ;;
	esac
}

# Reconfigure: re-gather inputs + rewrite env + restart, without re-downloading.
panel_reconfigure() {
	panel_gather
	if [ "${CFG[INSTALLED_PANEL_MODE]:-}" = "native" ]; then
		panel_write_env_file "$CALAGOPUS_PANEL_ENV"
		system_as_root systemctl restart "$CALAGOPUS_PANEL_SERVICE" 2>/dev/null || true
	else
		panel_write_env_file "${CALAGOPUS_PANEL_DIR}/.env"
		( cd "${CALAGOPUS_PANEL_DIR}" && docker compose up -d --force-recreate ) 2>/dev/null || true
	fi
	log_ok "panel reconfigured"
}
