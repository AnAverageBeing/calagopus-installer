#!/usr/bin/env bash
#
# src/docker/configure.sh - Docker daemon configuration + networking + health.
#
# Builds on dependencies/docker.sh (which installs the engine). This module:
#   * writes a sane /etc/docker/daemon.json (log rotation, live-restore),
#   * ensures a dedicated `calagopus` bridge network exists for compose stacks,
#   * validates the engine is actually functional,
#   * exposes helpers for pulling compose stacks and starting/stopping them.
#
# All operations are idempotent: re-running won't recreate an existing network
# or clobber a daemon.json that already has the right keys (we merge instead).

if [ -n "${CALAGOPUS_LIB_DOCKER_CONFIGURE:-}" ]; then return 0; fi
CALAGOPUS_LIB_DOCKER_CONFIGURE=1

CALAGOPUS_DOCKER_NETWORK="calagopus"
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

# Default daemon.json content. We keep it minimal and merge with anything that
# is already there so we don't fight the operator's own tuning.
DOCKER_DAEMON_DEFAULTS='{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "userland-proxy": false
}'

# Merge two JSON objects without jq (best-effort string merge). If jq IS
# available we use it for a proper deep merge.
_docker_json_merge() {
	local a="$1" b="$2"
	if command -v jq >/dev/null 2>&1; then
		jq -s '.[0] * .[1]' <<<"${a}${b}" 2>/dev/null \
			|| printf '%s' "$b"
	else
		# Naive fallback: prefer $b keys by concatenating objects. Good enough
		# for the small, flat daemon.json we manage.
		printf '%s,%s' "${a%"{}"}" "${b#"{}"}" | sed 's/},{$/},{/' | sed 's/^/{$/{/'
	fi
}

# Write daemon.json if missing, or merge our defaults into the existing one.
docker_configure_daemon() {
	dep_provision docker
	local existing=""
	if [ -f "$DOCKER_DAEMON_JSON" ]; then
		existing="$(cat "$DOCKER_DAEMON_JSON")"
		if [ -n "$existing" ] && ! grep -q "calagopus-installer" "$DOCKER_DAEMON_JSON"; then
			local merged
			merged="$(_docker_json_merge "$existing" "$DOCKER_DAEMON_DEFAULTS")"
			config_backup_file "$DOCKER_DAEMON_JSON" >/dev/null
			system_as_root cp -a "$DOCKER_DAEMON_JSON" "${DOCKER_DAEMON_JSON}.calagopus-orig"
			system_as_root tee "$DOCKER_DAEMON_JSON" >/dev/null <<<"$merged"
			system_as_root systemctl restart docker 2>/dev/null || true
		fi
	else
		system_as_root tee "$DOCKER_DAEMON_JSON" >/dev/null <<<"$DOCKER_DAEMON_DEFAULTS"
		system_as_root systemctl restart docker 2>/dev/null || true
	fi
}

# Ensure the shared bridge network exists (compose stacks reference it by name).
docker_ensure_network() {
	docker_health || return 1
	if docker network inspect "$CALAGOPUS_DOCKER_NETWORK" >/dev/null 2>&1; then
		log_debug "docker network '$CALAGOPUS_DOCKER_NETWORK' exists"
		return 0
	fi
	log_info "creating docker network '$CALAGOPUS_DOCKER_NETWORK'"
	docker network create --driver bridge "$CALAGOPUS_DOCKER_NETWORK" >/dev/null
}

# Run a full health probe: daemon up, compose plugin present, network exists.
docker_full_health() {
	docker_health || { log_error "docker daemon not running"; return 1; }
	docker compose version >/dev/null 2>&1 || { log_error "docker compose plugin missing"; return 1; }
	docker network inspect "$CALAGOPUS_DOCKER_NETWORK" >/dev/null 2>&1 || { log_warn "calagopus network missing"; return 2; }
	return 0
}

# Pull a compose file from the upstream repo into a working directory.
# Usage: docker_fetch_compose <dest_dir> <compose_key (panel_aio|panel_basic|wings_local|...)> [repo_raw]
docker_fetch_compose() {
	local dest="$1" key="$2" raw="${3:-}"
	local fname="${CALAGOPUS_COMPOSE_FILES[$key]:-compose.yml}"
	local url
	if [ -n "$raw" ]; then
		url="${raw}/${fname}"
	elif [ "$key" = "wings_local" ]; then
		url="${CALAGOPUS_WINGS_RAW}/${fname}"
	else
		url="${CALAGOPUS_PANEL_RAW}/${fname}"
	fi
	mkdir -p "$dest"
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would fetch $url -> $dest/compose.yml"
		return 0
	fi
	curl -fsSL "$url" -o "${dest}/compose.yml" \
		|| { log_error "failed to download compose file: $url"; return 1; }
}

# Substitute image tag in a compose file according to the release channel.
docker_set_compose_image() {
	local compose="$1" service="$2" image="$3"
	[ -f "$compose" ] || return 1
	# Use sed to replace the image: line under the named service. This is a
	# best-effort textual substitution; compose YAML ordering from upstream is
	# stable so the pattern is reliable.
	sed -i -E "/^[[:space:]]*${service}:/,/^[^[:space:]]/{
		s|image:.*|image: ${image}|
	}" "$compose"
}

# docker_compose_up <dir> - bring a stack up (detached, pull always).
docker_compose_up() {
	local dir="$1"
	[ -f "${dir}/compose.yml" ] || { log_error "no compose.yml in $dir"; return 1; }
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would run: docker compose -f ${dir}/compose.yml up -d"
		return 0
	fi
	( cd "$dir" && docker compose pull && docker compose up -d )
}

# docker_compose_down <dir> - stop + remove containers (keeps volumes).
docker_compose_down() {
	local dir="$1"
	[ -f "${dir}/compose.yml" ] || return 0
	( cd "$dir" && docker compose down ) 2>/dev/null || true
}

# Echo the image tag to use for a given (component, channel, heavy?, aio?) tuple.
docker_resolve_image() {
	local component="$1" channel="${CALAGOPUS_RELEASE_CHANNEL:-stable}" heavy="${3:-0}" aio="${4:-0}"
	local key
	if [ "$component" = "panel" ]; then
		if [ "$aio" = "1" ]; then
			case "$channel" in
				stable)  [ "$heavy" = "1" ] && key="panel_aio_heavy" || key="panel_aio_stable" ;;
				beta)    key="panel_aio_heavy" ;;  # beta AIO maps to heavy-aio for now
				nightly) [ "$heavy" = "1" ] && key="panel_aio_nightly_heavy" || key="panel_aio_nightly" ;;
			esac
		else
			case "$channel" in
				stable)  [ "$heavy" = "1" ] && key="panel_stable_heavy" || key="panel_stable" ;;
				beta)    [ "$heavy" = "1" ] && key="panel_beta_heavy"    || key="panel_beta" ;;
				nightly) [ "$heavy" = "1" ] && key="panel_nightly_heavy" || key="panel_nightly" ;;
			esac
		fi
	else
		case "$channel" in
			stable)  key="wings_stable" ;;
			beta)    key="wings_beta" ;;
			nightly) key="wings_nightly" ;;
		esac
	fi
	printf '%s' "${CALAGOPUS_IMAGE_TAGS[$key]}"
}
