#!/usr/bin/env bats
#
# tests/common.bats - Unit tests for src/lib/common.sh helpers.

setup() {
	CALAGOPUS_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	export CALAGOPUS_ROOT
	. "${CALAGOPUS_ROOT}/src/lib/common.sh"
}

@test "common_is_root reflects uid" {
	if [ "$(id -u)" -eq 0 ]; then
		common_is_root
	else
		! common_is_root
	fi
}

@test "common_is_yes accepts y/yes/1/true case-insensitively" {
	common_is_yes "y"
	common_is_yes "YES"
	common_is_yes "1"
	common_is_yes "true"
	common_is_yes "True"
	! common_is_yes "n"
	! common_is_yes "no"
	! common_is_yes ""
}

@test "common_default returns value when set, fallback when empty" {
	[ "$(common_default "x" "y")" = "x" ]
	[ "$(common_default "" "y")" = "y" ]
}

@test "common_cmd_exists finds bash" {
	common_cmd_exists bash
	! common_cmd_exists definitely-not-a-real-cmd-xyz
}
