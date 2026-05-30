# updatebtw

Unofficial automatic update utility for Arch Linux and compatible distributions. Not affiliated with or endorsed by the Arch Linux project.

## Usage

```sh
# Install via standalone installer (from releases)
curl -sSfL https://github.com/anomalyco/updatebtw/releases/latest/download/installer.sh | sh

# Or build from source
make && make install
```

## Commands

| Command | Description |
|---|---|
| `updatebtw update` | Run system update now |
| `updatebtw install` | Run TUI installer/reconfigure |
| `updatebtw status` | Show current configuration |
| `updatebtw backup list` | List available backups |
| `updatebtw backup restore <path>` | Restore a file from backup |

## Development

```sh
make        # Build standalone installer.sh
make test   # Run tests in Docker
make clean  # Remove build artifacts
```

## Project Structure

```
src/          Source files
├── updatebtw       CLI entry point
└── lib/            Library modules
    ├── config.sh       Config read/write/validate
    ├── backup.sh       Timestamped backups with rotation
    ├── updater.sh      Core update logic (AUR, flatpak, reflector)
    ├── silent-boot.sh  Boot quieting configuration
    └── installer.sh    TUI installer (whiptail)
systemd/      Systemd unit files
config/       Default configuration
tests/        Docker + Bats test suite
build/        Build helper scripts
```

## Testing

All tests run in Docker — no system modifications:

```sh
make test
```
