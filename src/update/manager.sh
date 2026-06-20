#!/usr/bin/env bash
#
# src/update/manager.sh - Upgrade + rollback for panel/wings.
#
# Update flow:
#   1. Check the latest release for the current channel.
#   2. Detect installed version.
#   3. If newer, create a backup (so rollback is possible).
#   4. Pull the new image / download the new binary.
#   5. Restart the service.
#   6. Verify health; if unhealthy, roll back automatically.
#
# Channels (stable|beta|nightly) map to image tags / release tags as defined in
# common.sh + docker/configure.sh. A failed upgrade restores the pre-upgrade
# backup bundle and restarts services.

if [ -n "${CALAGOPUS_LIB_UPDATE:-}" ]; then return 0; fi
CALAGOPUS_LIB_UPDATE=1

# Query the GitHub API for the latest release tag of a repo.
# Echoes the tag name (e.g. v1.2.3) or empty on failure.
update_latest_tag() {
	local repo="$1"
	if ! command -v curl >/dev/null 2>&1; then return 1; fi
	curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
		| grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
}

update_panel_latest() {
	case "${CALAGOPUS_RELEASE_CHANNEL:-stable}" in
		stable)  update_latest_tag "calagopus/panel" ;;
		beta)    echo "latest-pre" ;;
		nightly) echo "nightly" ;;
	esac
}
update_wings_latest() {
	case "${CALAGOPUS_RELEASE_CHANNEL:-stable}" in
		stable)  update_latest_tag "calagopus/wings" ;;
		beta)    echo "latest-pre" ;;
		nightly) echo "nightly" ;;
	esac
}

# Upgrade the panel. docker: pull new image + recreate. native: download binary.
update_panel() {
	if ! config_is_installed PANEL; then log_warn "panel not installed; nothing to upgrade"; return 0; fi
	log_info "upgrading panel (channel=${CALAGOPUS_RELEASE_CHANNEL})"

	local pre_backup
	pre_backup="$(backup_create)" || log_warn "pre-upgrade backup failed; continuing anyway"
	CFG[LAST_UPGRADED_AT]="$(date '+%Y-%m-%dT%H:%M:%S%z')"

	if [ "${CFG[INSTALLED_PANEL_MODE]:-}" = "native" ]; then
		local url; url="$(panel_binary_url)"
		local old_bin="${CALAGOPUS_PANEL_BIN}.prev"
		if [ -x "$CALAGOPUS_PANEL_BIN" ]; then system_as_root cp -a "$CALAGOPUS_PANEL_BIN" "$old_bin"; fi
		curl -fsSL "$url" -o /tmp/calagopus-panel
		system_as_root install -m0755 /tmp/calagopus-panel "$CALAGOPUS_PANEL_BIN"
		rm -f /tmp/calagopus-panel
		system_as_root systemctl restart "$CALAGOPUS_PANEL_SERVICE" 2>/dev/null || true
		sleep 3
		if ! panel_health; then
			log_error "panel unhealthy after upgrade - rolling back"
			system_as_root cp -a "$old_bin" "$CALAGOPUS_PANEL_BIN"
			system_as_root systemctl restart "$CALAGOPUS_PANEL_SERVICE" 2>/dev/null || true
			backup_restore "$pre_backup" 2>/dev/null || true
			return 1
		fi
		system_as_root rm -f "$old_bin"
	else
		( cd "$CALAGOPUS_PANEL_DIR" && docker compose pull && docker compose up -d )
		sleep 3
		if ! panel_health; then
			log_error "panel container unhealthy after upgrade - rolling back"
			backup_restore "$pre_backup" 2>/dev/null || true
			return 1
		fi
	fi
	CFG[INSTALLED_PANEL_VERSION]="$(panel_version 2>/dev/null || echo unknown)"
	config_save
	log_ok "panel upgraded to $(panel_version 2>/dev/null || echo 'latest')"
}

update_wings() {
	if ! config_is_installed WINGS; then log_warn "wings not installed; nothing to upgrade"; return 0; fi
	if wings_is_aio_bundled; then log_info "wings is bundled in AIO panel - upgraded with the panel"; return 0; fi
	log_info "upgrading wings (channel=${CALAGOPUS_RELEASE_CHANNEL})"
	local pre_backup; pre_backup="$(backup_create)" || true

	if [ "${CFG[INSTALLED_WINGS_MODE]:-}" = "native" ]; then
		local url; url="$(wings_binary_url)"
		local old_bin="${CALAGOPUS_WINGS_BIN}.prev"
		if [ -x "$CALAGOPUS_WINGS_BIN" ]; then system_as_root cp -a "$CALAGOPUS_WINGS_BIN" "$old_bin"; fi
		curl -fsSL "$url" -o /tmp/wings
		system_as_root install -m0755 /tmp/wings "$CALAGOPUS_WINGS_BIN"
		rm -f /tmp/wings
		system_as_root systemctl restart "$CALAGOPUS_WINGS_SERVICE" 2>/dev/null || true
		sleep 3
		if ! wings_health; then
			log_error "wings unhealthy after upgrade - rolling back"
			system_as_root cp -a "$old_bin" "$CALAGOPUS_WINGS_BIN"
			system_as_root systemctl restart "$CALAGOPUS_WINGS_SERVICE" 2>/dev/null || true
			return 1
		fi
		system_as_root rm -f "$old_bin"
	else
		( cd "$CALAGOPUS_WINGS_DIR" && docker compose pull && docker compose up -d )
		sleep 3
		if ! wings_health; then
			log_error "wings container unhealthy after upgrade - rolling back"
			backup_restore "$pre_backup" 2>/dev/null || true
			return 1
		fi
	fi
	CFG[INSTALLED_WINGS_VERSION]="$(wings_version 2>/dev/null || echo unknown)"
	config_save
	log_ok "wings upgraded to $(wings_version 2>/dev/null || echo 'latest')"
}

update_all() {
	update_panel
	update_wings
	CFG[LAST_UPGRADED_AT]="$(date '+%Y-%m-%dT%H:%M:%S%z')"
	config_save
}

# Roll back to the most recent backup bundle (or a specified one).
update_rollback() {
	local bundle="${1:-$(find "$(backup_dir)" -name 'calagopus-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)}"
	[ -n "$bundle" ] || { log_error "no backup bundle available to roll back to"; return 1; }
	log_warn "rolling back to $bundle"
	backup_restore "$bundle"
}
