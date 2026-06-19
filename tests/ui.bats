#!/usr/bin/env bats
#
# tests/ui.bats - Unit tests for src/lib/ui.sh prompt/menu helpers.
# All tests run with CALAGOPUS_INTERACTIVE=0 so prompts return defaults
# without blocking on stdin.

setup() {
	CALAGOPUS_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	export CALAGOPUS_ROOT
	. "${CALAGOPUS_ROOT}/src/lib/common.sh"
	. "${CALAGOPUS_ROOT}/src/lib/ui.sh"
	export CALAGOPUS_INTERACTIVE=0
	export CALAGOPUS_NO_COLOR=1
	export CALAGOPUS_QUIET=1
}

@test "ui_prompt_default returns the default in non-interactive mode" {
	[ "$(ui_prompt_default "q" "defval")" = "defval" ]
}

@test "ui_confirm returns 0 for default yes in non-interactive mode" {
	ui_confirm "q" "y"
}

@test "ui_confirm returns 1 for default no in non-interactive mode" {
	! ui_confirm "q" "n"
}

@test "ui_choice returns the default option in non-interactive mode" {
	local pick
	pick="$(ui_choice "q" "a|b|c" "b")"
	[ "$pick" = "b" ]
}

@test "ui_main_menu returns the configured action in non-interactive mode" {
	CALAGOPUS_ACTION="status"
	[ "$(ui_main_menu)" = "status" ]
}
