#!/usr/bin/env bash
#
# src/lib/trap.sh - Error/cleanup/interrupt handling.
#
# Gives the installer a single, consistent failure mode:
#   * any unexpected error captures a backtrace,
#   * Ctrl-C produces a clean "aborted" message and rolls back the in-flight
#     step via a stack of registered cleanup callbacks,
#   * a structured marker is written to the log so monitoring can detect
#     aborted runs.
#
# Modules register cleanup work with trap_push "cleanup_fn" and remove it with
# trap_pop once their step completed successfully. This makes rollback LIFO and
# scoped to whatever was actually started.

if [ -n "${CALAGOPUS_LIB_TRAP:-}" ]; then return 0; fi
CALAGOPUS_LIB_TRAP=1

# Stack of cleanup function names.
declare -ga TRAP_CLEANUP_STACK=()
TRAP_ABORTING=0

# Push a cleanup callback (function name) onto the stack.
trap_push() {
	TRAP_CLEANUP_STACK+=("$1")
}

# Pop the most recent cleanup callback (call after a step completes OK so we
# don't roll back successful work).
trap_pop() {
	local n=${#TRAP_CLEANUP_STACK[@]}
	if [ "$n" -gt 0 ]; then unset 'TRAP_CLEANUP_STACK[n-1]'; fi
}

# Run all registered cleanups in reverse order. Swallow individual failures so
# one bad callback cannot prevent the rest from running.
trap_run_cleanup() {
	if [ "${TRAP_ABORTING:-0}" -eq 1 ]; then return 0; fi
	TRAP_ABORTING=1
	local i n=${#TRAP_CLEANUP_STACK[@]}
	for ((i=n-1; i>=0; i--)); do
		local fn="${TRAP_CLEANUP_STACK[i]}"
		if declare -F "$fn" >/dev/null 2>&1; then
			log_debug "cleanup: $fn"
			"$fn" 2>/dev/null || true
		fi
	done
	TRAP_CLEANUP_STACK=()
}

# Backtrace helper (bash >= 4).
trap_backtrace() {
	local i=0 frame
	if [ -z "${BASH_VERSION:-}" ]; then return 0; fi
	while caller "$i" 2>/dev/null | {
		read -r line file func
		printf '  #%d %s:%d %s\n' "$i" "${file:-?}" "${line:-0}" "${func:-main}"
	}; do i=$((i+1)); done
}

# The global ERR handler.
trap_on_error() {
	local rc=$?
	log_error "unexpected error (exit ${rc}) at:"
	trap_backtrace >&2
	trap_run_cleanup
	exit "$rc"
}

# The global EXIT handler - runs only remaining (non-aborted) cleanups.
trap_on_exit() {
	local rc=$?
	trap_run_cleanup
	if [ "$rc" -eq 0 ]; then
		log_ok "installer finished successfully"
	else
		log_error "installer finished with errors (exit ${rc})"
	fi
}

# Ctrl-C / SIGTERM.
trap_on_interrupt() {
	log_warn "interrupted by signal"
	trap_run_cleanup
	exit 130
}

# Install all the handlers. Call once near the top of installer.sh.
trap_install() {
	set -Eeuo pipefail
	trap trap_on_error ERR
	trap trap_on_exit EXIT
	trap trap_on_interrupt INT TERM
}

# Wrap a step so a failure rolls back cleanly and still surfaces the error.
# Usage: trap_step "label" function_name args...
trap_step() {
	local label="$1"; shift
	log_info "step: $label"
	ui_step_begin "$label"
	"$@"
	local rc=$?
	ui_step_end "$rc"
	if [ "$rc" -ne 0 ]; then
		log_error "step failed: $label"
		return "$rc"
	fi
	trap_pop  # step succeeded, drop its cleanup hook if it pushed one
	return 0
}
