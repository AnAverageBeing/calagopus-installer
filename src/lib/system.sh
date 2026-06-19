#!/usr/bin/env bash
#
# src/lib/system.sh - Host capability checks: arch, root, memory, disk, kernel.
#
# Used by the validation step before installation and by repair/doctor for
# reporting. All checks are read-only and side-effect free.

if [ -n "${CALAGOPUS_LIB_SYSTEM:-}" ]; then return 0; fi
CALAGOPUS_LIB_SYSTEM=1

# Normalised CPU architecture -> Calagopus asset suffix.
# Calagopus ships per-arch binaries named like panel-rs-<arch>-linux.
system_arch() {
	local a
	a="$(uname -m 2>/dev/null || echo unknown)"
	case "$a" in
		x86_64|amd64)  printf 'x86_64' ;;
		aarch64|arm64) printf 'aarch64' ;;
		armv7l)        printf 'armv7' ;;
		riscv64)       printf 'riscv64' ;;
		ppc64le)       printf 'ppc64le' ;;
		*) printf '%s' "$a" ;;
	esac
}

# True if the current arch is one Calagopus publishes binaries for.
system_arch_supported() {
	case "$(system_arch)" in
		x86_64|aarch64|armv7|riscv64|ppc64le) return 0 ;;
		*) return 1 ;;
	esac
}

# RAM in MiB (best-effort across Linux variants).
system_ram_mib() {
	if [ -r /proc/meminfo ]; then
		awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo
	else
		echo 0
	fi
}

# Free disk in MiB for a given path (default: install dir).
system_free_mib() {
	local path="${1:-${CALAGOPUS_INSTALL_DIR}}"
	df -m --output=avail "$path" 2>/dev/null | awk 'NR==2{print $1}' || echo 0
}

# Kernel version (major.minor).
system_kernel() { uname -r 2>/dev/null | cut -d. -f1-2; }

# True if systemd is the init system (needed for service-install).
system_has_systemd() {
	[ -d /run/systemd/system ] || command -v systemctl >/dev/null 2>&1
}

# True if running inside a container (LXC/Docker). Used to soften some checks.
system_in_container() {
	[ -f /.dockerenv ] && return 0
	grep -qaE 'container=lxc|container=docker' /proc/1/environ 2>/dev/null && return 0
	return 1
}

# Public IPv4 (best-effort, never fatal).
system_public_ip() {
	if common_cmd_exists curl; then
		curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null && return 0
	fi
	echo ""
}

# -----------------------------------------------------------------------------
# Preflight validation: combine arch/ram/disk/systemd checks into one report.
# Returns non-zero if any HARD requirement fails; soft failures only warn.
# -----------------------------------------------------------------------------
system_preflight() {
	local rc=0
	local arch ram free

	arch="$(system_arch)"
	if system_arch_supported; then
		log_ok "architecture supported: ${arch}"
	else
		log_error "unsupported architecture: ${arch} (need x86_64/aarch64/armv7/riscv64/ppc64le)"
		rc=1
	fi

	ram="$(system_ram_mib)"
	if [ "$ram" -ge 512 ]; then
		log_ok "memory: ${ram} MiB (>= 512 required)"
	else
		log_warn "low memory: ${ram} MiB (512 MiB minimum, 1 GiB recommended)"
	fi

	free="$(system_free_mib "${CALAGOPUS_INSTALL_DIR}")"
	if [ "$free" -ge 1024 ]; then
		log_ok "disk: ${free} MiB free under ${CALAGOPUS_INSTALL_DIR}"
	else
		log_error "insufficient disk: ${free} MiB free (need >= 1 GiB)"
		rc=1
	fi

	if system_has_systemd; then
		log_ok "systemd detected"
	else
		log_warn "systemd not detected - service management will be limited"
	fi

	if common_is_root; then
		log_ok "running as root"
	else
		if [ "${CALAGOPUS_ASSUME_YES:-0}" -eq 1 ] || [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 0 ]; then
			log_warn "not running as root - some operations will need sudo and may fail"
		else
			ui_warn "not running as root; several steps require root (we will use sudo)."
			ui_confirm "Continue anyway?" "n" || log_die "aborted by user"
		fi
	fi

	return "$rc"
}

# Acquire sudo privileges if not root (best-effort, caches via sudo -v).
system_ensure_sudo() {
	if common_is_root; then return 0; fi
	if ! command -v sudo >/dev/null 2>&1; then
		log_die "sudo is required when not running as root, but it is not installed"
	fi
	sudo -v 2>/dev/null || log_die "failed to acquire sudo privileges"
}

# Run a command as root (via sudo if needed). Used throughout for idempotent ops.
system_as_root() {
	if common_is_root; then "$@"; else sudo "$@"; fi
}
