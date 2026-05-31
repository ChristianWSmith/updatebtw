# updatebtw

Unofficial automatic update utility for Arch Linux and compatible distributions.
Not affiliated with or endorsed by the Arch Linux project.

## Install

```sh
curl -sS https://raw.githubusercontent.com/anomalyco/updatebtw/main/installer.sh | sudo bash
```

This launches a TUI wizard that walks you through configuring AUR helper, update
schedule, mirrorlist refreshing, and more. No manual setup required.

After install, automatic updates are enabled by default on your chosen schedule
(daily, weekly, or monthly). You can also run an update at any time:

```sh
sudo updatebtw update
```

## Commands

| Command | Description |
|---------|-------------|
| `updatebtw update` | Run system update now (inhibits shutdown) |
| `updatebtw install` | Re-run the installer wizard |
| `updatebtw status` | Show current configuration |
| `updatebtw on` | Enable automatic updates |
| `updatebtw off` | Disable automatic updates |
| `updatebtw reflector` | Refresh mirrorlist via reflector now |
| `updatebtw backup list` | List available backups |
| `updatebtw backup restore <path>` | Restore latest backup of a file |
| `updatebtw uninstall` | Remove updatebtw (keeps backups) |

## How it works

When `updatebtw update` runs, it:

1. Refreshes the mirrorlist via reflector (if enabled, respects interval)
2. Updates system packages via `yay -Syyuu --noconfirm` (or `paru`)
3. Runs `flatpak update --noninteractive` if flatpak is installed

Updates run as an unprivileged AUR user (`aur_builder` by default) with
passwordless sudo scoped only to `/usr/bin/pacman`. Shutdown is blocked
during updates via `systemd-inhibit` with a desktop notification.

## Configuration

Edit `/etc/updatebtw/updatebtw.conf` or re-run `sudo updatebtw install`.

| Option | Default | Description |
|--------|---------|-------------|
| `AUR_HELPER` | `yay` | AUR helper to use (`yay` or `paru`) |
| `UPDATE_FREQUENCY` | `weekly` | Schedule (`daily`, `weekly`, `monthly`) |
| `UPDATE_TIME` | `06:00` | Time of day for scheduled updates |
| `RUN_AT_BOOT` | `false` | Also update on every boot |
| `ENABLE_REFLECTOR` | `true` | Refresh mirrorlist via reflector |
| `REFLECTOR_COUNTRY` | `United States` | Country for mirror selection |
| `REFLECTOR_INTERVAL` | `30` | Days between mirrorlist refreshes |
| `AUR_USER` | `aur_builder` | Unprivileged user for AUR updates |
| `FLATPAK_USER` | (install user) | User for flatpak updates |

## Uninstall

```sh
sudo updatebtw uninstall
```

This removes binaries, libraries, config, systemd units, sudoers rules, and the
AUR user. Backups in `/var/lib/updatebtw/backups` are left intact.
