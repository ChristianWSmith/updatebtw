# Mock helpers for testing
# Override system commands with logging versions

export MOCK_LOG="$(mktemp /tmp/updatebtw-mock.XXXXXX)"
export BACKUP_DIR="$(mktemp -d /tmp/updatebtw-backup.XXXXXX)"

# Override config path for testing
export UPDATERBTW_CONFIG="$(mktemp /tmp/updatebtw-config.XXXXXX)"
export UPDATERBTW_BACKUP_DIR="$BACKUP_DIR"
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

# Mock runuser — intercept user switching, execute command directly
runuser() {
  echo "runuser $*" >> "$MOCK_LOG"
  local args=() after_dd=false
  for arg in "$@"; do
    if $after_dd; then
      args+=("$arg")
    fi
    [ "$arg" = "--" ] && after_dd=true
  done
  "${args[@]}"
}

# Mock su — intercept user switching, execute command directly
su() {
  echo "su $*" >> "$MOCK_LOG"
  local cmd="" next=false
  for arg in "$@"; do
    if $next; then
      cmd="$arg"
      break
    fi
    [ "$arg" = "-c" ] && next=true
  done
  if [ -n "$cmd" ]; then
    eval "$cmd"
  fi
}
