# 🦆 calagopus-installer

[![Shellcheck](https://github.com/AnAverageBeing/calagopus-installer/actions/workflows/shellcheck.yml/badge.svg?style=flat-square)](https://github.com/AnAverageBeing/calagopus-installer/actions/workflows/shellcheck.yml)
[![Tests](https://github.com/AnAverageBeing/calagopus-installer/actions/workflows/tests.yml/badge.svg?style=flat-square)](https://github.com/AnAverageBeing/calagopus-installer/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Bash 4+](https://img.shields.io/badge/Bash-4%2B-1f425f.svg?style=flat-square)](https://www.gnu.org/software/bash/)
[![GitHub Release](https://img.shields.io/github/v/release/AnAverageBeing/calagopus-installer?style=flat-square)](https://github.com/AnAverageBeing/calagopus-installer/releases)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/AnAverageBeing/calagopus-installer?style=flat-square)](https://github.com/AnAverageBeing/calagopus-installer)
[![GitHub Issues](https://img.shields.io/github/issues/AnAverageBeing/calagopus-installer?style=flat-square)](https://github.com/AnAverageBeing/calagopus-installer/issues)
[![GitHub Stars](https://img.shields.io/github/stars/AnAverageBeing/calagopus-installer?style=flat-square)](https://github.com/AnAverageBeing/calagopus-installer)

> **Unofficial** installation and management scripts for [Calagopus](https://calagopus.com) Panel & Wings - a modern, Docker-first, ARM-friendly game server panel.

Inspired by [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer), built specifically for Calagopus' Rust-powered architecture.

---

## 🚀 Quick Start

### One-line installer (interactive)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh)
```

> ⚠️ **Root required** - Some systems need `sudo` before running this command.

### One-line non-interactive (automated)

```bash
# Full stack (Panel + Wings)
bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh) -- \
  --non-interactive --yes --action install_full --target full --mode docker --channel stable

# Panel only (native binary, without Docker)
bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh) -- \
  --non-interactive --yes --action install_panel_native --target panel --mode native --channel stable

# Wings only (Docker)
bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh) -- \
  --non-interactive --yes --action install_wings --target wings --mode docker \
  --wings-join-data "your-join-token-here"
```

---

## ✨ Features

<table>
<tr>
<td width="50%">

**Installation & Deployment**
- ✅ Automatic Panel + Wings setup
- ✅ Full Stack mode (AIO)
- ✅ Docker & Native binary modes
- ✅ Non-interactive automation
- ✅ Idempotent (safe to re-run)

</td>
<td width="50%">

**Operations**
- 🔄 Update & rollback (channel-aware)
- 💾 Backup & restore with retention
- 🔧 Repair mode (8 auto-fix probes)
- 📊 Status & health checks
- 🪵 Structured logging

</td>
</tr>
<tr>
<td width="50%">

**Security & Infrastructure**
- 🔒 SSL/TLS: Let's Encrypt, self-signed, Cloudflare Origin
- 🚪 Firewall: UFW, firewalld, nftables, iptables
- 🛡️ Secrets auto-redacted from logs
- 📁 Strict file permissions (0600)
- ⚡ Principle of least privilege

</td>
<td width="50%">

**Compatibility**
- 🐧 10+ Linux distros (Ubuntu, Debian, RHEL, Fedora, Arch, etc.)
- 🦾 Multi-architecture: x86_64, ARM64, armv7, riscv64, ppc64le
- 🥧 Raspberry Pi 3/4/5 support
- 🌍 Release channels: stable, beta, nightly
- ✅ Docker or binary deployment

</td>
</tr>
</table>

---

## 📋 Supported Platforms

### Operating Systems

| OS | Version | Support | Arch |
|:---|:--------|:--------|:-----|
| **Ubuntu** | 22.04, 24.04, 26.04 | ✅ Full | x86_64, ARM64 |
| **Debian** | 11, 12, 13 | ✅ Full | x86_64, ARM64 |
| **Rocky Linux** | 8, 9 | ✅ Full | x86_64, ARM64 |
| **AlmaLinux** | 8, 9 | ✅ Full | x86_64, ARM64 |
| **RHEL** | 8, 9 | ✅ Full | x86_64, ARM64 |
| **Fedora** | 38+ | ✅ Full | x86_64, ARM64 |
| **Arch Linux** | rolling | ✅ Full | x86_64, ARM64 |
| **openSUSE** | Tumbleweed, Leap 15.5+ | ✅ Full | x86_64, ARM64 |
| **Raspberry Pi OS** | 11+ | ✅ Full | ARM64 |
| **Other (Docker)** | Any | 🟡 Community | All |

### Architectures

| Arch | Support | Notes |
|:-----|:--------|:------|
| **x86_64 / amd64** | ✅ | Primary target |
| **aarch64 / arm64** | ✅ | Raspberry Pi 4/5, ARM servers |
| **armv7** | ✅ | Raspberry Pi 3 |
| **riscv64** | ✅ | Experimental |
| **ppc64le** | ✅ | POWER systems |

---

## 🎯 Installation Modes

| Mode | Setup | Best For |
|:-----|:------|:---------|
| **Docker AIO** | Panel + Wings in one container | Single-node, recommended for most |
| **Docker Standalone** | Panel only, Wings separate | Multi-node, distributed setups |
| **Native Binary** | Compiled Rust + systemd | Minimal footprint, no Docker |

### Release Channels

| Channel | Tag | Notes |
|:--------|:-----|:-------|
| **Stable** (recommended) | `:latest` / `:aio` | Production-ready, latest release |
| **Beta** | `:latest-pre` / `:heavy-pre` | New features, may have bugs |
| **Nightly** | `:nightly` / `:nightly-aio` | Development builds, unstable |

---

## 📖 Usage Guide

### Interactive Menu

Run the installer and choose your setup:

```bash
sudo bash src/installer.sh
```

**Available options:**

| # | Action | Description |
|:--|:-------|:------------|
| 1 | Install Panel Only (without Docker) | Deploy Calagopus Panel using native binaries + systemd |
| 2 | Install Panel+Wings (Full Stack) | Panel + Wings on one host via AIO Docker image |
| 3 | Install Panel Only (Docker) | Deploy Calagopus Panel using Docker Compose |
| 4 | Install Wings Only | Deploy Calagopus Wings node |
| 5 | Upgrade Installation | Update to latest release on your channel |
| 6 | Repair Installation | Auto-detect and fix common issues |
| 7 | Backup Installation | Create full backup bundle (DB + config) |
| 8 | Restore Installation | Restore from backup |
| 9 | Reconfigure Installation | Re-run setup wizard |
| 10 | Remove Installation | Full clean uninstall (containers, files, configs, optionally DB) |
| 11 | Show System Status | Health overview |

### CLI Flags

```bash
--action <action>           install_panel_native | install_panel_docker | install_wings | install_full | upgrade | repair | backup | restore | remove | status
--target <target>           panel | wings | full
--mode <mode>               docker | native
--channel <channel>         stable | beta | nightly
--non-interactive           Skip all prompts (use defaults)
--yes                       Assume 'yes' to all confirmations
--dry-run                   Show what would happen (no changes)
--verbose / --debug         More logging
--quiet                     Suppress non-error output
--no-color                  Disable colored output
--config <file>             Load config from env file
--wings-join-data <token>   Node join token for Wings
--version                   Show version
--help                      Show help
```

---

## 🛠️ Post-Install Management

After installation, use the `calagopus-installer` command:

```bash
# Status & Monitoring
calagopus-installer status       # Quick health overview
calagopus-installer doctor       # Deep health check (fails on issues)
calagopus-installer logs -f      # Follow installer logs (tail -f)
calagopus-installer logs 100     # Last 100 lines

# Operations
calagopus-installer upgrade      # Update to latest release
calagopus-installer repair       # Auto-detect and fix issues
calagopus-installer reconfigure  # Re-run setup wizard

# Backup & Restore
calagopus-installer backup       # Create full backup bundle
calagopus-installer restore      # Restore from backup (interactive)

# Cleanup
calagopus-installer remove       # Uninstall (interactive confirmation)
calagopus-installer version      # Show CLI version
calagopus-installer help         # Show help
```

### Scheduled Backups

Configure periodic backups with systemd timers:

```bash
# During install, configure:
BACKUP_SCHEDULE=daily       # hourly | daily | weekly | monthly
BACKUP_RETENTION=7          # Keep last N bundles
```

---

## 🔒 Security & Network

### Firewall Configuration

Automatic firewall setup with multiple backends:

| Backend | Distro | Default |
|:--------|:-------|:--------|
| **UFW** | Debian/Ubuntu/Arch | ✅ Preferred |
| **firewalld** | RHEL/Fedora/SUSE | ✅ Preferred |
| **nftables** | Any | ⚠️ Fallback |
| **iptables** | Any | ⚠️ Last resort |

**Default ports opened:**

```
22        TCP   SSH
8000      TCP   Panel HTTP
8443      TCP   Panel HTTPS
443       TCP   Wings
20000:20100 TCP Game server allocations
```

### SSL/TLS Options

| Option | Type | Best For | Requirements |
|:-------|:-----|:---------|:------------|
| **Let's Encrypt** ⭐ | Auto | Production | FQDN + ports 80/443 |
| **Self-signed** | Manual | Testing/Homelab | None (OpenSSL) |
| **Existing Certs** | Manual | Custom setup | fullchain.pem + privkey.pem |
| **Cloudflare Origin** | Auto | Cloudflare users | Cloudflare account |

Auto-renewal configured for Let's Encrypt with proxy reload hook.

---

## 📁 Project Structure

```
calagopus-installer/
├── 📄 install.sh                    curl bootstrap entrypoint
├── 📄 src/
│   ├── installer.sh                 Main orchestrator
│   ├── lib/                         Core libraries
│   │   ├── common.sh                Constants & shared state
│   │   ├── log.sh                   Structured logging + redaction
│   │   ├── ui.sh                    Terminal UI (colors, menus)
│   │   ├── crypto.sh                Secure credential generation
│   │   ├── config.sh                Config load/save/validate
│   │   ├── system.sh                Host capability detection
│   │   └── trap.sh                  Error handling & cleanup
│   ├── os/                          OS detection & per-family setup
│   │   ├── detect.sh                Distro detection
│   │   ├── debian.sh                Ubuntu/Debian repos
│   │   ├── rhel.sh                  RHEL/Rocky/Alma/Fedora
│   │   ├── arch.sh                  Arch Linux setup
│   │   └── suse.sh                  openSUSE setup
│   ├── dependencies/                Dependency provisioning
│   │   ├── manager.sh               Central facade
│   │   ├── docker.sh                Docker Engine + Compose
│   │   ├── postgres.sh              PostgreSQL
│   │   ├── redis.sh                 Redis / Valkey
│   │   ├── nginx.sh                 Nginx reverse proxy
│   │   ├── caddy.sh                 Caddy reverse proxy
│   │   ├── certbot.sh               Let's Encrypt
│   │   └── packages.sh              Helper utilities
│   ├── database/                    Database lifecycle
│   │   ├── postgres.sh              Provisioning (local/remote)
│   │   └── validate.sh              Connectivity & schema checks
│   ├── docker/                      Docker daemon config
│   ├── panel/                       Panel installation
│   ├── wings/                       Wings installation
│   ├── ssl/                         SSL/TLS lifecycle
│   ├── proxy/                       Nginx + Caddy config
│   ├── firewall/                    UFW/firewalld/nftables
│   ├── backup/                      Backup & restore bundles
│   ├── update/                      Upgrades & rollback
│   ├── repair/                      Auto-repair probes
│   ├── uninstall/                   Clean removal
│   └── monitoring/                  Status & health checks
├── 📄 scripts/cli.sh                Installed CLI shim
├── 📄 configs/defaults.env          Default configuration
├── 📄 templates/                    Config templates
├── 📄 tests/                        Bats unit tests
├── 📄 .github/workflows/            CI/CD pipelines
├── 📄 Vagrantfile                   Integration test VMs
└── 📄 LICENSE, CHANGELOG.md, etc.
```

---

## 🧪 Development

### Prerequisites

```bash
bash 4+          # Shell interpreter
shellcheck       # Linting
bats-core        # Unit testing
Vagrant          # Integration testing (optional)
```

### Testing Locally

**Quick test with Vagrant:**

```bash
vagrant up                    # All distributions
vagrant up ubuntu_jammy       # Single distro
vagrant ssh ubuntu_jammy      # SSH into box
sudo /vagrant/src/installer.sh
```

**Available test boxes:**
```
ubuntu_jammy (22.04)  |  ubuntu_noble (24.04)  |  debian_bookworm (12)
debian_trixie (13)    |  rockylinux_9          |  almalinux_9
fedora_40             |  archlinux
```

### Code Quality

```bash
# Lint all scripts
find . -type f -name '*.sh' -not -path './.git/*' -exec shellcheck -x {} +

# Run unit tests
bats tests/
```

### Creating a Release

1. Update `CHANGELOG.md` with release info
2. Bump `CALAGOPUS_INSTALLER_VERSION` in `src/lib/common.sh`
3. Commit: `git commit -m "Release vX.Y.Z"`
4. Tag: `git tag vX.Y.Z`
5. Push & create GitHub release (CI auto-attaches binaries)

---

## 💬 Support

### For installer issues:
👉 [Open an issue](https://github.com/AnAverageBeing/calagopus-installer/issues)

### For Calagopus support:
👉 [Join Discord](https://discord.gg/uSM8tvTxBV)

---

## 📄 License

[MIT](LICENSE) - see LICENSE file for details.

---

## 🙏 Acknowledgements

- [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer) - Original inspiration
- [Calagopus](https://github.com/calagopus) - The panel this installer deploys
- All contributors making open-source better

---

<div align="center">

**If you find this helpful, please consider starring the repo!**

[Report Issue](https://github.com/AnAverageBeing/calagopus-installer/issues) - [View Releases](https://github.com/AnAverageBeing/calagopus-installer/releases) - [Contributing](CONTRIBUTING.md)

</div>

---

## Donations

Donations are appreciated!

**Bitcoin:** `bc1qqdhanefhpfht66urta6yws03pc060gmz26k9dt`
