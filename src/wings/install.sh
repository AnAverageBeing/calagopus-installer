#!/usr/bin/env bash
#
# src/wings/install.sh - Calagopus Wings installation (docker + native paths).
#
# Wings is the daemon that actually runs game servers; it needs Docker (or
# Podman) on the host. Like the panel, two deploy modes:
#
#   docker:
#     * Fetch compose.local.yml from the wings repo, set the image tag, create
#       config/config.yml (operator pastes node config from the panel), and
#       `docker compose up -d`.
#   native:
#     * Download the per-arch wings binary, run `wings configure --join-data`
#       with the token from the panel, then `wings service-install`.
#
# In a full-stack (AIO) docker install, Wings is bundled into the panel
# container and this module is a no-op (detected via panel_is_aio).

if [ -n "${CALAGOPUS_LIB_WINGS_INSTALL:-}" ]; then return 0; fi
CALAGOPUS_LIB_WINGS_INSTALL=1

# In AIO mode wings is already in the panel container.
wings_is_aio_bundled() {
	if [ "${CFG[INSTALLED_PANEL_MODE]:-}" = "docker" ] && [ "${CFG[INSTALL_TARGET]:-}" = "full" ]; then return 0; else return 1; fi
}

wings_binary_url() {
	local arch; arch="$(system_arch)"
	case "${CALAGOPUS_RELEASE_CHANNEL:-stable}" in
		stable)  printf '%s/wings-rs-%s-linux' "$CALAGOPUS_WINGS_RELEASES" "$arch" ;;
		beta)    printf 'https://github.com/calagopus/wings/releases/download/latest-pre/wings-rs-%s-linux' "$arch" ;;
		nightly) printf 'https://github.com/calagopus/wings/releases/download/nightly/wings-rs-%s-linux' "$arch" ;;
	esac
}

wings_installed() {
	[ -x "$CALAGOPUS_WINGS_BIN" ] || common_unit_exists "$CALAGOPUS_WINGS_SERVICE" \
		|| [ -f "${CALAGOPUS_WINGS_DIR}/compose.yml" ]
}
wings_version() { [ -x "$CALAGOPUS_WINGS_BIN" ] && "$CALAGOPUS_WINGS_BIN" version 2>/dev/null | head -1; }
wings_health() {
	if common_unit_exists "$CALAGOPUS_WINGS_SERVICE" && systemctl is-active --quiet "$CALAGOPUS_WINGS_SERVICE" 2>/dev/null; then return 0; fi
	if [ -f "${CALAGOPUS_WINGS_DIR}/compose.yml" ]; then
		( cd "${CALAGOPUS_WINGS_DIR}" && docker compose ps --status=running 2>/dev/null | grep -q . )
	fi
}

# -----------------------------------------------------------------------------
# Gather node join data + optional FQDN. The join token comes from the panel's
# "Add Node" page; we prompt for it (or accept --wings-join-data non-interactively).
# -----------------------------------------------------------------------------
wings_gather() {
	if [ -z "${CFG[WINGS_JOIN_DATA]:-}" ] && [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 1 ]; then
		log_info "Wings needs its node config from the panel's 'Add Node' page."
		CFG[WINGS_JOIN_DATA]="$(ui_prompt "Paste the wings join-data / auto-deploy string (or blank to configure later)")"
	fi
	if [ -z "${CFG[WINGS_FQDN]:-}" ] && [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 1 ]; then
		CFG[WINGS_FQDN]="$(ui_prompt_default "Wings FQDN (for SSL/proxy; blank to skip)" "")"
	fi
	CFG[WINGS_PORT]="${CFG[WINGS_PORT]:-${CALAGOPUS_PORTS[wings]}}"
}

# Write config/config.yml for the docker compose stack. If we have join-data
# we let `wings configure` produce the real config; otherwise we write a stub.
wings_write_config() {
	local cfgdir="${CALAGOPUS_WINGS_DIR}/config"
	system_as_root install -d -m0750 "$cfgdir"
	if [ -n "${CFG[WINGS_JOIN_DATA]:-}" ] && [ -x "$CALAGOPUS_WINGS_BIN" ]; then
		"$CALAGOPUS_WINGS_BIN" configure --join-data "${CFG[WINGS_JOIN_DATA]}" \
			--config "${cfgdir}/config.yml" 2>&1 | tee -a "$CALAGOPUS_LOGFILE" >/dev/null || true
	elif [ ! -f "${cfgdir}/config.yml" ]; then
		cat > "${cfgdir}/config.yml" <<'EOF'
# Calagopus Wings configuration
# Populate this from the panel's "Add Node" page, then restart wings.
app_name: Calagopus
EOF
	fi
}

# -----------------------------------------------------------------------------
# Docker deployment
# -----------------------------------------------------------------------------
wings_install_docker() {
	if wings_is_aio_bundled; then { log_ok "wings is bundled in the AIO panel container; nothing to do"; return 0; } fi
	dep_provision docker
	docker_configure_daemon
	docker_ensure_network

	local image; image="$(docker_resolve_image wings "${CALAGOPUS_RELEASE_CHANNEL}")"
	CFG[WINGS_IMAGE]="$image"
	log_info "deploying wings via docker (image: $image)"
	system_as_root install -d -m0755 "$CALAGOPUS_WINGS_DIR"
	docker_fetch_compose "$CALAGOPUS_WINGS_DIR" "wings_local" "$CALAGOPUS_WINGS_RAW"
	docker_set_compose_image "${CALAGOPUS_WINGS_DIR}/compose.yml" "wings" "$image"
	wings_write_config
	docker_compose_up "$CALAGOPUS_WINGS_DIR"

	CFG[INSTALLED_WINGS_MODE]="docker"
	config_mark_installed WINGS
	log_ok "wings deployed (docker). Configure the node in the panel if not already."
}

# -----------------------------------------------------------------------------
# Native deployment
# -----------------------------------------------------------------------------
wings_install_native() {
	if wings_is_aio_bundled; then { log_ok "wings is bundled in the AIO panel container; nothing to do"; return 0; } fi
	dep_provision docker   # wings needs a container runtime regardless

	local url; url="$(wings_binary_url)"
	log_info "downloading wings binary: $url"
	system_as_root install -d -m0755 "$(dirname "$CALAGOPUS_WINGS_BIN")"
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would install binary to $CALAGOPUS_WINGS_BIN"
	else
		curl -fsSL "$url" -o /tmp/wings
		system_as_root install -m0755 /tmp/wings "$CALAGOPUS_WINGS_BIN"
		rm -f /tmp/wings
	fi
	"$CALAGOPUS_WINGS_BIN" version >/dev/null 2>&1 || log_warn "wings binary present but 'version' failed"

	# Configure from join-data if provided.
	if [ -n "${CFG[WINGS_JOIN_DATA]:-}" ]; then
		if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
			log_info "[dry-run] would run: wings configure --join-data <redacted>"
		else
			"$CALAGOPUS_WINGS_BIN" configure --join-data "${CFG[WINGS_JOIN_DATA]}" 2>&1 \
				| tee -a "$CALAGOPUS_LOGFILE" >/dev/null || log_warn "wings configure did not complete"
		fi
	fi

	# Register systemd service.
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would run: wings service-install"
	else
		"$CALAGOPUS_WINGS_BIN" service-install 2>&1 | tee -a "$CALAGOPUS_LOGFILE" >/dev/null || true
		system_as_root systemctl enable --now "$CALAGOPUS_WINGS_SERVICE" 2>/dev/null || true
	fi

	CFG[INSTALLED_WINGS_MODE]="native"
	config_mark_installed WINGS
	log_ok "wings installed (native). Remember to set up allocations."
}

# -----------------------------------------------------------------------------
# Public entry
# -----------------------------------------------------------------------------
wings_install() {
	case "${CALAGOPUS_DEPLOY_MODE:-docker}" in
		docker) wings_install_docker ;;
		native) wings_install_native ;;
		*) log_die "unknown deploy mode: ${CALAGOPUS_DEPLOY_MODE}" ;;
	esac
}

wings_reconfigure() {
	wings_gather
	if [ "${CFG[INSTALLED_WINGS_MODE]:-}" = "native" ]; then
		if [ -n "${CFG[WINGS_JOIN_DATA]:-}" ]; then
			"$CALAGOPUS_WINGS_BIN" configure --join-data "${CFG[WINGS_JOIN_DATA]}" 2>&1 \
				| tee -a "$CALAGOPUS_LOGFILE" >/dev/null || true
		fi
		system_as_root systemctl restart "$CALAGOPUS_WINGS_SERVICE" 2>/dev/null || true
	else
		wings_write_config
		( cd "${CALAGOPUS_WINGS_DIR}" && docker compose up -d --force-recreate ) 2>/dev/null || true
	fi
	log_ok "wings reconfigured"
}
