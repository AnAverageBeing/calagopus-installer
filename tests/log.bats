#!/usr/bin/env bats
#
# tests/log.bats - Unit tests for src/lib/log.sh, including secret redaction.

setup() {
	CALAGOPUS_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	export CALAGOPUS_ROOT
	TMPDIR_TEST="$(mktemp -d)"
	export TMPDIR_TEST
	# Override log paths BEFORE sourcing common.sh so it picks up our sandbox.
	export CALAGOPUS_LOG_DIR="${TMPDIR_TEST}/var/log/calagopus"
	export CALAGOPUS_LOGFILE="${CALAGOPUS_LOG_DIR}/installer.log"
	. "${CALAGOPUS_ROOT}/src/lib/common.sh"
	. "${CALAGOPUS_ROOT}/src/lib/log.sh"
	mkdir -p "$CALAGOPUS_LOG_DIR"
	log_init
}

teardown() {
	[ -n "${TMPDIR_TEST:-}" ] && rm -rf "${TMPDIR_TEST}"
}

@test "log_info writes to the log file" {
	log_info "test message"
	grep -q "test message" "$CALAGOPUS_LOGFILE"
}

@test "log_redact masks a known secret value" {
	declare -gA CFG=()
	CFG[APP_ENCRYPTION_KEY]="supersecret123"
	local redacted
	redacted="$(log_redact "the key is supersecret123 here")"
	[[ "$redacted" == *"**REDACTED**"* ]]
	[[ "$redacted" != *"supersecret123"* ]]
}

@test "log_redact scrubs inline postgresql:// credentials" {
	local redacted
	redacted="$(log_redact "connecting to postgresql://user:secretpw@db:5432/panel")"
	[[ "$redacted" != *"secretpw"* ]]
}

@test "log_warn goes to stderr without failing" {
	log_warn "warning test"
}

@test "log_die exits non-zero" {
	run log_die "fatal test"
	[ "$status" -eq 1 ]
}
