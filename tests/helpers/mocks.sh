# Mock helpers for testing
# Override system commands with logging versions

export MOCK_LOG="$(mktemp /tmp/updatebtw-mock.XXXXXX)"
export BACKUP_DIR="$(mktemp -d /tmp/updatebtw-backup.XXXXXX)"

# Override config path for testing
export UPDATERBTW_CONFIG="$(mktemp /tmp/updatebtw-config.XXXXXX)"
export UPDATERBTW_BACKUP_DIR="$BACKUP_DIR"
export AUR_USER="${AUR_USER:-root}"
export UPDATERBTW_BACKUP_KEEP="5"

# Source the real modules
export UPDATERBTW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)"

setup() {
  :> "$MOCK_LOG"
  rm -rf "$BACKUP_DIR"/*
  mkdir -p "$BACKUP_DIR"
}

teardown() {
  rm -f "$UPDATERBTW_CONFIG"
}

# Mock systemctl
systemctl() {
  echo "systemctl $*" >> "$MOCK_LOG"
  return 0
}

# Mock pacman
pacman() {
  echo "pacman $*" >> "$MOCK_LOG"
  return 0
}

# Mock yay
yay() {
  echo "yay $*" >> "$MOCK_LOG"
  return 0
}

# Mock paru
paru() {
  echo "paru $*" >> "$MOCK_LOG"
  return 0
}

# Mock flatpak
flatpak() {
  echo "flatpak $*" >> "$MOCK_LOG"
  return 0
}

# Mock reflector
reflector() {
  echo "reflector $*" >> "$MOCK_LOG"
  return 0
}

# Mock notify-send
notify-send() {
  echo "notify-send $*" >> "$MOCK_LOG"
  return 0
}

# Mock mkinitcpio
mkinitcpio() {
  echo "mkinitcpio $*" >> "$MOCK_LOG"
  return 0
}
