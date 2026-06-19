#!/usr/bin/env bats
#
# tests/test_helper.bats - Shared test setup + helpers for the bats suite.
#
# Each test file sources this to get a clean CALAGOPUS_ROOT + library load
# helper. Tests are designed to run WITHOUT root and without touching the real
# filesystem layout (we override the install dirs to a temp location).

# Load order matters: common.sh defines globals the rest depend on.
load() {
	local f="$1"
	# shellcheck disable=SC1090
	. "${CALAGOPUS_ROOT:-$(dirname "$BATS_TEST_FILENAME")/..}/src/${f}.sh"
}

# Run once per test file.
setup() {
	CALAGOPUS_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	export CALAGOPUS_ROOT
	# Redirect installer paths to a sandbox so tests never touch the real host.
	TMPDIR_TEST="$(mktemp -d)"
	export TMPDIR_TEST
	export CALAGOPUS_ETC_DIR="${TMPDIR_TEST}/etc/calagopus"
	export CALAGOPUS_INSTALL_DIR="${TMPDIR_TEST}/var/lib/calagopus"
	export CALAGOPUS_PANEL_DIR="${CALAGOPUS_INSTALL_DIR}/panel"
	export CALAGOPUS_WINGS_DIR="${CALAGOPUS_INSTALL_DIR}/wings"
	export CALAGOPUS_LOG_DIR="${TMPDIR_TEST}/var/log/calagopus"
	export CALAGOPUS_BACKUP_DIR="${TMPDIR_TEST}/var/backups/calagopus"
	export CALAGOPUS_LIB_DIR="${TMPDIR_TEST}/var/lib/calagopus-installer"
	export CALAGOPUS_STATE_FILE="${CALAGOPUS_LIB_DIR}/state.env"
	export CALAGOPUS_CONFIG_FILE="${CALAGOPUS_ETC_DIR}/installer.env"
	export CALAGOPUS_LOGFILE="${CALAGOPUS_LOG_DIR}/installer.log"
	export CALAGOPUS_INTERACTIVE=0
	export CALAGOPUS_QUIET=1
	export CALAGOPUS_NO_COLOR=1
}

teardown() {
	[ -n "${TMPDIR_TEST:-}" ] && rm -rf "${TMPDIR_TEST}"
}
