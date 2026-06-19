# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-18

### Added
- Initial release of the Calagopus Installer.
- Interactive TUI menu + non-interactive CLI flags.
- Panel-only, Wings-only, and Full Stack install targets.
- Docker (AIO + standalone) and native (binary) deployment modes.
- Automatic dependency provisioning: Docker, PostgreSQL, Redis/Valkey, Nginx,
  Caddy, Certbot, firewall tooling.
- Database management: local, existing-local, remote PostgreSQL; secure
  credential generation; idempotent role/database creation; connectivity
  validation.
- SSL management: Let's Encrypt, self-signed, existing, Cloudflare Origin
  certificates; automatic renewal + renewal monitoring.
- Reverse proxy: Nginx and Caddy with WebSocket + security headers.
- Firewall: UFW, firewalld, nftables, iptables; least-privilege port exposure.
- Backup + restore: full bundle (DB, config, app files); retention policies;
  systemd timer for scheduled backups.
- Update + rollback: channel-aware upgrades; pre-upgrade backup; health-check
  driven automatic rollback.
- Repair mode: missing files, broken services, DB/Docker issues, permissions,
  SSL, proxy config.
- Monitoring: `calagopus-installer status|doctor|logs` commands.
- Security: secrets redacted from logs; config files mode 0600; least
  privilege throughout.
- OS support: Ubuntu 22.04+, Debian 11+, RHEL/Rocky/Alma 8+, Fedora, Arch,
  openSUSE; x86_64, ARM64, ARMv7, RISC-V, PPC64LE.
- CI: shellcheck + bats via GitHub Actions.
- Vagrantfile for integration testing across supported distros.
