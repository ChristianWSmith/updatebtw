# Integration tests for CLI commands

setup_file() {
  export INSTALLER="/opt/updatebtw/installer.sh"
  export LOG_FILE="/var/log/updatebtw-integration.log"
}

setup() {
  : > "$LOG_FILE"
  chmod 666 "$LOG_FILE"
  rm -f /var/lib/updatebtw/last_update
  rm -f /var/lib/updatebtw/update.lock
  rm -f /var/lib/updatebtw/pacman.lock
  rm -rf /var/lib/updatebtw/backups/*
}

@test "status shows correct configuration after install" {
  sudo bash "$INSTALLER" --non-interactive
  run sudo updatebtw status
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUR_HELPER=yay"* ]]
  [[ "$output" == *"UPDATE_FREQUENCY=weekly"* ]]
  [[ "$output" == *"UPDATE_TIME=06:00"* ]]
}

@test "status reflects custom configuration" {
  sudo AUR_HELPER=paru UPDATE_FREQUENCY=daily UPDATE_TIME=03:00 bash "$INSTALLER" --non-interactive
  run sudo updatebtw status
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUR_HELPER=paru"* ]]
  [[ "$output" == *"UPDATE_FREQUENCY=daily"* ]]
  [[ "$output" == *"UPDATE_TIME=03:00"* ]]
}

@test "on enables the timer" {
  sudo bash "$INSTALLER" --non-interactive
  sudo updatebtw off
  run sudo updatebtw on
  [ "$status" -eq 0 ]
  grep "systemctl enable --now updatebtw-update.timer" "$LOG_FILE" >/dev/null
}

@test "off disables the timer" {
  sudo bash "$INSTALLER" --non-interactive
  run sudo updatebtw off
  [ "$status" -eq 0 ]
  grep "systemctl disable --now updatebtw-update.timer" "$LOG_FILE" >/dev/null
}

@test "reflector command updates mirrorlist" {
  sudo bash "$INSTALLER" --non-interactive
  run sudo updatebtw reflector
  [ "$status" -eq 0 ]
  grep "reflector" "$LOG_FILE" >/dev/null
}

@test "backup list works with no backups" {
  sudo bash "$INSTALLER" --non-interactive
  run sudo updatebtw backup list
  [ "$status" -eq 0 ]
}

@test "backup and restore round-trip" {
  sudo bash "$INSTALLER" --non-interactive

  local test_file="/tmp/test_backup_file.conf"
  echo "original content" > "$test_file"

  sudo updatebtw backup list

  run sudo updatebtw backup restore "$test_file"
  [ "$status" -ne 0 ]

  rm -f "$test_file"
}

@test "help prints usage" {
  run sudo updatebtw help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: updatebtw <command>"* ]]
}
