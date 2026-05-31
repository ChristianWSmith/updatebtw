# Integration tests for the installer

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

teardown() {
  rm -f /var/lib/updatebtw/last_update
  rm -f /var/lib/updatebtw/update.lock
  rm -f /var/lib/updatebtw/pacman.lock
}

@test "non-interactive install with defaults succeeds" {
  run sudo bash "$INSTALLER" --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUR_HELPER=yay"* ]]
  [[ "$output" == *"UPDATE_FREQUENCY=weekly"* ]]
}

@test "non-interactive install writes config file" {
  sudo bash "$INSTALLER" --non-interactive
  [ -f /etc/updatebtw/updatebtw.conf ]
}

@test "config file has correct permissions" {
  sudo bash "$INSTALLER" --non-interactive
  local perms
  perms="$(stat -c '%a' /etc/updatebtw/updatebtw.conf)"
  [ "$perms" = "600" ]
}

@test "config file is owned by root" {
  sudo bash "$INSTALLER" --non-interactive
  local owner
  owner="$(stat -c '%U' /etc/updatebtw/updatebtw.conf)"
  [ "$owner" = "root" ]
}

@test "config contains expected default values" {
  sudo bash "$INSTALLER" --non-interactive
  . /opt/updatebtw/src/lib/config.sh
  UPDATERBTW_CONFIG="/etc/updatebtw/updatebtw.conf"
  read_config

  [ "$AUR_HELPER" = "yay" ]
  [ "$UPDATE_FREQUENCY" = "weekly" ]
  [ "$UPDATE_TIME" = "06:00" ]
  [ "$RUN_AT_BOOT" = "false" ]
  [ "$ENABLE_REFLECTOR" = "true" ]
  [ "$REFLECTOR_COUNTRY" = "United States" ]
  [ "$REFLECTOR_INTERVAL" = "30" ]
  [ "$SILENT_BOOT" = "false" ]
  [ "$AUR_USER" = "aur_builder" ]
}

@test "systemd units are installed" {
  sudo bash "$INSTALLER" --non-interactive
  [ -f /etc/systemd/system/updatebtw-update.service ]
  [ -f /etc/systemd/system/updatebtw-update.timer ]
  [ -f /etc/systemd/system/updatebtw-boot.service ]
}

@test "sudoers rules are created for aur_builder" {
  sudo bash "$INSTALLER" --non-interactive
  [ -f /etc/sudoers.d/updatebtw-aur_builder ]
}

@test "sudoers rules allow passwordless pacman" {
  sudo bash "$INSTALLER" --non-interactive
  local content
  content="$(cat /etc/sudoers.d/updatebtw-aur_builder)"
  [[ "$content" == *"NOPASSWD"* ]]
  [[ "$content" == *"/usr/bin/pacman"* ]]
}

@test "aur_builder user exists" {
  sudo bash "$INSTALLER" --non-interactive
  id aur_builder >/dev/null 2>&1
}

@test "binary is installed" {
  sudo bash "$INSTALLER" --non-interactive
  [ -f /usr/bin/updatebtw ]
  [ -x /usr/bin/updatebtw ]
}

@test "library files are installed" {
  sudo bash "$INSTALLER" --non-interactive
  [ -f /usr/lib/updatebtw/config.sh ]
  [ -f /usr/lib/updatebtw/backup.sh ]
  [ -f /usr/lib/updatebtw/updater.sh ]
  [ -f /usr/lib/updatebtw/silent-boot.sh ]
  [ -f /usr/lib/updatebtw/installer.sh ]
}

@test "non-interactive install with paru override" {
  sudo AUR_HELPER=paru bash "$INSTALLER" --non-interactive
  . /opt/updatebtw/src/lib/config.sh
  UPDATERBTW_CONFIG="/etc/updatebtw/updatebtw.conf"
  read_config
  [ "$AUR_HELPER" = "paru" ]
}

@test "non-interactive install with daily frequency override" {
  sudo UPDATE_FREQUENCY=daily UPDATE_TIME=03:00 bash "$INSTALLER" --non-interactive
  . /opt/updatebtw/src/lib/config.sh
  UPDATERBTW_CONFIG="/etc/updatebtw/updatebtw.conf"
  read_config
  [ "$UPDATE_FREQUENCY" = "daily" ]
  [ "$UPDATE_TIME" = "03:00" ]
}

@test "non-interactive install with reflector disabled" {
  sudo ENABLE_REFLECTOR=false bash "$INSTALLER" --non-interactive
  . /opt/updatebtw/src/lib/config.sh
  UPDATERBTW_CONFIG="/etc/updatebtw/updatebtw.conf"
  read_config
  [ "$ENABLE_REFLECTOR" = "false" ]
}

@test "non-interactive install with silent boot enabled" {
  sudo SILENT_BOOT=true bash "$INSTALLER" --non-interactive
  . /opt/updatebtw/src/lib/config.sh
  UPDATERBTW_CONFIG="/etc/updatebtw/updatebtw.conf"
  read_config
  [ "$SILENT_BOOT" = "true" ]
}

@test "non-interactive install with run at boot enabled" {
  sudo RUN_AT_BOOT=true bash "$INSTALLER" --non-interactive
  . /opt/updatebtw/src/lib/config.sh
  UPDATERBTW_CONFIG="/etc/updatebtw/updatebtw.conf"
  read_config
  [ "$RUN_AT_BOOT" = "true" ]
}
