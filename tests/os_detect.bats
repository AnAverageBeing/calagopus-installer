#!/usr/bin/env bats
#
# tests/os_detect.bats - Unit tests for src/os/detect.sh detection logic.

setup() {
	CALAGOPUS_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	export CALAGOPUS_ROOT
	. "${CALAGOPUS_ROOT}/src/lib/common.sh"
	. "${CALAGOPUS_ROOT}/src/lib/log.sh"
	. "${CALAGOPUS_ROOT}/src/lib/ui.sh"
	. "${CALAGOPUS_ROOT}/src/lib/system.sh"
	. "${CALAGOPUS_ROOT}/src/os/detect.sh"
}

@test "os_detect sets OS_ID and OS_FAMILY" {
	os_detect
	[ -n "$OS_ID" ]
	[ -n "$OS_FAMILY" ]
}

@test "os_support_label returns a non-empty string" {
	os_detect
	local label; label="$(os_support_label)"
	[ -n "$label" ]
}

@test "os_setup_pkg_facade populates OS_PKGINSTALL for the current family" {
	os_detect
	os_setup_pkg_facade
	[ "${#OS_PKGINSTALL[@]}" -gt 0 ] || [ "$OS_FAMILY" = "unknown" ]
}
