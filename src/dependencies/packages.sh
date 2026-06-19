#!/usr/bin/env bash
#
# src/dependencies/packages.sh - Small, optional helper packages.
#
# jq is used by a few export/import helpers and by the monitoring module for
# pretty status output. It is strictly optional - everything degrades cleanly
# when it is absent - so this never hard-fails.

if [ -n "${CALAGOPUS_LIB_DEPS_PACKAGES:-}" ]; then return 0; fi
CALAGOPUS_LIB_DEPS_PACKAGES=1

packages_install_jq_optional() {
	if command -v jq >/dev/null 2>&1; then return 0; fi
	case "$OS_FAMILY" in
		debian|rhel|arch|suse) os_pkg_install jq 2>/dev/null || log_warn "jq not available; JSON output will be hand-rolled" ;;
		*) log_debug "jq skipped on $OS_FAMILY" ;;
	esac
}
