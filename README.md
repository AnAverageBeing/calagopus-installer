# calagopus-installer

[![Shellcheck](https://github.com/AnAverageBeing/calagopus-installer/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/AnAverageBeing/calagopus-installer/actions/workflows/shellcheck.yml)
[![Tests](https://github.com/AnAverageBeing/calagopus-installer/actions/workflows/tests.yml/badge.svg)](https://github.com/AnAverageBeing/calagopus-installer/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![made-with-bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![Release](https://img.shields.io/github/v/release/AnAverageBeing/calagopus-installer)](https://github.com/AnAverageBeing/calagopus-installer/releases)

Unofficial installation and management scripts for the [Calagopus](https://calagopus.com) Panel & Wings. Works with the latest version of Calagopus!

This script is not associated with the official Calagopus Project. For more information about Calagopus itself, visit [calagopus.com](https://calagopus.com) or the [GitHub repository](https://github.com/calagopus).

Inspired by the [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer) project, but built specifically for Calagopus' Docker-first, ARM-friendly, Rust-powered architecture.

## Features

- **Automatic installation** of the Calagopus Panel (dependencies, database, Redis/Valkey, reverse proxy, SSL).
- **Automatic installation** of Calagopus Wings (Docker, container runtime, systemd service).
- **Full Stack mode** — Panel + Wings on a single host via the AIO Docker image.
- **Docker and Native (binary) deployment modes** — pick what fits your infrastructure.
- **Idempotent** — safe to re-run; won't clobber an existing installation.
- **Non-interactive mode** for automation / CI / provisioning scripts.
- **Automatic dependency detection and installation** — Docker, PostgreSQL, Redis/Valkey, Nginx, Caddy, Certbot, firewall tooling.
- **SSL/TLS** — Let's Encrypt, self-signed, existing certificates, or Cloudflare Origin certificates, with automatic renewal monitoring.
- **Reverse proxy** — Nginx or Caddy with WebSocket support and security headers.
- **Firewall configuration** — UFW, firewalld, nftables, or iptables, with least-privilege port exposure.
- **Backup & restore** — full bundle (DB, config, app files) with retention policies and scheduled backups.
- **Update & rollback** — channel-aware upgrades with automatic pre-upgrade backup and health-check-driven rollback.
- **Repair mode** — detects and fixes missing files, broken services, database issues, Docker issues, permissions, SSL, and proxy config.
- **Monitoring** — `calagopus-installer status | doctor | logs` commands.
- **Security** — secrets never logged (automatically redacted), config files mode 0600, principle of least privilege throughout.
- **ARM64 support** — runs on Raspberry Pi and other ARM64 platforms.
- **Release channels** — stable, beta, and nightly.

## Help and support

For help and support regarding the script itself and **not the official Calagopus project**, please [open an issue](https://github.com/AnAverageBeing/calagopus-installer/issues).

For Calagopus support, join the [Calagopus Discord](https://discord.gg/uSM8tvTxBV).

## Supported installations

List of supported installation setups for Panel and Wings.

### Supported Panel and Wings operating systems

| Operating System | Version | Supported | Architecture |
|-------------------|---------|-----------|--------------|
| **Ubuntu** | 20.04 | 🔴 \* | x86_64, ARM64 |
| | 22.04 | ✅ | x86_64, ARM64 |
| | 24.04 | ✅ | x86_64, ARM64 |
| | 26.04 | ✅ | x86_64, ARM64 |
| **Debian** | 10 | 🔴 \* | x86_64, ARM64 |
| | 11 | ✅ | x86_64, ARM64 |
| | 12 | ✅ | x86_64, ARM64 |
| | 13 | ✅ | x86_64, ARM64 |
| **Rocky Linux** | 8 | ✅ | x86_64, ARM64 |
| | 9 | ✅ | x86_64, ARM64 |
| **AlmaLinux** | 8 | ✅ | x86_64, ARM64 |
| | 9 | ✅ | x86_64, ARM64 |
| **RHEL** | 8 | ✅ | x86_64, ARM64 |
| | 9 | ✅ | x86_64, ARM64 |
| **Fedora** | 38+ | ✅ | x86_64, ARM64 |
| **Arch Linux** | rolling | ✅ | x86_64, ARM64 |
| **openSUSE** | Tumbleweed | ✅ | x86_64, ARM64 |
| | Leap 15.5+ | ✅ | x86_64, ARM64 |
| **Raspberry Pi OS** | 11+ | ✅ | ARM64 |
| **Other (Docker present)** | - | 🟡 Community | All |

*\* Indicates an operating system and release that previously was supported by Calagopus but is now end-of-life.*

### Supported architectures

| Architecture | Supported | Notes |
|--------------|-----------|-------|
| x86_64 / amd64 | ✅ | Primary target |
| aarch64 / arm64 | ✅ | Raspberry Pi 4/5, ARM servers |
| armv7 | ✅ | Raspberry Pi 3 |
| riscv64 | ✅ | Experimental |
| ppc64le | ✅ | POWER systems |

### Installation modes

| Mode | Description | Best for |
|------|-------------|----------|
| **Docker AIO** | Panel + Wings in one container | Single-node setups (recommended) |
| **Docker Standalone** | Panel only, Wings on separate hosts | Multi-node / split-host setups |
| **Native (Binary)** | Compiled Rust binaries + systemd | Minimal footprint, no Docker for Panel |

### Release channels

| Channel | Image tag | Description |
|---------|-----------|-------------|
| **Stable** | `:latest` / `:aio` | Latest stable release. Recommended for production. |
| **Beta** | `:latest-pre` / `:heavy-pre` | Pre-release with new features. May contain bugs. |
| **Nightly** | `:nightly` / `:nightly-aio` | Development builds. Not for production. |

## Using the installation scripts

To use the installation scripts, simply run this command as root. The script will show you an interactive menu where you can choose whether to install just the Panel, just Wings, or the Full Stack.

```bash
bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh)
```

> **Note:** On some systems, it's required to be already logged in as root before executing the one-line command (where `sudo` is in front of the command does not work).

### Non-interactive installation

For automation, CI/CD pipelines, or provisioning scripts:

```bash
# Full stack Docker install (Panel + Wings AIO)
bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh) -- \
  --non-interactive --yes \
  --action install_full --target full --mode docker --channel stable

# Panel only, native binary
bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh) -- \
  --non-interactive --yes \
  --action install_panel --target panel --mode native --channel stable

# Wings only, Docker
bash <(curl -sSL https://raw.githubusercontent.com/AnAverageBeing/calagopus-installer/main/install.sh) -- \
  --non-interactive --yes \
  --action install_wings --target wings --mode docker \
  --wings-join-data "your-join-token-here"
```

### Running from a clone

If you have cloned this repository, run the modular installer directly:

```bash
sudo bash src/installer.sh
```

## Installation options

The interactive menu offers the following options:

| # | Option | Description |
|---|--------|-------------|
| 1 | Install Panel | Deploy the Calagopus Panel (Docker or native) |
| 2 | Install Wings | Deploy Calagopus Wings on a node |
| 3 | Install Full Stack | Panel + Wings on a single host (AIO) |
| 4 | Upgrade Installation | Upgrade to the latest release on your channel |
| 5 | Repair Installation | Detect and fix common issues |
| 6 | Backup Installation | Create a full backup bundle |
| 7 | Restore Installation | Restore from a backup bundle |
| 8 | Reconfigure Installation | Re-run config prompts and restart services |
| 9 | Remove Installation | Uninstall Calagopus cleanly |
| 10 | Show System Status | At-a-glance health overview |

### CLI flags

| Flag | Description |
|------|-------------|
| `--action <a>` | `install_panel`, `install_wings`, `install_full`, `upgrade`, `repair`, `backup`, `restore`, `reconfigure`, `remove`, `status`, `doctor`, `logs` |
| `--target <t>` | `panel`, `wings`, `full` |
| `--mode <m>` | `docker`, `native` |
| `--channel <c>` | `stable`, `beta`, `nightly` |
| `--non-interactive` | Never prompt (use defaults / stored config) |
| `--yes` | Assume yes to all confirmations |
| `--dry-run` | Show what would happen without making changes |
| `--verbose` / `--debug` | More logging |
| `--quiet` | Suppress non-error output |
| `--no-color` | Disable coloured output |
| `--config <file>` | Import config from an env file before running |
| `--wings-join-data <s>` | Node join token for non-interactive Wings setup |
| `--version` | Show installer version |
| `--help` | Show help |

## Post-install management

After installation, a `calagopus-installer` command is installed on your system:

```bash
calagopus-installer status       # system status overview
calagopus-installer doctor       # deep health check (exit non-zero if issues)
calagopus-installer logs -f      # follow installer logs (tail -f)
calagopus-installer logs 100     # show last 100 log lines
calagopus-installer repair       # detect and repair common issues
calagopus-installer backup       # create a backup bundle
calagopus-installer restore      # restore from a backup bundle (interactive)
calagopus-installer upgrade      # upgrade panel + wings to latest release
calagopus-installer reconfigure  # re-run config prompts and restart services
calagopus-installer remove       # uninstall Calagopus (interactive confirmation)
calagopus-installer version      # show CLI version
calagopus-installer help         # show help
```

### Scheduled backups

The installer can set up a systemd timer for periodic backups:

```bash
# During install, set the schedule:
# BACKUP_SCHEDULE=hourly|daily|weekly|monthly  (default: daily)
# BACKUP_RETENTION=7                           (keep last N bundles)
```

## Firewall setup

The installation scripts can install and configure a firewall for you. The script will ask whether you want this or not. It is highly recommended to opt-in for the automatic firewall setup.

Supported firewall backends:

| Backend | Distro family | Default? |
|---------|---------------|----------|
| UFW | Debian / Ubuntu / Arch | ✅ |
| firewalld | RHEL / Fedora / SUSE | ✅ |
| nftables | Any | Fallback |
| iptables | Any | Last resort |

Ports opened by default:

| Port | Protocol | Component |
|------|----------|-----------|
| 22 | TCP | SSH |
| 8000 | TCP | Panel HTTP |
| 8443 | TCP | Panel HTTPS |
| 443 | TCP | Wings |
| 20000-20100 | TCP | Game server allocations |

## SSL/TLS setup

The installer supports four SSL modes:

| Mode | Description | Requirements |
|------|-------------|--------------|
| **Let's Encrypt** (recommended) | Free, automatic TLS via Certbot | FQDN resolving to your server, ports 80/443 open |
| **Self-signed** | OpenSSL-generated certificate | None (good for homelabs / testing) |
| **Existing certificates** | Use certs you already have | Paths to fullchain.pem + privkey.pem |
| **Cloudflare Origin** | Cloudflare Origin Certificate | Cloudflare account, FQDN behind Cloudflare proxy |

Automatic renewal is configured for Let's Encrypt certificates, with a post-renew hook that reloads the reverse proxy.

## Project structure

```
calagopus-installer/
├── install.sh                     # curl bootstrap entrypoint
├── src/
│   ├── installer.sh               # main orchestrator (menu, arg parsing, dispatch)
│   ├── lib/                       # core libraries
│   │   ├── common.sh              #   constants, defaults, shared state
│   │   ├── log.sh                 #   structured logging + secret redaction
│   │   ├── ui.sh                  #   terminal UI: colors, prompts, menus, progress
│   │   ├── crypto.sh              #   secure credential generation
│   │   ├── config.sh              #   configuration load/save/validate
│   │   ├── system.sh              #   host capability checks (arch, ram, disk)
│   │   └── trap.sh                #   error/cleanup/interrupt handling
│   ├── os/                        # OS detection + per-family modules
│   │   ├── detect.sh              #   distro detection + supported-distro matrix
│   │   ├── debian.sh              #   Ubuntu/Debian repo setup
│   │   ├── rhel.sh                #   RHEL/Rocky/Alma/Fedora repo setup
│   │   ├── arch.sh                #   Arch Linux prep
│   │   └── suse.sh                #   openSUSE prep
│   ├── dependencies/              # dependency provisioning
│   │   ├── manager.sh             #   central facade
│   │   ├── docker.sh              #   Docker Engine + Compose
│   │   ├── postgres.sh            #   PostgreSQL server
│   │   ├── redis.sh               #   Redis / Valkey
│   │   ├── nginx.sh               #   Nginx
│   │   ├── caddy.sh               #   Caddy
│   │   ├── certbot.sh             #   Certbot (Let's Encrypt)
│   │   └── packages.sh            #   optional helper packages (jq)
│   ├── database/                  # database lifecycle
│   │   ├── postgres.sh            #   local/existing/remote provisioning
│   │   └── validate.sh            #   connectivity + schema checks
│   ├── docker/                    # Docker configuration
│   │   └── configure.sh           #   daemon.json, networks, compose helpers
│   ├── panel/                     # Panel installation
│   │   └── install.sh             #   docker + native paths
│   ├── wings/                     # Wings installation
│   │   └── install.sh             #   docker + native paths
│   ├── ssl/                       # SSL/TLS management
│   │   └── manager.sh             #   letsencrypt/selfsigned/existing/cloudflare
│   ├── proxy/                     # reverse proxy
│   │   └── manager.sh             #   nginx + caddy config generation
│   ├── firewall/                  # firewall configuration
│   │   └── manager.sh             #   ufw/firewalld/nftables/iptables
│   ├── backup/                    # backup + restore
│   │   └── manager.sh             #   bundle creation, retention, scheduled timer
│   ├── update/                    # upgrade + rollback
│   │   └── manager.sh             #   channel-aware upgrades, auto-rollback
│   ├── repair/                    # repair mode
│   │   └── manager.sh             #   8 repair probes
│   ├── uninstall/                 # clean removal
│   │   └── manager.sh             #   stop, remove, optional DB drop
│   └── monitoring/                # status / doctor / logs
│       └── manager.sh             #   health checks + resource usage
├── scripts/
│   └── cli.sh                     # installed `calagopus-installer` CLI shim
├── configs/
│   └── defaults.env               # default configuration profile
├── templates/                     # configuration templates
│   ├── env/                       #   panel.env.tmpl
│   ├── systemd/                   #   service + timer units
│   ├── nginx/                     #   panel.conf.tmpl
│   ├── caddy/                     #   Caddyfile.tmpl
│   ├── docker/                    #   compose files
│   └── sql/                       #   database init SQL
├── tests/                         # bats unit tests
├── .github/workflows/             # CI (shellcheck + bats + release)
├── Vagrantfile                    # integration test boxes
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
└── LICENSE
```

## Development & Ops

### Prerequisites

- [bash](https://www.gnu.org/software/bash/) 4+
- [shellcheck](https://www.shellcheck.net/) (for linting)
- [bats-core](https://github.com/bats-core/bats-core) (for unit tests)
- [Vagrant](https://www.vagrantup.com/) + VirtualBox (for integration testing)

### Testing the script locally

We use [Vagrant](https://www.vagrantup.com) for integration testing. With Vagrant, you can quickly get a fresh machine up and running to test the script.

If you want to test the script on all supported distributions in one go:

```bash
vagrant up
```

If you only want to test a specific distribution:

```bash
vagrant up ubuntu_jammy
```

Available test boxes:

- `ubuntu_jammy` (Ubuntu 22.04)
- `ubuntu_noble` (Ubuntu 24.04)
- `debian_bookworm` (Debian 12)
- `debian_trixie` (Debian 13)
- `rockylinux_9` (Rocky Linux 9)
- `almalinux_9` (AlmaLinux 9)
- `fedora_40` (Fedora 40)
- `archlinux` (Arch Linux)

Then SSH into the box and run the installer:

```bash
vagrant ssh ubuntu_jammy
sudo /vagrant/src/installer.sh
```

The project directory is mounted at `/vagrant` so you can modify the script locally and test changes immediately.

### Linting

```bash
# Lint all shell files
shellcheck install.sh src/**/*.sh scripts/*.sh

# Or use the CI command:
find . -type f -name '*.sh' -not -path './.git/*' -exec shellcheck -x {} +
```

### Unit tests

```bash
bats tests/
```

### Creating a release

1. Update `CHANGELOG.md` with the release date and tag.
2. Bump `CALAGOPUS_INSTALLER_VERSION` in `src/lib/common.sh` and `SCRIPT_RELEASE` in `install.sh`.
3. Push a commit with the message `Release vX.Y.Z`.
4. Tag `vX.Y.Z` and create a GitHub release. The `release.yml` workflow will attach `src/installer.sh` as `installer.sh` so the bootstrap can fetch it as a release asset.

## Contributing

Pull requests are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first. All code must pass `shellcheck` and `bats` tests.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

- [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer) — the original inspiration for this project.
- [Calagopus](https://github.com/calagopus) — the panel this installer deploys.
- All the contributors who make open-source possible.
