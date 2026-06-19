#!/usr/bin/env bash
#
# src/dependencies/manager.sh - Central dependency provisioning facade.
#
# Each concrete dependency (docker, postgres, redis, nginx, caddy, certbot)
# lives in its own file and exposes a uniform contract:
#
#   <name>_installed      -> 0 if present, 1 otherwise
#   <name>_install        -> install/upgrade the component (idempotent)
#   <name>_version        -> echo installed version string (or empty)
#   <name>_health         -> 0 if healthy/running, 1 otherwise
#
# This file provides dep_provision (ask for a component and make sure it is
# installed + healthy) and dep_install_base (the always-needed system tools:
# curl, git, openssl, firewall tooling, etc).

if [ -n "${CALAGOPUS_LIB_DEPS_MANAGER:-}" ]; then return 0; fi
CALAGOPUS_LIB_DEPS_MANAGER=1

# Source all dependency modules once.
_deps_source_all() {
	local f
	for f in docker postgres redis nginx caddy certbot packages; do
		# shellcheck source=/dev/null
		. "${CALAGOPUS_ROOT}/src/dependencies/${f}.sh"
	done
}

# Map a friendly component name to its module prefix.
_dep_prefix() {
	case "$1" in
		docker|docker-ce) printf 'docker' ;;
		postgres|postgresql) printf 'postgres' ;;
		redis|valkey) printf 'redis' ;;
		nginx) printf 'nginx' ;;
		caddy) printf 'caddy' ;;
		certbot) printf 'certbot' ;;
		*) printf '%s' "$1" ;;
	esac
}

# dep_provision <component>  - ensure installed, healthy, and record in state.
# Returns 0 on success. Skips work if already present and healthy.
dep_provision() {
	local comp="$1" prefix fn
	_deps_source_all
	prefix="$(_dep_prefix "$comp")"

	if declare -F "${prefix}_installed" >/dev/null 2>&1 && "${prefix}_installed"; then
		log_ok "${comp} already installed ($("${prefix}_version" 2>/dev/null || echo '?'))"
		if declare -F "${prefix}_health" >/dev/null 2>&1 && ! "${prefix}_health"; then
			log_warn "${comp} installed but not healthy - attempting start"
			system_as_root systemctl enable --now "${comp}" 2>/dev/null || \
				system_as_root systemctl enable --now "${prefix}" 2>/dev/null || true
		fi
		return 0
	fi
	log_info "provisioning dependency: ${comp}"
	if ! declare -F "${prefix}_install" >/dev/null 2>&1; then
		log_error "no install function for '${comp}'"; return 1
	fi
	"${prefix}_install" || { log_error "failed to install ${comp}"; return 1; }
	# Verify post-install.
	if declare -F "${prefix}_installed" >/dev/null 2>&1 && ! "${prefix}_installed"; then
		log_error "${comp} install reported success but binary missing"
		return 1
	fi
	log_ok "${comp} installed ($("${prefix}_version" 2>/dev/null || echo '?'))"
	return 0
}

# Provision a list of components.
dep_provision_all() {
	local c rc=0
	for c in "$@"; do dep_provision "$c" || rc=1; done
	return "$rc"
}

# Base system tooling that every install path needs. Idempotent.
dep_install_base() {
	_deps_source_all
	log_info "ensuring base system tools"
	local pkgs=(curl git openssl ca-certificates tar gzip)
	# Firewall tooling: prefer ufw on debian, firewalld on rhel.
	case "$OS_FAMILY" in
		debian) pkgs+=(ufw) ;;
		rhel)   pkgs+=(firewalld) ;;
		arch)   pkgs+=(ufw) ;;
		suse)   pkgs+=(firewalld) ;;
	esac
	os_pkg_install "${pkgs[@]}"
	packages_install_jq_optional
	log_ok "base tools ready"
}
