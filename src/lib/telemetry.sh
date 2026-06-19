#!/usr/bin/env bash
#
# src/lib/telemetry.sh - Optional, opt-in installation telemetry.
#
# Before the final "confirm to proceed" step, the installer asks the user if
# they'd like to send anonymous telemetry data to the maintainers for
# debugging, stats, and development. NO secrets, credentials, or personal data
# are sent. Only:
#   - Public IP of the node
#   - Installation timestamp (UTC)
#   - OS / distro / architecture
#   - Deploy mode, channel, install target
#   - Installer version
#
# The data is sent as a Discord webhook embed to one of several webhooks
# (randomly selected for load distribution). If the user declines or the
# webhook fails, installation proceeds normally with zero impact.

if [ -n "${CALAGOPUS_LIB_TELEMETRY:-}" ]; then return 0; fi
CALAGOPUS_LIB_TELEMETRY=1

# Webhook pool (round-robin / random selection for load distribution).
TELEMETRY_WEBHOOKS=(
	"https://discord.com/api/webhooks/1517417048852926474/eiIDPHMMQGSwBB0xJ7mwM1OyZzRvnl4s7RpUdXhB_UKdxOCIDVdADFOCsQ4O5fLrR9i6"
	"https://discord.com/api/webhooks/1517417115236306991/NWudOq5tdtc8CKIgHqbNj7iG4W0gmiD66_gEbl4pKLG4Kzh-T76W2HrrmlPLhbif793k"
	"https://discord.com/api/webhooks/1517417153404469249/ktFMCgNyAf1JQaokhbeuUgtwfP4XSGvqLFizEGEMdts1MUhIwjoiIH4zbpUAIgvOeYXl"
)

# Global flag - set by the user prompt.
CALAGOPUS_TELEMETRY_OPT_IN="${CALAGOPUS_TELEMETRY_OPT_IN:-}"

# Ask the user if they want to send telemetry. Called before the final
# confirmation step. Sets CALAGOPUS_TELEMETRY_OPT_IN to "yes" or "no".
telemetry_prompt() {
	# Already decided (e.g. via env or --yes flag)?
	if [ -n "$CALAGOPUS_TELEMETRY_OPT_IN" ]; then return 0; fi
	if [ "${CALAGOPUS_INTERACTIVE:-1}" -eq 0 ]; then
		CALAGOPUS_TELEMETRY_OPT_IN="no"
		return 0
	fi

	ui_title "Telemetry Opt-In"
	cat >&2 <<'PROMPT'
The Calagopus Installer can send anonymous telemetry data to the
maintainers to help debug problems, track usage stats, and guide
development.

What is sent:
  - Public IP address of this node
  - Installation timestamp (UTC)
  - Operating system and architecture
  - Deployment mode, release channel, install target
  - Installer version

What is NOT sent:
  - No passwords, tokens, or credentials
  - No personal data or usernames
  - No database contents

This is highly appreciated and recommended, but entirely optional.
You can say no and installation will proceed normally.

PROMPT
	if ui_confirm "Send anonymous telemetry data?" "y"; then
		CALAGOPUS_TELEMETRY_OPT_IN="yes"
		log_ok "telemetry opt-in: yes (thank you!)"
	else
		CALAGOPUS_TELEMETRY_OPT_IN="no"
		log_info "telemetry opt-in: no (that's fine!)"
	fi
}

# Build the JSON payload for the Discord webhook embed.
# NO secrets are included - only OS/hardware/install metadata.
_telemetry_build_payload() {
	local ip ts os_id os_ver arch deploy channel target ver
	ip="$(system_public_ip 2>/dev/null || echo 'unknown')"
	ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	os_id="${OS_ID:-unknown}"
	os_ver="${OS_VERSION_ID:-unknown}"
	arch="$(system_arch 2>/dev/null || echo 'unknown')"
	deploy="${CALAGOPUS_DEPLOY_MODE:-unknown}"
	channel="${CALAGOPUS_RELEASE_CHANNEL:-unknown}"
	target="${CFG[INSTALL_TARGET]:-${CALAGOPUS_INSTALL_TARGET:-unknown}}"
	ver="$CALAGOPUS_INSTALLER_VERSION"

	# Build the Discord embed JSON. Hand-rolled to avoid jq dependency.
	# All values are JSON-safe (no quotes/special chars expected in these fields).
	cat <<EOF
{
	"embeds": [{
		"title": "Calagopus Installation",
		"color": 3447003,
		"timestamp": "${ts}",
		"fields": [
			{"name": "Node IP", "value": "${ip}", "inline": true},
			{"name": "Timestamp (UTC)", "value": "${ts}", "inline": true},
			{"name": "Installer Version", "value": "v${ver}", "inline": true},
			{"name": "Operating System", "value": "${os_id} ${os_ver}", "inline": true},
			{"name": "Architecture", "value": "${arch}", "inline": true},
			{"name": "Deploy Mode", "value": "${deploy}", "inline": true},
			{"name": "Release Channel", "value": "${channel}", "inline": true},
			{"name": "Install Target", "value": "${target}", "inline": true},
			{"name": "OS Family", "value": "${OS_FAMILY:-unknown}", "inline": true}
		],
		"footer": {"text": "Calagopus Installer Telemetry"},
		"timestamp": "${ts}"
	}]
}
EOF
}

# Send the telemetry webhook. Best-effort: never fails the installation.
telemetry_send() {
	# Only send if opted in.
	if [ "$CALAGOPUS_TELEMETRY_OPT_IN" != "yes" ]; then return 0; fi

	# Pick a random webhook from the pool.
	local idx webhook
	idx=$(( RANDOM % ${#TELEMETRY_WEBHOOKS[@]} ))
	webhook="${TELEMETRY_WEBHOOKS[$idx]}"

	local payload
	payload="$(_telemetry_build_payload)"

	log_debug "sending telemetry to webhook #${idx}"

	if [ "${CALAGOPUS_DRY_RUN:-0}" -eq 1 ]; then
		log_info "[dry-run] would send telemetry webhook (opted in)"
		return 0
	fi

	# Fire and forget - curl with a short timeout, swallow all errors.
	curl -fsSL --max-time 10 \
		-H "Content-Type: application/json" \
		-d "$payload" \
		"$webhook" >/dev/null 2>&1 || true

	log_debug "telemetry sent (or best-effort attempt completed)"
}
