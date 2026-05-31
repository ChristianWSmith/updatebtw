# Integration tests for reconfigure flow

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
  rm -f /etc/sysctl.d/20-quiet-printk.conf
}

@test "reconfigure changes configuration" {
  sudo bash "$INSTALLER" --non-interactive

  run sudo updatebtw status
  [[ "$output" == *"AUR_HELPER=yay"* ]]
  [[ "$output" == *"UPDATE_FREQUENCY=weekly"* ]]

  sudo AUR_HELPER=paru UPDATE_FREQUENCY=daily UPDATE_TIME=03:00 bash "$INSTALLER" --non-interactive

  run sudo updatebtw status
  [[ "$output" == *"AUR_HELPER=paru"* ]]
  [[ "$output" == *"UPDATE_FREQUENCY=daily"* ]]
  [[ "$output" == *"UPDATE_TIME=03:00"* ]]
}

@test "reconfigure preserves existing install" {
  sudo bash "$INSTALLER" --non-interactive

  [ -f /usr/bin/updatebtw ]
  [ -f /etc/systemd/system/updatebtw-update.service ]

  sudo UPDATE_FREQUENCY=monthly bash "$INSTALLER" --non-interactive

  [ -f /usr/bin/updatebtw ]
  [ -f /etc/systemd/system/updatebtw-update.service ]
}

@test "reconfigure with silent boot applies changes" {
  sudo SILENT_BOOT=false bash "$INSTALLER" --non-interactive
  [ ! -f /etc/sysctl.d/20-quiet-printk.conf ]

  sudo SILENT_BOOT=true bash "$INSTALLER" --non-interactive
  [ -f /etc/sysctl.d/20-quiet-printk.conf ]
}

@test "reconfigure with reflector disabled" {
  sudo bash "$INSTALLER" --non-interactive

  . /opt/updatebtw/src/lib/config.sh
  UPDATERBTW_CONFIG="/etc/updatebtw/updatebtw.conf"
  read_config
  [ "$ENABLE_REFLECTOR" = "true" ]

  sudo ENABLE_REFLECTOR=false bash "$INSTALLER" --non-interactive

  read_config
  [ "$ENABLE_REFLECTOR" = "false" ]
}
