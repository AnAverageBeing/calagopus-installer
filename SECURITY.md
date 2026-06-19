# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.0.x | ✅ |
| < 1.0 | ❌ |

## Reporting a vulnerability

If you discover a security vulnerability in the Calagopus Installer, please
report it responsibly:

1. **Do NOT open a public GitHub issue.**
2. Email the maintainers with details of the vulnerability.
3. Include steps to reproduce if possible.
4. You will receive a response within 48 hours.

## Security features

The Calagopus Installer is designed with security in mind:

- **Secrets are never logged.** All log output passes through a redaction
  layer that masks known secret keys (passwords, tokens, connection strings)
  before they reach the terminal or log file.
- **Config files are mode 0600.** The installer's config and state files
  (which contain credentials) are created with restrictive permissions.
- **Principle of least privilege.** Firewall rules open only the ports
  Calagopus actually needs. Database roles get only the privileges they
  require.
- **Secure credential generation.** All generated passwords, encryption keys,
  and tokens use cryptographic random sources (`/dev/urandom` or `openssl`).
- **No credential leakage to `ps`.** Passwords are passed via environment
  variables or stdin, never as command-line arguments.
