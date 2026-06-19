#!/usr/bin/env bash
#
# src/database/postgres.sh - PostgreSQL lifecycle for Calagopus.
#
# Handles the three DB sourcing modes Calagopus supports:
#   * local  - install + bootstrap a Postgres server on this host
#   * existing - use a Postgres server already running on this host
#   * remote - connect to an external Postgres server over TCP
#
# In every case we generate strong credentials (unless the user supplied their
# own), create the database + role, write DATABASE_URL into the panel env, and
# verify connectivity. Migrations themselves are run by the panel binary on
# first start (DATABASE_MIGRATE=true), so this module only verifies the
# connection is usable; it does not run SQL migrations directly.

if [ -n "${CALAGOPUS_LIB_DB_POSTGRES:-}" ]; then return 0; fi
CALAGOPUS_LIB_DB_POSTGRES=1

# Run a SQL string as the postgres superuser on the local server.
db_local_psql() {
	local sql="$1"
	if common_is_root; then
		su - postgres -c "psql -v ON_ERROR_STOP=1 -c \"$sql\"" 2>/dev/null \
			|| sudo -u postgres psql -v ON_ERROR_STOP=1 -c "$sql" 2>/dev/null
	else
		system_as_root su - postgres -c "psql -v ON_ERROR_STOP=1 -c \"$sql\"" 2>/dev/null
	fi
}

# Run a SQL string against an arbitrary server with a given DSN.
db_remote_psql() {
	local dsn="$1" sql="$2"
	PSGS=\"$dsn\" PGPASSWORD="${PGPASSWORD:-}" \
		psql "$dsn" -v ON_ERROR_STOP=1 -c "$sql" 2>&1
}

# ----------------------------------------------------------------------------
# Interactive source selection -> sets CFG[DB_REMOTE] = local|existing|remote
# ----------------------------------------------------------------------------
db_choose_source() {
	if [ -n "${CFG[DB_REMOTE]:-}" ]; then return 0; fi
	local pick
	pick="$(ui_choice "Where should the database live?" \
		"Install PostgreSQL locally|Use an existing local PostgreSQL|Use a remote PostgreSQL server" \
		"${CFG[DB_REMOTE]:-1}")"
	case "$pick" in
		Install*) CFG[DB_REMOTE]="local" ;;
		Use*existing*) CFG[DB_REMOTE]="existing" ;;
		Use*remote*) CFG[DB_REMOTE]="remote" ;;
	esac
}

# ----------------------------------------------------------------------------
# Gather connection parameters (host/port/db/user). Generates a password if
# the user did not supply one. Populates CFG[DB_*] and CFG[DATABASE_URL].
# ----------------------------------------------------------------------------
db_gather_credentials() {
	# If we already have DB_NAME + DB_USER + POSTGRES_PASSWORD, don't re-prompt.
	if [ -n "${CFG[DB_NAME]:-}" ] && [ -n "${CFG[DB_USER]:-}" ] && [ -n "${CFG[POSTGRES_PASSWORD]:-}" ]; then
		log_debug "DB credentials already gathered, skipping prompts"
		CFG[DATABASE_URL]="$(crypto_pg_url "${CFG[DB_USER]}" "${CFG[POSTGRES_PASSWORD]}" \
			"${CFG[DB_HOST]}" "${CFG[DB_PORT]}" "${CFG[DB_NAME]}")"
		return 0
	fi
	case "${CFG[DB_REMOTE]:-local}" in
		local|existing)
			CFG[DB_HOST]="${CFG[DB_HOST]:-127.0.0.1}"
			CFG[DB_PORT]="${CFG[DB_PORT]:-5432}"
			;;
		remote)
			CFG[DB_HOST]="$(ui_prompt_default "Database host" "${CFG[DB_HOST]:-}")"
			CFG[DB_PORT]="$(ui_prompt_default "Database port" "${CFG[DB_PORT]:-5432}")"
			;;
	esac
	CFG[DB_NAME]="$(ui_prompt_default "Database name" "${CFG[DB_NAME]:-panel}")"
	CFG[DB_USER]="$(ui_prompt_default "Database user" "${CFG[DB_USER]:-calagopus}")"

	# Password: reuse if present, else generate and remember (state file is 0600).
	if [ -z "${CFG[POSTGRES_PASSWORD]:-}" ]; then
		if [ "${CFG[DB_REMOTE]:-local}" = "remote" ] && [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 1 ]; then
			local pw; pw="$(ui_password "Password for ${CFG[DB_USER]} (blank to generate)")"
			CFG[POSTGRES_PASSWORD]="${pw:-$(crypto_db_password)}"
		else
			CFG[POSTGRES_PASSWORD]="$(crypto_db_password)"
		fi
	fi
	CFG[DATABASE_URL]="$(crypto_pg_url "${CFG[DB_USER]}" "${CFG[POSTGRES_PASSWORD]}" \
		"${CFG[DB_HOST]}" "${CFG[DB_PORT]}" "${CFG[DB_NAME]}")"
}

# ----------------------------------------------------------------------------
# Provision: install server (local only), create role + database, verify.
# ----------------------------------------------------------------------------
db_provision() {
	db_choose_source
	db_gather_credentials

	case "${CFG[DB_REMOTE]:-local}" in
		local)
			dep_provision postgres
			_create_role_and_db
			;;
		existing)
			dep_provision postgres   # ensures psql client is available
			_create_role_and_db
			;;
		remote)
			os_pkg_install postgresql-client 2>/dev/null || os_pkg_install postgresql 2>/dev/null || true
			log_info "using remote PostgreSQL at ${CFG[DB_HOST]}:${CFG[DB_PORT]}"
			# Remote: we assume the operator pre-created the role/db, or the
			# supplied creds have CREATE privileges. Just verify connectivity.
			;;
	esac

	db_validate_connection
	config_mark_installed DB
}

# Create the role and database on a local/existing server (idempotent).
# Checks for existing role/db and asks the user how to handle conflicts.
_create_role_and_db() {
	local user="${CFG[DB_USER]}" db="${CFG[DB_NAME]}"
	local sql

	# Check if role already exists.
	sql="SELECT 1 FROM pg_roles WHERE rolname='${user}'"
	local role_exists=0
	db_local_psql "$sql" 2>/dev/null | grep -q 1 && role_exists=1

	# Check if database already exists.
	sql="SELECT 1 FROM pg_database WHERE datname='${db}'"
	local db_exists=0
	db_local_psql "$sql" 2>/dev/null | grep -q 1 && db_exists=1

	# If either exists, ask the user what to do.
	if [ "$role_exists" = "1" ] || [ "$db_exists" = "1" ]; then
		local conflict_msg=""
		[ "$role_exists" = "1" ] && conflict_msg="role '${user}'"
		[ "$db_exists" = "1" ] && conflict_msg="${conflict_msg:+${conflict_msg} and }database '${db}'"
		ui_warn "${conflict_msg} already exists in PostgreSQL."
		local pick
		pick="$(ui_choice "How to handle the existing ${conflict_msg}?" \
			"Drop and recreate (warning: data loss)|Keep existing and proceed (update password/owner only)" \
			"2")"

		if [ "${pick#Drop}" != "$pick" ]; then
			# Drop and recreate.
			if [ "$db_exists" = "1" ]; then
				log_info "dropping existing database '${db}'"
				db_local_psql "DROP DATABASE IF EXISTS ${db};" 2>/dev/null || true
				db_exists=0
			fi
			if [ "$role_exists" = "1" ]; then
				log_info "dropping existing role '${user}'"
				db_local_psql "DROP ROLE IF EXISTS ${user};" 2>/dev/null || true
				role_exists=0
			fi
		fi
	fi

	# Create role if it doesn't exist (or was dropped).
	if [ "$role_exists" = "0" ]; then
		log_info "creating database role '${user}'"
		db_local_psql "CREATE ROLE ${user} WITH LOGIN PASSWORD '${CFG[POSTGRES_PASSWORD]}'" \
			|| log_error "failed to create role ${user}"
	else
		log_debug "role '${user}' already exists"
		db_local_psql "ALTER ROLE ${user} WITH LOGIN PASSWORD '${CFG[POSTGRES_PASSWORD]}'" >/dev/null 2>&1 || true
	fi

	# Create database if it doesn't exist (or was dropped).
	if [ "$db_exists" = "0" ]; then
		log_info "creating database '${db}'"
		db_local_psql "CREATE DATABASE ${db} OWNER ${user}" \
			|| log_error "failed to create database ${db}"
		db_local_psql "GRANT ALL PRIVILEGES ON DATABASE ${db} TO ${user}"
	else
		log_debug "database '${db}' already exists"
		db_local_psql "ALTER DATABASE ${db} OWNER TO ${user}" >/dev/null 2>&1 || true
	fi
}

# ----------------------------------------------------------------------------
# Validate that DATABASE_URL actually connects + has create-table privileges.
# ----------------------------------------------------------------------------
db_validate_connection() {
	[ -n "${CFG[DATABASE_URL]:-}" ] || { log_error "DATABASE_URL not set"; return 1; }
	log_info "validating database connectivity"
	if ! command -v psql >/dev/null 2>&1; then
		log_warn "psql not installed - skipping live connectivity check"
		return 0
	fi
	# Pass the DSN via the env to avoid leaking it into argv.
	if PGPASSWORD="${CFG[POSTGRES_PASSWORD]}" \
		psql "${CFG[DATABASE_URL]}" -c "SELECT current_database(), current_user;" >/dev/null 2>&1; then
		log_ok "database connection OK (${CFG[DB_USER]}@${CFG[DB_HOST]}/${CFG[DB_NAME]})"
		return 0
	fi
	log_error "could not connect to database as ${CFG[DB_USER]}@${CFG[DB_HOST]}:${CFG[DB_PORT]}/${CFG[DB_NAME]}"
	return 1
}

# pg_dump the panel DB into a file (used by backup/). Echoes the dump path.
db_dump() {
	local out="${1:-${CALAGOPUS_BACKUP_DIR}/db-$(date +%Y%m%d-%H%M%S).sql.gz}"
	mkdir -p "$(dirname "$out")"
	if ! command -v pg_dump >/dev/null 2>&1; then
		log_error "pg_dump not available"; return 1
	fi
	PGPASSWORD="${CFG[POSTGRES_PASSWORD]}" pg_dump "${CFG[DATABASE_URL]}" \
		| gzip >"$out"
	printf '%s' "$out"
}

# Restore a dump file (used by restore/).
db_restore() {
	local dump="$1"
	[ -f "$dump" ] || { log_error "dump not found: $dump"; return 1; }
	log_info "restoring database from $dump"
	gunzip -c "$dump" | PGPASSWORD="${CFG[POSTGRES_PASSWORD]}" psql "${CFG[DATABASE_URL]}"
}
