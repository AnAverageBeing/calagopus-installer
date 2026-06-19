#!/usr/bin/env bats
#
# tests/config.bats - Unit tests for src/lib/config.sh load/save/validate.

setup() {
	CALAGOPUS_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	export CALAGOPUS_ROOT
	TMPDIR_TEST="$(mktemp -d)"
	export TMPDIR_TEST
	export CALAGOPUS_ETC_DIR="${TMPDIR_TEST}/etc/calagopus"
	export CALAGOPUS_LIB_DIR="${TMPDIR_TEST}/var/lib/calagopus-installer"
	export CALAGOPUS_CONFIG_FILE="${CALAGOPUS_ETC_DIR}/installer.env"
	export CALAGOPUS_STATE_FILE="${CALAGOPUS_LIB_DIR}/state.env"
	. "${CALAGOPUS_ROOT}/src/lib/common.sh"
	. "${CALAGOPUS_ROOT}/src/lib/log.sh"
	. "${CALAGOPUS_ROOT}/src/lib/crypto.sh"
	. "${CALAGOPUS_ROOT}/src/lib/config.sh"
	declare -gA CFG=()
	mkdir -p "$CALAGOPUS_ETC_DIR" "$CALAGOPUS_LIB_DIR"
}

teardown() {
	[ -n "${TMPDIR_TEST:-}" ] && rm -rf "${TMPDIR_TEST}"
}

@test "config_save_file writes a KEY='value' file" {
	CFG[FOO]="bar"
	config_save_file "${TMPDIR_TEST}/cfg.env" FOO
	grep -q "^FOO='bar'$" "${TMPDIR_TEST}/cfg.env"
}

@test "config_load_file round-trips a saved file" {
	CFG[BAZ]="qux"
	config_save_file "${TMPDIR_TEST}/cfg.env" BAZ
	unset 'CFG[BAZ]'
	config_load_file "${TMPDIR_TEST}/cfg.env"
	[ "${CFG[BAZ]}" = "qux" ]
}

@test "config_load_file skips comments and blanks" {
	cat > "${TMPDIR_TEST}/cfg.env" <<'EOF'
# a comment

REAL='value'
EOF
	config_load_file "${TMPDIR_TEST}/cfg.env"
	[ "${CFG[REAL]}" = "value" ]
}

@test "config_is_yes wrapper works for installed flags" {
	CFG[INSTALLED_PANEL]="yes"
	config_is_installed PANEL
	CFG[INSTALLED_PANEL]="no"
	! config_is_installed PANEL
}

@test "config_validate rejects bad release channel" {
	CFG[RELEASE_CHANNEL]="bogus"
	run config_validate
	[ "$status" -ne 0 ]
}

@test "config_validate rejects bad FQDN" {
	CFG[PANEL_FQDN]="not a hostname"
	run config_validate
	[ "$status" -ne 0 ]
}

@test "config_export_json produces valid-looking JSON" {
	CFG[DEPLOY_MODE]="docker"
	local json
	json="$(config_export_json)"
	[[ "$json" == *'"DEPLOY_MODE":"docker"'* ]]
	[[ "$json" == "{"*"}" ]]
}
