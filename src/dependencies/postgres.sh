#!/usr/bin/env bash
#
# src/dependencies/postgres.sh - PostgreSQL server provisioning (install only).
#
# Installs the PostgreSQL server package via the OS family repo helper. The
# higher-level database/ module (create user/db, migrate, validate) builds on
# top of this. Idempotent: if a server is already running we leave it alone.
#
# Note: for the Docker deployment path we never install a host Postgres - the
# compose stack ships its own containerised Postgres. This module is only used
# by native (binary) panel installs that want a local DB.

if [ -n "${CALAGOPUS_LIB_DEPS_POSTGRES:-}" ]; then return 0; fi
CALAGOPUS_LIB_DEPS_POSTGRES=1

postgres_installed() {
	command -v psql >/dev/null 2>&1 || systemctl list-unit-files postgresql.service >/dev/null 2>&1
}

postgres_version() { psql --version 2>/dev/null | awk '{print $3}'; }

postgres_health() { systemctl is-active --quiet postgresql 2>/dev/null || pg_isready >/dev/null 2>&1; }

# Distro-specific package name + repo bootstrap.
_postgres_pkg() {
	case "$OS_FAMILY" in
		debian) printf 'postgresql' ;;
		rhel)   printf 'postgresql-server' ;;
		arch)   arch_pkg_name postgresql ;;
		suse)   printf 'postgresql-server' ;;
		*)      printf 'postgresql' ;;
	esac
}

postgres_install() {
	# Add upstream repo so we get a recent major version.
	case "$OS_FAMILY" in
		debian) debian_add_postgres_repo ;;
		rhel)   rhel_add_postgres_repo ;;
	esac
	local pkg; pkg="$(_postgres_pkg)"
	os_pkg_install "$pkg"

	# Initialise the cluster where the distro expects an explicit initdb.
	case "$OS_FAMILY" in
		rhel)
			system_as_root postgresql-setup --initdb 2>/dev/null \
				|| system_as_root /usr/pgsql-*/bin/postgresql-*-setup initdb 2>/dev/null || true
			;;
		arch)
			system_as_root su - postgres -c "initdb -D /var/lib/postgres/data" 2>/dev/null || true
			;;
	esac

	# Ensure simple md5/scram auth for local TCP (needed by DATABASE_URL).
	_postgres_configure_auth
	system_as_root systemctl enable --now postgresql 2>/dev/null \
		|| system_as_root systemctl enable --now postgresql-18 2>/dev/null \
		|| true
}

# Enable password auth on local host connections (idempotent, backs up first).
_postgres_configure_auth() {
	local conf=""
	for c in /etc/postgresql/*/main/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf /var/lib/postgres/data/pg_hba.conf; do
		[ -f "$c" ] && conf="$c" && break
	done
	[ -n "$conf" ] || { log_warn "pg_hba.conf not found; skipping auth tuning"; return 0; }
	config_backup_file "$conf" >/dev/null
	if ! grep -q "calagopus-installer" "$conf"; then
		system_as_root sed -i '1i# calagopus-installer: allow local password auth\nhost all all 127.0.0.1/32 scram-sha-256\nhost all all ::1/128 scram-sha-256\n' "$conf"
		system_as_root systemctl reload postgresql 2>/dev/null || true
	fi
}
