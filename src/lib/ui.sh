#!/usr/bin/env bash
#
# src/lib/ui.sh - Terminal UI primitives: colors, prompts, progress, menus.
#
# Everything user-facing (other than plain log lines) goes through here so the
# look-and-feel is consistent and so non-interactive / quiet / no-color modes
# can be handled in exactly one place.

if [ -n "${CALAGOPUS_LIB_UI:-}" ]; then return 0; fi
CALAGOPUS_LIB_UI=1

# -----------------------------------------------------------------------------
# Colour setup (disabled when stdout is not a TTY, when --no-color is set, or
# when the user opted into quiet mode).
# -----------------------------------------------------------------------------
_ui_colors_enable() {
	if [ "${CALAGOPUS_NO_COLOR:-0}" -eq 1 ]; then return 1; fi
	if [ "${CALAGOPUS_QUIET:-0}" -eq 1 ]; then return 1; fi
	[ -t 1 ] || return 1
	return 0
}

if _ui_colors_enable; then
	C_RESET=$'\033[0m'
	C_BOLD=$'\033[1m'
	C_RED=$'\033[31m'
	C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'
	C_BLUE=$'\033[34m'
	C_MAGENTA=$'\033[35m'
	C_CYAN=$'\033[36m'
	C_GREY=$'\033[90m'
else
	C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""
	C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GREY=""
fi

# Thematic wrappers (so modules don't hardcode raw colour codes).
ui_brand()    { printf '%s%s%s%s%s' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET" ""; }
ui_title()    { printf '\n%s%s%s%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"; }
ui_step()     { printf '%s=>%s %s\n' "$C_CYAN" "$C_RESET" "$1"; }
ui_ok()       { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
ui_warn()     { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()      { printf '%s[ERR]%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
ui_dim()      { printf '%s%s%s\n' "$C_GREY" "$1" "$C_RESET"; }

# A boxed banner used at the top of interactive runs.
ui_banner() {
	local ver="${CALAGOPUS_INSTALLER_VERSION:-?}"
	printf '\n'
	printf '%s==============================================%s\n' "$C_CYAN" "$C_RESET"
	printf '%s   %s %s%s\n' "$C_BOLD" "$(ui_brand 'Calagopus Installer')" "v${ver}" "$C_RESET"
	printf '%s   Panel + Wings, easy mode.%s\n' "$C_GREY" "$C_RESET"
	printf '%s==============================================%s\n\n' "$C_CYAN" "$C_RESET"
}

# -----------------------------------------------------------------------------
# Prompting - all prompts are no-ops in non-interactive mode (they return the
# provided default instead of blocking on stdin), which is what makes the
# installer fully automatable.
# -----------------------------------------------------------------------------

# ui_prompt_default  "prompt text" "default value"  -> echoes user input or default
ui_prompt_default() {
	local prompt="$1" default="${2:-}" reply
	if [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 0 ]; then
		printf '%s' "$default"; return 0
	fi
	if [ -n "$default" ]; then
		printf '%s%s [%s]%s: ' "$C_BOLD" "$prompt" "$default" "$C_RESET" >&2
	else
		printf '%s%s:%s ' "$C_BOLD" "$prompt" "$C_RESET" >&2
	fi
	read -r reply </dev/tty 2>/dev/null || reply="$default"
	printf '%s' "${reply:-$default}"
}

# ui_prompt  "prompt text"  -> echoes user input (empty allowed only in interactive)
ui_prompt() { ui_prompt_default "$1" ""; }

# ui_confirm  "question" [default(yn)]  -> 0=yes 1=no
ui_confirm() {
	local q="$1" default="${2:-y}"
	if [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 0 ] || [ "${CALAGOPUS_ASSUME_YES:-0}" -eq 1 ]; then
		common_is_yes "$default" && return 0 || return 1
	fi
	local yn
	while true; do
		printf '%s%s [y/N]%s: ' "$C_BOLD" "$q" "$C_RESET" >&2
		read -r yn </dev/tty 2>/dev/null || yn="$default"
		case "$(printf '%s' "$yn" | tr '[:upper:]' '[:lower:]')" in
			y|yes) return 0 ;;
			n|no|"") return 1 ;;
			*) ui_warn "please answer y or n" ;;
		esac
	done
}

# ui_choice  "question" "opt1|opt2|opt3" [default]  -> echoes selected option
ui_choice() {
	local q="$1" default="${3:-}"
	local -a opts=()
	IFS='|' read -ra opts <<<"$2"
	local i pick
	if [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 0 ]; then printf '%s' "$default"; return 0; fi
	while true; do
		printf '%s%s:%s\n' "$C_BOLD" "$q" "$C_RESET" >&2
		i=1
		for opt in "${opts[@]}"; do
			printf '  %s%d)%s %s\n' "$C_CYAN" "$i" "$C_RESET" "$opt" >&2
			i=$((i+1))
		done
		printf 'Choice [%s]: ' "${default:-1}" >&2
		read -r pick </dev/tty 2>/dev/null || pick="$default"
		if [ -z "$pick" ] && [ -n "$default" ]; then pick="$default"; fi
		if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#opts[@]}" ]; then
			printf '%s' "${opts[$((pick-1))]}"
			return 0
		fi
		# also accept matching by text
		for opt in "${opts[@]}"; do
			if [ "${opt,,}" = "${pick,,}" ]; then printf '%s' "$opt"; return 0; fi
		done
		ui_warn "invalid choice"
	done
}

# ui_password  "prompt"  -> echoes a masked password (reads from /dev/tty)
ui_password() {
	local prompt="$1" reply
	if [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 0 ]; then printf '%s' "${CFG[$2]:-}"; return 0; fi
	printf '%s%s:%s ' "$C_BOLD" "$prompt" "$C_RESET" >&2
	read -rs reply </dev/tty 2>/dev/null || reply=""
	printf '\n' >&2
	printf '%s' "$reply"
}

# -----------------------------------------------------------------------------
# Menu - the main interactive menu. Returns the selected action name on stdout.
# -----------------------------------------------------------------------------
ui_main_menu() {
	local action
	if [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 0 ]; then
		printf '%s' "${CALAGOPUS_ACTION:-install}"
		return 0
	fi
	ui_title "What would you like to do?"
	cat >&2 <<'MENU'
  1) Install Panel
  2) Install Wings
  3) Install Full Stack (Panel + Wings)
  4) Upgrade Installation
  5) Repair Installation
  6) Backup Installation
  7) Restore Installation
  8) Reconfigure Installation
  9) Remove Installation
 10) Show System Status
  0) Exit
MENU
	local pick
	printf 'Select an option [1]: ' >&2
	read -r pick </dev/tty 2>/dev/null || pick="1"
	case "${pick:-1}" in
		1) action="install_panel" ;; 2) action="install_wings" ;;
		3) action="install_full" ;;   4) action="upgrade" ;;
		5) action="repair" ;;         6) action="backup" ;;
		7) action="restore" ;;        8) action="reconfigure" ;;
		9) action="remove" ;;         10) action="status" ;;
		0) action="exit" ;;           *) action="install_panel" ;;
	esac
	printf '%s' "$action"
}

# -----------------------------------------------------------------------------
# Progress - lightweight, no external deps. Two modes:
#   ui_step_begin "Doing X"  /  ui_step_end  (prints [OK]/[FAIL] on same line)
#   ui_progress "msg" cur total  (renders a percentage bar)
# -----------------------------------------------------------------------------
UI_CURRENT_STEP=""
ui_step_begin() {
	UI_CURRENT_STEP="$1"
	printf '%s=> %s ...%s' "$C_CYAN" "$1" "$C_RESET"
}
ui_step_end() {
	local rc="${1:-0}"
	if [ "$rc" -eq 0 ]; then
		printf '\r%s=> %s ... [%sOK%s]%s\n' "$C_CYAN" "$UI_CURRENT_STEP" "$C_GREEN" "$C_RESET" "$C_RESET"
	else
		printf '\r%s=> %s ... [%sFAIL%s]%s\n' "$C_CYAN" "$UI_CURRENT_STEP" "$C_RED" "$C_RESET" "$C_RESET"
	fi
	unset UI_CURRENT_STEP
}

ui_progress() {
	local msg="$1" cur="$2" total="$3"
	[ "${CALAGOPUS_QUIET:-0}" -eq 0 ] || return 0
	[ -t 1 ] || return 0
	local pct=0 bar len filled
	if [ "$total" -gt 0 ]; then pct=$((cur*100/total)); fi
	len=30; filled=$((pct*len/100))
	bar="$(printf '%0.s=' $(seq 1 "$filled" 2>/dev/null) 2>/dev/null)$(printf '%0.s ' $(seq 1 $((len-filled)) 2>/dev/null) 2>/dev/null)"
	printf '\r%s[%s] %3d%% %s%s' "$C_CYAN" "$bar" "$pct" "$msg" "$C_RESET"
	if [ "$cur" -ge "$total" ]; then printf '\n'; fi
}
