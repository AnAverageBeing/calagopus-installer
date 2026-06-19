#!/usr/bin/env bats
#
# tests/crypto.bats - Unit tests for src/lib/crypto.sh.

setup() {
	CALAGOPUS_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
	export CALAGOPUS_ROOT
	TMPDIR_TEST="$(mktemp -d)"
	export TMPDIR_TEST
	. "${CALAGOPUS_ROOT}/src/lib/common.sh"
	. "${CALAGOPUS_ROOT}/src/lib/crypto.sh"
}

teardown() {
	[ -n "${TMPDIR_TEST:-}" ] && rm -rf "${TMPDIR_TEST}"
}

@test "crypto_rand_string produces a string of the requested length" {
	local s
	s="$(crypto_rand_string 32)"
	[ "${#s}" -eq 32 ]
}

@test "crypto_rand_string hex charset only contains hex chars" {
	local s
	s="$(crypto_rand_string 40 hex)"
	[[ "$s" =~ ^[0-9a-f]+$ ]]
}

@test "crypto_rand_string urlsafe charset contains only urlsafe chars" {
	local s
	s="$(crypto_rand_string 50 urlsafe)"
	[[ "$s" =~ ^[A-Za-z0-9_-]+$ ]]
}

@test "crypto_encryption_key is 32 chars alphanumeric" {
	local k
	k="$(crypto_encryption_key)"
	[ "${#k}" -eq 32 ]
	[[ "$k" =~ ^[A-Za-z0-9]+$ ]]
}

@test "crypto_pg_url builds a correct connection string" {
	local url
	url="$(crypto_pg_url user pass 127.0.0.1 5432 panel)"
	[ "$url" = "postgresql://user:pass@127.0.0.1:5432/panel" ]
}

@test "crypto_redis_url with password includes it" {
	local url
	url="$(crypto_redis_url secret 127.0.0.1 6379 0)"
	[ "$url" = "redis://:secret@127.0.0.1:6379/0" ]
}

@test "crypto_redis_url without password omits it" {
	local url
	url="$(crypto_redis_url "" 127.0.0.1 6379 0)"
	[ "$url" = "redis://127.0.0.1:6379/0" ]
}

@test "crypto_sha256_file hashes a known file" {
	printf 'hello\n' > "$TMPDIR_TEST/hello.txt"
	local h
	h="$(crypto_sha256_file "$TMPDIR_TEST/hello.txt")"
	[ "${#h}" -eq 64 ]
}
