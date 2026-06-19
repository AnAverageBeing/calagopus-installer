#!/usr/bin/env bats
#
# tests/argparse.bats - Unit tests for the installer.sh argument parser.
# We extract parse_args without running main() by sourcing the file with
# a guard that prevents main execution.

setup() {
	CALAGOPUS_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	export CALAGOPUS_ROOT
	TMPDIR_TEST="$(mktemp -d)"
	export TMPDIR_TEST
	export CALAGOPUS_ETC_DIR="${TMPDIR_TEST}/etc/calagopus"
	export CALAGOPUS_LOG_DIR="${TMPDIR_TEST}/var/log/calagopus"
	export CALAGOPUS_LIB_DIR="${TMPDIR_TEST}/var/lib/calagopus-installer"
	export CALAGOPUS_CONFIG_FILE="${CALAGOPUS_ETC_DIR}/installer.env"
	export CALAGOPUS_STATE_FILE="${CALAGOPUS_LIB_DIR}/state.env"
	export CALAGOPUS_LOGFILE="${CALAGOPUS_LOG_DIR}/installer.log"
	export CALAGOPUS_INTERACTIVE=0
	export CALAGOPUS_QUIET=1
	export CALAGOPUS_NO_COLOR=1
	. "${CALAGOPUS_ROOT}/src/lib/common.sh"
	. "${CALAGOPUS_ROOT}/src/lib/log.sh"
	. "${CALAGOPUS_ROOT}/src/lib/ui.sh"
	. "${CALAGOPUS_ROOT}/src/lib/crypto.sh"
	. "${CALAGOPUS_ROOT}/src/lib/config.sh"
	. "${CALAGOPUS_ROOT}/src/lib/system.sh"
	. "${CALAGOPUS_ROOT}/src/lib/trap.sh"
	declare -gA CFG=()
	mkdir -p "$CALAGOPUS_LOG_DIR" "$CALAGOPUS_ETC_DIR" "$CALAGOPUS_LIB_DIR"
	# Source installer.sh to get parse_args, but suppress main() by defining
	# a no-op main before sourcing. We use a function shadow trick.
	main() { :; }
	# shellcheck source=/dev/null
	. "${CALAGOPUS_ROOT}/src/installer.sh"
}

teardown() {
	[ -n "${TMPDIR_TEST:-}" ] && rm -rf "${TMPDIR_TEST}"
}

@test "--action sets CALAGOPUS_ACTION" {
	parse_args --action doctor
	[ "$CALAGOPUS_ACTION" = "doctor" ]
}

@test "--target sets CFG[INSTALL_TARGET]" {
	parse_args --target full
	[ "${CFG[INSTALL_TARGET]}" = "full" ]
}

@test "--mode docker sets CFG[DEPLOY_MODE]" {
	parse_args --mode docker
	[ "${CFG[DEPLOY_MODE]}" = "docker" ]
}

@test "--channel nightly sets CFG[RELEASE_CHANNEL]" {
	parse_args --channel nightly
	[ "${CFG[RELEASE_CHANNEL]}" = "nightly" ]
}

@test "--non-interactive disables prompts" {
	parse_args --non-interactive
	[ "$CALAGOPUS_INTERACTIVE" -eq 0 ]
}

@test "--yes sets assume-yes" {
	parse_args --yes
	[ "$CALAGOPUS_ASSUME_YES" -eq 1 ]
}

@test "--dry-run sets dry-run flag" {
	parse_args --dry-run
	[ "$CALAGOPUS_DRY_RUN" -eq 1 ]
}
