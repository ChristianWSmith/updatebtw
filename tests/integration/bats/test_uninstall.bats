# Integration tests for uninstall

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

@test "uninstall removes binary" {
  sudo bash "$INSTALLER" --non-interactive
  [ -f /usr/bin/updatebtw ]

  sudo updatebtw uninstall
  [ ! -f /usr/bin/updatebtw ]
}

@test "uninstall removes library files" {
  sudo bash "$INSTALLER" --non-interactive
  [ -d /usr/lib/updatebtw ]

  sudo updatebtw uninstall
  [ ! -d /usr/lib/updatebtw ]
}

@test "uninstall removes config directory" {
  sudo bash "$INSTALLER" --non-interactive
  [ -d /etc/updatebtw ]

  sudo updatebtw uninstall
  [ ! -d /etc/updatebtw ]
}

@test "uninstall removes systemd units" {
  sudo bash "$INSTALLER" --non-interactive
  [ -f /etc/systemd/system/updatebtw-update.service ]
  [ -f /etc/systemd/system/updatebtw-update.timer ]
  [ -f /etc/systemd/system/updatebtw-boot.service ]

  sudo updatebtw uninstall
  [ ! -f /etc/systemd/system/updatebtw-update.service ]
  [ ! -f /etc/systemd/system/updatebtw-update.timer ]
  [ ! -f /etc/systemd/system/updatebtw-boot.service ]
}

@test "uninstall removes sudoers rules" {
  sudo bash "$INSTALLER" --non-interactive
  [ -f /etc/sudoers.d/updatebtw-aur_builder ]

  sudo updatebtw uninstall
  [ ! -f /etc/sudoers.d/updatebtw-aur_builder ]
}

@test "uninstall preserves backups" {
  sudo bash "$INSTALLER" --non-interactive

  local test_file="/tmp/test_uninstall_backup.conf"
  echo "backup me" > "$test_file"

  sudo updatebtw uninstall

  [ -d /var/lib/updatebtw/backups ]
  rm -f "$test_file"
}

@test "uninstall removes state files" {
  sudo bash "$INSTALLER" --non-interactive
  sudo updatebtw update

  sudo updatebtw uninstall
  [ ! -d /var/lib/updatebtw/state ]
}
