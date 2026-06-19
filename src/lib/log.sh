#!/usr/bin/env bash
#
# src/lib/log.sh - Structured logging with automatic secret redaction.
#
# Console output is clean and colored (checkmarks, warnings, etc.) without
# timestamps. The on-disk log file keeps full timestamps for debugging.
# Secrets are redacted before reaching either destination.

if [ -n "${CALAGOPUS_LIB_LOG:-}" ]; then return 0; fi
CALAGOPUS_LIB_LOG=1

# Secret key patterns - values stored under these CFG keys are masked in logs.
CALAGOPUS_SECRET_KEYS="APP_ENCRYPTION_KEY DATABASE_URL DATABASE_URL_PRIMARY REDIS_URL REDIS_PASSWORD POSTGRES_PASSWORD PANEL_DB_PASSWORD WINGS_TOKEN SENTRY_URL CLOUDFLARE_API_KEY SSL_PRIVATE_KEY_PATH"

# Regex fragments used to scrub secrets that appear inline in free-form text.
CALAGOPUS_SECRET_REGEX='(postgresql|redis|rediss|https?)://[^:]+:[^@]+@|(Bearer |token=|api[_-]?key=|password=)[^ ]+'

# -----------------------------------------------------------------------------
# Internal: redact a single line of text.
# -----------------------------------------------------------------------------
log_redact() {
	local line="$1"
	local key val
	if declare -p CFG >/dev/null 2>&1; then
		for key in $CALAGOPUS_SECRET_KEYS; do
			val="${CFG[$key]:-}"
			if [ -n "$val" ]; then
				line="${line//"${val}"/**REDACTED**}"
			fi
		done
	fi
	line="$(printf '%s' "$line" | sed -E "s#${CALAGOPUS_SECRET_REGEX}#\1**REDACTED**#g")"
	printf '%s' "$line"
}

# -----------------------------------------------------------------------------
# Internal: write to the log file (with timestamp) + console (clean/colored).
# Console output uses symbols instead of [LEVEL] text for a cleaner look.
# -----------------------------------------------------------------------------
_log_emit() {
	local level="$1"; shift
	local msg="$*"
	local ts
	ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
	msg="$(log_redact "$msg")"
	local file_line="[${ts}] [${level}] ${msg}"

	# Always persist to the log file with full timestamp.
	if [ -n "${CALAGOPUS_LOGFILE:-}" ] && [ -w "${CALAGOPUS_LOGFILE%/*}" ] 2>/dev/null \
		|| { [ -n "${CALAGOPUS_LOGFILE:-}" ] && common_is_root; }; then
		printf '%s\n' "$file_line" >>"$CALAGOPUS_LOGFILE" 2>/dev/null || true
	fi

	# Console output: clean symbols, no timestamps.
	# Colors come from ui.sh (sourced before us). If colors are empty
	# (non-TTY / --no-color), the symbols still work plain.
	local sym color target
	case "$level" in
		OK)
			sym="✓"; color="${C_GREEN:-}"
			target="stdout" ;;
		INFO)
			sym="•"; color="${C_CYAN:-}"
			target="stdout" ;;
		DEBUG)
			sym="·"; color="${C_GREY:-}"
			target="stdout" ;;
		WARN)
			sym="⚠"; color="${C_YELLOW:-}"
			target="stderr" ;;
		ERROR)
			sym="✗"; color="${C_RED:-}"
			target="stderr" ;;
		FATAL)
			sym="✗"; color="${C_RED:-}"
			target="stderr" ;;
		*)
			sym="•"; color=""
			target="stdout" ;;
	esac

	# Skip DEBUG on console unless verbose/debug.
	if [ "$level" = "DEBUG" ] && [ "${CALAGOPUS_VERBOSE:-0}" -eq 0 ] && [ "${CALAGOPUS_DEBUG:-0}" -eq 0 ]; then
		return 0
	fi
	# Skip non-ERROR/WARN on console if quiet.
	if [ "${CALAGOPUS_QUIET:-0}" -eq 1 ] && [ "$target" = "stdout" ]; then
		return 0
	fi

	local console_line
	console_line=" ${color}${sym}${C_RESET:-} ${msg}"

	if [ "$target" = "stderr" ]; then
		printf '%s\n' "$console_line" >&2
	else
		printf '%s\n' "$console_line"
	fi

	# Debug sink.
	if [ "${CALAGOPUS_DEBUG:-0}" -eq 1 ] && [ -n "${CALAGOPUS_LOGFILE:-}" ]; then
		printf '%s\n' "[debug] ${file_line}" >>"${CALAGOPUS_LOGFILE}.debug" 2>/dev/null || true
	fi
}

# -----------------------------------------------------------------------------
# Public log levels
# -----------------------------------------------------------------------------
log_debug() {
	if [ "${CALAGOPUS_VERBOSE:-0}" -eq 1 ] || [ "${CALAGOPUS_DEBUG:-0}" -eq 1 ]; then
		_log_emit DEBUG "$@"
	fi
}
log_info()    { _log_emit INFO    "$@"; }
log_ok()      { _log_emit OK      "$@"; }
log_warn()    { _log_emit WARN    "$@"; }
log_error()   { _log_emit ERROR   "$@"; }
log_fatal()   { _log_emit FATAL   "$@"; }

# Die loudly with a message and non-zero exit.
log_die() {
	log_fatal "$*"
	exit 1
}

# -----------------------------------------------------------------------------
# Log lifecycle helpers
# -----------------------------------------------------------------------------
log_init() {
	mkdir -p "${CALAGOPUS_LOG_DIR}" 2>/dev/null || true
	touch "${CALAGOPUS_LOGFILE}" 2>/dev/null || true
	chmod 0640 "${CALAGOPUS_LOGFILE}" 2>/dev/null || true
	{
		printf '\n===== Calagopus Installer run %s =====\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
		printf 'action=%s target=%s mode=%s channel=%s\n' \
			"${CALAGOPUS_ACTION:-none}" "${CALAGOPUS_INSTALL_TARGET:-none}" \
			"${CALAGOPUS_DEPLOY_MODE:-none}" "${CALAGOPUS_RELEASE_CHANNEL:-none}"
	} >>"$CALAGOPUS_LOGFILE" 2>/dev/null || true
}

log_rotate() {
	[ -f "${CALAGOPUS_LOGFILE}" ] || return 0
	local size
	size="$(stat -c%s "${CALAGOPUS_LOGFILE}" 2>/dev/null || stat -f%z "${CALAGOPUS_LOGFILE}" 2>/dev/null || echo 0)"
	if [ "$size" -gt 5242880 ]; then
		for i in 2 1; do
			[ -f "${CALAGOPUS_LOGFILE}.$i" ] && mv "${CALAGOPUS_LOGFILE}.$i" "${CALAGOPUS_LOGFILE}.$((i+1))"
		done
		mv "${CALAGOPUS_LOGFILE}" "${CALAGOPUS_LOGFILE}.1"
		touch "${CALAGOPUS_LOGFILE}"
		chmod 0640 "${CALAGOPUS_LOGFILE}"
	fi
}

# Tee a command's output into the log while still showing it to the user.
log_run() {
	local label="$1"; shift
	[ "$1" = "--" ] && shift
	log_info "running: $label"
	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would execute: $*"
		return 0
	fi
	"$@" 2>&1 | tee -a "${CALAGOPUS_LOGFILE}" >/dev/null 2>&1 || true
	local rc=${PIPESTATUS[0]}
	if [ "$rc" -ne 0 ]; then
		log_error "'$label' failed (exit $rc)"
		return "$rc"
	fi
	return 0
}
