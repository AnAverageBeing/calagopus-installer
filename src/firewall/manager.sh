#!/usr/bin/env bash
#
# src/firewall/manager.sh - Firewall configuration across ufw/firewalld/nft/iptables.
#
# Detects which firewall tool is available (or installs the distro-preferred
# one), opens exactly the ports Calagopus needs, and enables safe defaults.
# The principle of least privilege is enforced: only panel HTTP/HTTPS, wings,
# SSH, and (optionally) the game-server port range are exposed.

if [ -n "${CALAGOPUS_LIB_FW_MANAGER:-}" ]; then return 0; fi
CALAGOPUS_LIB_FW_MANAGER=1

# Game server allocation range (defaults from Pterodactyl/Calagopus convention).
CALAGOPUS_GAME_PORT_START="${CALAGOPUS_GAME_PORT_START:-20000}"
CALAGOPUS_GAME_PORT_END="${CALAGOPUS_GAME_PORT_END:-20100}"

fw_detect_engine() {
	if [ -n "${CFG[FIREWALL_ENGINE]:-}" ]; then return 0; fi
	if command -v ufw >/dev/null 2>&1; then CFG[FIREWALL_ENGINE]="ufw"
	elif command -v firewall-cmd >/dev/null 2>&1; then CFG[FIREWALL_ENGINE]="firewalld"
	elif command -v nft >/dev/null 2>&1; then CFG[FIREWALL_ENGINE]="nftables"
	elif command -v iptables >/dev/null 2>&1; then CFG[FIREWALL_ENGINE]="iptables"
	else
		# Install a default based on distro family.
		case "$OS_FAMILY" in
			debian|arch) dep_provision ufw; CFG[FIREWALL_ENGINE]="ufw" ;;
			rhel|suse)   dep_provision firewalld; CFG[FIREWALL_ENGINE]="firewalld" ;;
			*) CFG[FIREWALL_ENGINE]="iptables" ;;
		esac
	fi
}

# Ports the panel needs exposed.
fw_panel_ports() {
	printf '%s\n' "${CALAGOPUS_PORTS[panel_http]}" "${CALAGOPUS_PORTS[panel_https]}" 22
}
# Ports wings needs exposed.
fw_wings_ports() {
	printf '%s\n' "${CALAGOPUS_PORTS[wings]}"
	seq "$CALAGOPUS_GAME_PORT_START" "$CALAGOPUS_GAME_PORT_END"
}

# ----------------------------------------------------------------------------
# ufw
# ----------------------------------------------------------------------------
fw_apply_ufw() {
	system_as_root ufw --force reset 2>/dev/null || true
	system_as_root ufw default deny incoming
	system_as_root ufw default allow outgoing
	local p
	for p in $(fw_panel_ports); do system_as_root ufw allow "$p"/tcp; done
	if [ "${CFG[INSTALL_TARGET]:-}" != "panel" ]; then
		for p in $(fw_wings_ports); do system_as_root ufw allow "$p"/tcp; done
	fi
	system_as_root ufw --force enable
	log_ok "ufw configured"
}

# ----------------------------------------------------------------------------
# firewalld
# ----------------------------------------------------------------------------
fw_apply_firewalld() {
	system_as_root systemctl enable --now firewalld 2>/dev/null || true
	local p
	for p in $(fw_panel_ports); do
		system_as_root firewall-cmd --permanent --add-port="${p}/tcp" 2>/dev/null || true
	done
	if [ "${CFG[INSTALL_TARGET]:-}" != "panel" ]; then
		for p in $(fw_wings_ports); do
			system_as_root firewall-cmd --permanent --add-port="${p}/tcp" 2>/dev/null || true
		done
		system_as_root firewall-cmd --permanent --add-port="${CALAGOPUS_GAME_PORT_START}-${CALAGOPUS_GAME_PORT_END}/tcp" 2>/dev/null || true
	fi
	system_as_root firewall-cmd --reload
	log_ok "firewalld configured"
}

# ----------------------------------------------------------------------------
# nftables
# ----------------------------------------------------------------------------
fw_apply_nftables() {
	local rules="/etc/nftables.d/calagopus.nft"
	system_as_root install -d -m0755 /etc/nftables.d
	system_as_root tee "$rules" >/dev/null <<EOF
table inet calagopus_filter {
	chain input {
		type filter hook input priority 0; policy drop;
		iif lo accept
		ct state established,related accept
		# panel + ssh
		$(for p in $(fw_panel_ports); do echo "tcp dport $p accept"; done)
		# wings + game ports
		$(if [ "${CFG[INSTALL_TARGET]:-}" != "panel" ]; then
			for p in $(fw_wings_ports); do echo "tcp dport $p accept"; done
		fi)
	}
	chain forward { type filter hook forward priority 0; policy drop; }
	chain output  { type filter hook output  priority 0; policy accept; }
}
EOF
	system_as_root nft -f "$rules" 2>/dev/null || true
	system_as_root systemctl enable nftables 2>/dev/null || true
	log_ok "nftables configured"
}

# ----------------------------------------------------------------------------
# iptables (fallback)
# ----------------------------------------------------------------------------
fw_apply_iptables() {
	system_as_root iptables -P INPUT DROP
	system_as_root iptables -P FORWARD DROP
	system_as_root iptables -P OUTPUT ACCEPT
	system_as_root iptables -A INPUT -i lo -j ACCEPT
	system_as_root iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
	local p
	for p in $(fw_panel_ports); do system_as_root iptables -A INPUT -p tcp --dport "$p" -j ACCEPT; done
	if [ "${CFG[INSTALL_TARGET]:-}" != "panel" ]; then
		for p in $(fw_wings_ports); do system_as_root iptables -A INPUT -p tcp --dport "$p" -j ACCEPT; done
	fi
	# persist
	if command -v netfilter-persistent >/dev/null 2>&1; then
		system_as_root netfilter-persistent save
	elif [ -d /etc/iptables ]; then
		system_as_root iptables-save > /etc/iptables/rules.v4
	fi
	log_ok "iptables configured"
}

# ----------------------------------------------------------------------------
# Public entry
# ----------------------------------------------------------------------------
fw_apply() {
	fw_detect_engine
	case "${CFG[FIREWALL_ENGINE]:-}" in
		ufw)        fw_apply_ufw ;;
		firewalld)  fw_apply_firewalld ;;
		nftables)   fw_apply_nftables ;;
		iptables)   fw_apply_iptables ;;
		none)       log_info "firewall configuration skipped"; return 0 ;;
		*) log_error "unknown firewall engine"; return 1 ;;
	esac
	config_mark_installed FIREWALL
}

# Quick connectivity self-test: is the panel port reachable locally?
fw_validate() {
	local port="${CFG[PANEL_PORT]:-${CALAGOPUS_PORTS[panel_http]}}"
	if command -v nc >/dev/null 2>&1; then
		if nc -z 127.0.0.1 "$port" 2>/dev/null; then
			log_ok "panel port ${port} reachable"
		else
			log_warn "panel port ${port} not yet reachable"
		fi
	fi
}
