#!/usr/bin/env bash
#
# src/dependencies/docker.sh - Docker Engine + Compose plugin provisioning.
#
# Strategy:
#   1. If docker is already present and >= our minimum, keep it.
#   2. Otherwise use Docker's official get.docker.com script (works across all
#      supported distros and ARM64) which is the path Calagopus' own docs
#      recommend. We pin CHANNEL=stable and pass it through as root.
#   3. Ensure the compose plugin is present (v2), enabling `docker compose`.
#   4. Enable + start the daemon and add the running user to the docker group
#      when not root (so subsequent non-root invocations work post-relogin).
#
# Keeping get.docker.com as the primary path matches upstream Calagopus docs
# and avoids per-distro repo drift. The per-OS repo helpers remain available
# for users who set CALAGOPUS_DOCKER_SOURCE=repo.

if [ -n "${CALAGOPUS_LIB_DEPS_DOCKER:-}" ]; then return 0; fi
CALAGOPUS_LIB_DEPS_DOCKER=1

DOCKER_MIN_VERSION="20.10"

docker_installed() { command -v docker >/dev/null 2>&1; }

docker_version() {
	docker --version 2>/dev/null | awk '{print $3}' | sed 's/,//'
}

# Compare two dotted version strings; returns 0 if $1 >= $2.
_docker_ver_ge() {
	local a="$1" b="$2"
	[ "$a" = "$b" ] && return 0
	printf '%s\n%s\n' "$a" "$b" | sort -V -C && return 1 || return 0
}

docker_health() {
	docker_installed || return 1
	docker info >/dev/null 2>&1
}

docker_install() {
	# Already installed and recent enough -> just ensure compose plugin.
	if docker_installed; then
		local ver; ver="$(docker_version)"
		if _docker_ver_ge "$ver" "$DOCKER_MIN_VERSION"; then
			log_debug "docker ${ver} already satisfies >= ${DOCKER_MIN_VERSION}"
			docker_ensure_compose
			system_as_root systemctl enable --now docker 2>/dev/null || true
			return 0
		else
			log_warn "docker ${ver} older than ${DOCKER_MIN_VERSION}; upgrading"
		fi
	fi

	local source="${CALAGOPUS_DOCKER_SOURCE:-script}"
	case "$source" in
		repo)
			case "$OS_FAMILY" in
				debian) debian_add_docker_repo ;;
				rhel)   rhel_add_docker_repo ;;
				suse)   suse_add_docker_repo ;;
				arch)   : ;;
				*) log_warn "repo docker source unsupported on $OS_FAMILY; falling back to script"; source="script" ;;
			esac
			if [ "$source" = "repo" ]; then
				local pkgs=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
				[ "$OS_FAMILY" = "arch" ] && pkgs=(docker docker-compose)
				os_pkg_install "${pkgs[@]}"
			fi
			;;
		script|*)
			if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
				log_info "[dry-run] would run get.docker.com"
			else
				curl -fsSL https://get.docker.com \
					| CHANNEL=stable system_as_root env sh
			fi
			;;
	esac

	docker_ensure_compose
	system_as_root systemctl enable --now docker
	# Non-root convenience: add caller to docker group (takes effect next login).
	if ! common_is_root; then
		system_as_root groupadd -f docker 2>/dev/null || true
		system_as_root usermod -aG docker "$(id -un)" 2>/dev/null || true
		log_warn "added current user to 'docker' group - log out/in (or 'newgrp docker') to apply"
	fi
}

# Make sure `docker compose` (v2 plugin) is available; install it if missing.
docker_ensure_compose() {
	if docker compose version >/dev/null 2>&1; then
		log_debug "docker compose v2 plugin present"
		return 0
	fi
	# Try the distro package first.
	case "$OS_FAMILY" in
		debian) os_pkg_install docker-compose-plugin ;;
		rhel)   os_pkg_install docker-compose-plugin ;;
		arch)   os_pkg_install docker-compose ;;
		suse)   os_pkg_install docker-compose ;;
	esac
	if docker compose version >/dev/null 2>&1; then return 0; fi
	# Last resort: download the standalone plugin binary into the cli plugins dir.
	local arch; arch="$(system_arch)"
	local url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}"
	local dest="/usr/libexec/docker/cli-plugins/docker-compose"
	system_as_root install -d -m0755 "$(dirname "$dest")"
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would download compose plugin to $dest"
	else
		curl -fsSL "$url" -o /tmp/docker-compose
		system_as_root install -m0755 /tmp/docker-compose "$dest"
		rm -f /tmp/docker-compose
	fi
}
