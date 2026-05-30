load ../helpers/mocks.sh

setup_file() {
  export UPDATERBTW_ROOT="/opt/updatebtw/src/lib"
  export CLI="/opt/updatebtw/src/updatebtw"
}

setup() {
  : > "$MOCK_LOG"
}

# Override systemd-inhibit for testing (it requires logind D-Bus)
systemd-inhibit() {
  echo "systemd-inhibit $*" >> "$MOCK_LOG"
  shift
  eval "$@"
}
export -f systemd-inhibit

@test "cli help prints usage" {
  run "$CLI" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: updatebtw <command>"* ]]
}

@test "cli --help prints usage" {
  run "$CLI" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: updatebtw <command>"* ]]
}

@test "cli no args prints usage" {
  run "$CLI"
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: updatebtw <command>"* ]]
}

@test "cli status shows default config" {
  run "$CLI" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUR_HELPER=yay"* ]]
  [[ "$output" == *"UPDATE_FREQUENCY=weekly"* ]]
  [[ "$output" == *"UPDATE_TIME=06:00"* ]]
}

@test "cli status reads written config" {
  export UPDATERBTW_CONFIG="/tmp/test_cli_status.conf"
  echo 'AUR_HELPER="paru"' > "$UPDATERBTW_CONFIG"
  echo 'UPDATE_FREQUENCY="daily"' >> "$UPDATERBTW_CONFIG"

  run "$CLI" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUR_HELPER=paru"* ]]
  [[ "$output" == *"UPDATE_FREQUENCY=daily"* ]]

  rm -f "$UPDATERBTW_CONFIG"
}

@test "cli update dispatches yay" {
  yay() { echo "yay $*" >> "$MOCK_LOG"; return 0; }
  flatpak() { echo "flatpak $*" >> "$MOCK_LOG"; return 0; }
  notify-send() { echo "notify-send $*" >> "$MOCK_LOG"; return 0; }
  export -f yay flatpak notify-send

  run "$CLI" update
  [ "$status" -eq 0 ]
  grep "yay -Syyuu --noconfirm" "$MOCK_LOG" >/dev/null
}

@test "cli update dispatchs paru when configured" {
  export UPDATERBTW_CONFIG="/tmp/test_cli_paru.conf"
  cat > "$UPDATERBTW_CONFIG" << 'EOF'
AUR_HELPER="paru"
UPDATE_FREQUENCY="weekly"
ENABLE_REFLECTOR="false"
EOF

  paru() { echo "paru $*" >> "$MOCK_LOG"; return 0; }
  flatpak() { echo "flatpak $*" >> "$MOCK_LOG"; return 0; }
  notify-send() { echo "notify-send $*" >> "$MOCK_LOG"; return 0; }
  export -f paru flatpak notify-send

  run "$CLI" update
  [ "$status" -eq 0 ]
  grep "paru -Syyuu --noconfirm" "$MOCK_LOG" >/dev/null

  rm -f "$UPDATERBTW_CONFIG"
}

@test "cli update fails on pacman lock" {
  touch /var/lib/pacman/db.lck
  run "$CLI" update
  rm -f /var/lib/pacman/db.lck
  [ "$status" -eq 1 ]
  [[ "$output" == *"db.lck"* ]]
}

@test "cli update runs flatpak" {
  yay() { echo "yay $*" >> "$MOCK_LOG"; return 0; }
  flatpak() { echo "flatpak $*" >> "$MOCK_LOG"; return 0; }
  notify-send() { echo "notify-send $*" >> "$MOCK_LOG"; return 0; }
  export -f yay flatpak notify-send

  run "$CLI" update
  grep "flatpak update --noninteractive" "$MOCK_LOG" >/dev/null
}

@test "cli update with SYSTEMD_INHIBIT invokes systemd-inhibit" {
  export SYSTEMD_INHIBIT=1
  export UPDATERBTW_ROOT="/opt/updatebtw/src/lib"
  # Mock systemd-inhibit — since exec replaces the process, we write args and
  # re-exec the CLI without SYSTEMD_INHIBIT to test the full chain.
  cat > /tmp/systemd-inhibit << 'SCRIPT'
#!/bin/sh
echo "systemd-inhibit $*" >> /tmp/mock_log
# Extract cmd after --mode=block and exec it
while [ $# -gt 0 ] && [ "$1" != "--mode=block" ]; do shift; done
shift 2>/dev/null
exec "$@"
SCRIPT
  chmod +x /tmp/systemd-inhibit
  export PATH="/tmp:$PATH"

  # Provide real mock executables for all system commands (functions lost after exec)
  for cmd in yay paru flatpak notify-send reflector; do
    cat > "/tmp/$cmd" << 'SUB'
#!/bin/sh
echo "$(basename $0) $*" >> /tmp/mock_log
SUB
    chmod +x "/tmp/$cmd"
  done
  # Disable reflector by writing a fresh mirrorlist
  mkdir -p /etc/pacman.d
  date +"Server = https://example.com" > /etc/pacman.d/mirrorlist

  run "$CLI" update
  [ "$status" -eq 0 ]
  grep "systemd-inhibit" /tmp/mock_log >/dev/null
  grep "yay -Syyuu --noconfirm" /tmp/mock_log >/dev/null
  grep "flatpak update --noninteractive" /tmp/mock_log >/dev/null
}

@test "cli backup list shows no backups initially" {
  run "$CLI" backup list
  [ "$status" -eq 0 ]
}

@test "cli backup restore fails without path" {
  run "$CLI" backup restore
  [ "$status" -eq 1 ]
}

@test "cli backup restore fails for nonexistent file" {
  run "$CLI" backup restore /nonexistent/path
  [ "$status" -eq 1 ]
}
