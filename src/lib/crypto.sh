#!/usr/bin/env bash
#
# src/lib/crypto.sh - Secure random credential generation.
#
# Centralises every place the installer needs a secret so we never reach for
# `echo $RANDOM` or a hardcoded value. Falls back gracefully across platforms
# (openssl -> /dev/urandom -> awk) so it works on minimal containers and ARM
# SBCs alike. Output is always alphanumeric or URL-safe depending on the call.

if [ -n "${CALAGOPUS_LIB_CRYPTO:-}" ]; then return 0; fi
CALAGOPUS_LIB_CRYPTO=1

# Source of entropy preference order.
crypto_entropy_source() {
	if common_cmd_exists openssl; then printf 'openssl'; return 0; fi
	if [ -r /dev/urandom ]; then printf 'urandom'; return 0; fi
	printf 'awk'; return 0
}

# crypto_rand_bytes <count> -> base64 of N random bytes
crypto_rand_bytes() {
	local n="${1:-32}"
	if common_cmd_exists openssl; then
		openssl rand -base64 "$n" 2>/dev/null
	elif [ -r /dev/urandom ]; then
		head -c "$n" /dev/urandom | base64
	else
		# last-resort PRNG (not crypto-strong, but better than nothing)
		awk -v n="$n" 'BEGIN{srand(); for(i=0;i<n;i++) printf "%c", int(rand()*256)}' | base64
	fi
}

# crypto_rand_string <length> [charset] -> alphanumeric (default) string
# charset: alnum (default) | hex | urlsafe | ascii
crypto_rand_string() {
	local len="${1:-32}" charset="${2:-alnum}" chars
	case "$charset" in
		hex)     chars='0123456789abcdef' ;;
		urlsafe) chars='-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_' ;;
		ascii)   chars='!#$%&()*+,-./0-9:;<=>?@A-Z[]^_`a-z{|}~' ;;
		alnum|*) chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' ;;
	esac
	local out=""
	if [ -r /dev/urandom ]; then
		# Temporarily disable pipefail: head -c exits after reading enough
		# bytes, causing tr to receive SIGPIPE. Under `set -o pipefail`
		# this triggers ERR. The output is already correct at that point.
		set +o pipefail
		out="$(LC_ALL=C tr -dc "$chars" </dev/urandom 2>/dev/null | head -c "$len")"
		set -o pipefail
	fi
	if [ -z "$out" ] || [ "${#out}" -lt "$len" ]; then
		# fallback using openssl
		out=""
		local i c
		for ((i=0; i<len; i++)); do
			c=$(openssl rand -hex 1 2>/dev/null || echo "00")
			out+="${chars:$(( 16#$c % ${#chars} )):1}"
		done
	fi
	printf '%s' "$out"
}

# Convenience generators used across modules.
crypto_encryption_key() { crypto_rand_string 32 alnum; }        # APP_ENCRYPTION_KEY
crypto_db_password()    { crypto_rand_string 24 urlsafe; }      # postgres user pw
crypto_redis_password() { crypto_rand_string 24 urlsafe; }
crypto_token()          { crypto_rand_string 48 urlsafe; }      # generic API/node token
crypto_hex()            { crypto_rand_string "${1:-32}" hex; }

# Build a postgresql:// connection URL from components, masking nothing here
# (callers must avoid logging the result - log.sh redacts DATABASE_URL anyway).
crypto_pg_url() {
	local user="$1" pass="$2" host="$3" port="${4:-5432}" db="$5"
	printf 'postgresql://%s:%s@%s:%s/%s' "$user" "$pass" "$host" "$port" "$db"
}
crypto_redis_url() {
	local pass="${1:-}" host="${2:-127.0.0.1}" port="${3:-6379}" db="${4:-0}"
	if [ -n "$pass" ]; then
		printf 'redis://:%s@%s:%s/%s' "$pass" "$host" "$port" "$db"
	else
		printf 'redis://%s:%s/%s' "$host" "$port" "$db"
	fi
}

# Hash a file with sha256 (for verifying downloads / config fingerprints).
crypto_sha256_file() {
	local f="$1"
	if common_cmd_exists sha256sum; then sha256sum "$f" | awk '{print $1}'
	elif common_cmd_exists shasum; then shasum -a 256 "$f" | awk '{print $1}'
	elif common_cmd_exists openssl; then openssl dgst -sha256 "$f" | awk '{print $NF}'
	else return 1; fi
}
