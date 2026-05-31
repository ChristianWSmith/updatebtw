# Integration tests for updatebtw update flow

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
  export UPDATERBTW_MIN_UPDATE_INTERVAL=0
}

@test "update runs without password prompt" {
  sudo bash "$INSTALLER" --non-interactive
  run sudo updatebtw update
  [ "$status" -eq 0 ]
}

@test "update invokes yay with correct arguments" {
  sudo bash "$INSTALLER" --non-interactive
  sudo updatebtw update
  grep "yay -Syyuu --noconfirm" "$LOG_FILE" >/dev/null
}

@test "update invokes flatpak" {
  sudo bash "$INSTALLER" --non-interactive
  sudo updatebtw update
  grep "flatpak update --noninteractive" "$LOG_FILE" >/dev/null
}

@test "update runs as aur_builder user" {
  sudo bash "$INSTALLER" --non-interactive
  sudo updatebtw update
  . /opt/updatebtw/src/lib/config.sh
  UPDATERBTW_CONFIG="/etc/updatebtw/updatebtw.conf"
  read_config
  [ "$AUR_USER" = "aur_builder" ]
  grep "yay -Syyuu --noconfirm" "$LOG_FILE" >/dev/null
}

@test "update with paru dispatches paru" {
  sudo AUR_HELPER=paru bash "$INSTALLER" --non-interactive
  sudo updatebtw update
  grep "paru -Syyuu --noconfirm" "$LOG_FILE" >/dev/null
}

@test "rate limiting prevents rapid successive updates" {
  sudo bash "$INSTALLER" --non-interactive
  sudo updatebtw update
  run sudo updatebtw update
  [ "$status" -ne 0 ]
  [[ "$output" == *"Throttled"* ]] || [[ "$output" == *"already running"* ]]
}

@test "update respects pacman database lock" {
  sudo bash "$INSTALLER" --non-interactive
  sudo touch /var/lib/pacman/db.lck
  run sudo updatebtw update
  sudo rm -f /var/lib/pacman/db.lck
  [ "$status" -ne 0 ]
  [[ "$output" == *"db.lck"* ]]
}

@test "reflector runs when enabled" {
  sudo bash "$INSTALLER" --non-interactive
  sudo updatebtw update
  grep "reflector" "$LOG_FILE" >/dev/null
}

@test "reflector does not run when disabled" {
  sudo ENABLE_REFLECTOR=false bash "$INSTALLER" --non-interactive
  sudo updatebtw update
  ! grep "reflector" "$LOG_FILE" >/dev/null
}
