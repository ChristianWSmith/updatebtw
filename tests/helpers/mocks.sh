# Mock helpers for testing
# Override system commands with logging versions

export MOCK_LOG="$(mktemp /tmp/updatebtw-mock.XXXXXX)"
export BACKUP_DIR="$(mktemp -d /tmp/updatebtw-backup.XXXXXX)"

# Override config path for testing
export UPDATERBTW_CONFIG="$(mktemp /tmp/updatebtw-config.XXXXXX)"
chmod 600 "$UPDATERBTW_CONFIG"
export _UPDATERBTW_CONFIG_ORIG="$UPDATERBTW_CONFIG"
export UPDATERBTW_BACKUP_DIR="$BACKUP_DIR"
export UPDATERBTW_BACKUP_KEEP="5"

# Source the real modules
export UPDATERBTW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)"

mocks_setup() {
  :> "$MOCK_LOG"
  rm -rf "$BACKUP_DIR"/*
  mkdir -p "$BACKUP_DIR"
  UPDATERBTW_CONFIG="$_UPDATERBTW_CONFIG_ORIG"
  export UPDATERBTW_CONFIG
  if [ ! -f "$UPDATERBTW_CONFIG" ]; then
    UPDATERBTW_CONFIG="$(mktemp /tmp/updatebtw-config.XXXXXX)"
    chmod 600 "$UPDATERBTW_CONFIG"
    export UPDATERBTW_CONFIG
    export _UPDATERBTW_CONFIG_ORIG="$UPDATERBTW_CONFIG"
  fi
  rm -f /var/lib/updatebtw/state/last_update 2>/dev/null || true
  export UPDATERBTW_MIN_UPDATE_INTERVAL=0
}

mocks_teardown() {
  if [ "$UPDATERBTW_CONFIG" != "$_UPDATERBTW_CONFIG_ORIG" ]; then
    rm -f "$UPDATERBTW_CONFIG"
  fi
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

# Mock timeout
timeout() {
  local duration="$1"
  shift
  "$@"
}

export -f pacman yay paru flatpak reflector notify-send mkinitcpio runuser su timeout
