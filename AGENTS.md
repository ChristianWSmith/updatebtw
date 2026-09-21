# updatebtw

Arch Linux automatic update utility. Pure shell project — no compiled code.

## Build & Verify

```sh
make              # rebuild installer.sh and README.md from source modules
make lint         # shellcheck on src/updatebtw, src/lib/*.sh, build/build-installer.sh
make test         # BATS unit tests in Docker (archlinux:base-devel image)
make integration  # integration tests in Docker
make clean        # removes generated installer.sh and README.md
```

`make` is the only build step. `installer.sh` and `README.md` are generated, not hand-edited. Edit `templates/README.md.in`, never `README.md` directly.

## Architecture

- `src/updatebtw` — CLI entrypoint (bash). Dispatches commands: `update`, `install`, `status`, `on`, `off`, `backup`, etc.
- `src/lib/config.sh` — config read/write/validate. Reads `/etc/updatebtw/updatebtw.conf` with strict validation (fd-based TOCTOU mitigation, symlink rejection, character allowlist).
- `src/lib/backup.sh` — file backup/restore with manifest and rotation.
- `src/lib/updater.sh` — core update logic: rate limiting, mirrorlist refresh, AUR helper invocation, flatpak updates.
- `src/lib/silent-boot.sh` — modifies bootloader, mkinitcpio, sysctl, systemd services for quiet boot.
- `src/lib/installer.sh` — installer helper functions (AUR user setup, AUR helper build).
- `build/build-installer.sh` — concatenates all source into a single self-extracting `installer.sh` with base64 payloads and integrity hash.
- `config/updatebtw.conf` — default config template (embedded into installer).
- `systemd/` — timer and service units.

### Module sourcing

`src/updatebtw` sources modules from `$UPDATERBTW_ROOT` (default `/usr/lib/updatebtw`). Each command sources only what it needs (e.g., `update` loads config+backup+updater, `install` loads config+backup+silent-boot+installer). For development, `UPDATERBTW_ROOT` can point to `src/lib` but is ignored when running via sudo and rejects world-writable directories.

### Timer scheduling

`systemd/updatebtw-update.timer` is a bare timer unit. The actual schedule is written dynamically to a drop-in at `/etc/systemd/system/updatebtw-update.timer.d/schedule.conf` by `enable_timer()` using `calendar_from_config()`. Changing schedule config requires re-running install or `updatebtw install` to regenerate the drop-in.

## Build process

`build/build-installer.sh` concatenates a header (installer logic) with all lib modules, then base64-encodes each source file into `install_*` payload functions. The integrity hash (`SOURCES_HASH`) is computed over everything before the `#__END_OF_PAYLOADS__` delimiter, excluding the hash itself. Changing any source file changes the hash. Never edit `installer.sh` directly.

`README.md` is generated from `templates/README.md.in` by replacing `__INSTALLER_SHA256__` with the sha256sum of the built `installer.sh`. This embeds the checksum directly in the install instructions so users verify against what GitHub displays.

## Testing

Tests use BATS inside Docker (`archlinux:base-devel` with `bats`, `sudo`, `procps-ng`). The Dockerfile creates test users (`builder`, `aur_builder`, `test_user`) and mock directories (`/var/lib/pacman`, `/etc/pacman.d`, `/boot/loader/entries`).

```sh
# Run specific test file
make test && docker run --rm updatebtw-test bats tests/bats/test_config.bats

# Run single test
docker run --rm updatebtw-test bats --filter "test name" tests/bats/test_config.bats
```

Test files: `test_cli.bats`, `test_config.bats`, `test_backup.bats`, `test_updater.bats`, `test_silent_boot.bats`. Tests load `helpers/mocks.sh` for setup/teardown.

## Linting

`make lint` runs `shellcheck` on all shell sources. No other linters or formatters configured. Fix shellcheck warnings before committing.

## Conventions

- Shell scripts use POSIX sh (`#!/bin/sh`) except `src/updatebtw` which uses `#!/usr/bin/env bash`.
- No external dependencies beyond core Arch Linux packages (whiptail, git, sudo, base-devel).
- Config values are set directly from parsed lines — never sourced from the config file.
- Security-critical patterns: fd-based file opens (no TOCTOU), symlink rejection, strict character allowlists, atomic file writes via temp+mv.
- `installer.sh` and `README.md` are generated artifacts. Edit sources in `src/` and `templates/README.md.in`, rebuild with `make`, never edit them directly.
- `UPDATEBTW_AUTO_INSTALL_AUR=1` skips the PKGBUILD review prompt during AUR helper install.
- `_run_as_user` argument validation: only `[a-zA-Z0-9_./:@,+=-]` allowed — no shell metacharacters pass through.
