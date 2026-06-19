#!/usr/bin/env bash
#
# src/database/validate.sh - Standalone DB health / sanity checks.
#
# Used by repair/ and monitoring/doctor to answer "is the DB reachable and is
# the schema present?" without re-running any provisioning logic.

if [ -n "${CALAGOPUS_LIB_DB_VALIDATE:-}" ]; then return 0; fi
CALAGOPUS_LIB_DB_VALIDATE=1

db_reachable() {
	[ -n "${CFG[DATABASE_URL]:-}" ] || return 1
	command -v psql >/dev/null 2>&1 || return 2
	PGPASSWORD="${CFG[POSTGRES_PASSWORD]:-}" psql "${CFG[DATABASE_URL]}" \
		-c "SELECT 1" >/dev/null 2>&1
}

# Check that the panel's migrations have been applied. Calagopus stores its
# schema in the public namespace; we look for a known core table.
db_schema_present() {
	db_reachable || return 1
	local table="${1:-users}"
	PGPASSWORD="${CFG[POSTGRES_PASSWORD]:-}" psql "${CFG[DATABASE_URL]}" -tAc \
		"SELECT to_regclass('public.${table}')" 2>/dev/null | grep -q .
}

db_local_service_active() {
	systemctl is-active --quiet postgresql 2>/dev/null \
		|| systemctl is-active --quiet postgresql-18 2>/dev/null
}
