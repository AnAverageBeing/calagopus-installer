# Contributing to Calagopus Installer

Thanks for your interest in improving the Calagopus Installer. This document
covers the expectations for contributions so the project stays reliable,
secure, and easy to maintain.

## Code style

- **Bash 4+** is the target. Use associative arrays, `[[ ]]`, and
  `declare -F` checks freely. Avoid bashisms that break under `sh`.
- **ShellCheck clean.** Every `.sh` file must pass
  `shellcheck -x` with no warnings. The CI enforces this.
- **No side effects on source.** Library/module files must only declare
  functions and variables. Never run install logic at the top level so unit
  tests can `source` a file in isolation.
- **Idempotency.** Every install/repair/configure function must be safe to
  re-run. Check "is this already done?" before acting.
- **Secrets never logged.** Use the `log_*` helpers, which redact known
  secret keys. Never `echo` a password or connection string directly.
- **Comments explain *why*, not *what*.** The code should be readable; the
  comment should capture the decision or constraint that isn't obvious from
  the code.
- **Modular structure.** New functionality goes in a new file under the
  appropriate `src/<area>/` directory. Wire it into `src/installer.sh`'s
  `_source_all()`.

## Adding a new OS

1. Add a detection branch in `src/os/detect.sh` (`os_check_supported`).
2. If the OS needs repo setup, add `src/os/<family>.sh` with the
   `os_family_prepare` + any `*_add_*_repo` helpers.
3. Add a Vagrant box to `Vagrantfile` so CI can exercise it.

## Testing

```bash
# Lint
shellcheck install.sh src/**/*.sh scripts/*.sh

# Unit tests
bats tests/

# Integration (spins up VMs)
vagrant up <box>
vagrant ssh <box> -c 'sudo /vagrant/src/installer.sh --dry-run --non-interactive --yes --action install_full --target full'
```

## Pull request checklist

- [ ] `shellcheck` passes on all changed files.
- [ ] `bats tests/` passes.
- [ ] New functions have a bats test where practical.
- [ ] No secrets / credentials in commits or logs.
- [ ] CHANGELOG.md updated under an `[Unreleased]` section.
- [ ] README updated if user-facing behaviour changed.

## Releasing

1. Update `CHANGELOG.md` with the release date + tag.
2. Bump `CALAGOPUS_INSTALLER_VERSION` in `src/lib/common.sh` and
   `SCRIPT_RELEASE` in `install.sh`.
3. Commit with message `Release vX.Y.Z`.
4. Tag `vX.Y.Z` and create a GitHub release; attach `src/installer.sh` as
   `installer.sh` so the bootstrap can fetch it as a release asset.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Be excellent to each other.
