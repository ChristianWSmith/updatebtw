load ../helpers/mocks.sh

setup() {
  . "$UPDATERBTW_ROOT/config.sh"
  . "$UPDATERBTW_ROOT/backup.sh"
  . "$UPDATERBTW_ROOT/updater.sh"
}

@test "update_packages fails when db.lck exists" {
  touch /var/lib/pacman/db.lck
  run update_packages
  rm -f /var/lib/pacman/db.lck
  [ "$status" -eq 1 ]
}

@test "update_packages runs yay with correct args" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="weekly"
  ENABLE_REFLECTOR="false"
  write_config

  run update_packages
  [ "$status" -eq 0 ]
  grep "yay -Syyuu --noconfirm" "$MOCK_LOG" >/dev/null
}

@test "update_packages runs paru with correct args" {
  AUR_HELPER="paru"
  UPDATE_FREQUENCY="weekly"
  ENABLE_REFLECTOR="false"
  write_config

  run update_packages
  [ "$status" -eq 0 ]
  grep "paru -Syyuu --noconfirm" "$MOCK_LOG" >/dev/null
}

@test "update_packages runs flatpak" {
  AUR_HELPER="paru"
  UPDATE_FREQUENCY="weekly"
  ENABLE_REFLECTOR="false"
  write_config

  run update_packages
  grep "flatpak update --noninteractive" "$MOCK_LOG" >/dev/null
}

@test "update_packages calls notify-send on success" {
  AUR_HELPER="paru"
  UPDATE_FREQUENCY="weekly"
  ENABLE_REFLECTOR="false"
  write_config

  run update_packages
  grep "notify-send" "$MOCK_LOG" >/dev/null
}

@test "update_mirrorlist runs reflector" {
  ENABLE_REFLECTOR="true"
  REFLECTOR_INTERVAL="0"
  write_config

  run _update_mirrorlist
  [ "$status" -eq 0 ]
  grep "reflector" "$MOCK_LOG" >/dev/null
}

@test "update_mirrorlist backs up mirrorlist" {
  # Create a mirrorlist with old timestamp
  local mirrorlist="/etc/pacman.d/mirrorlist"
  mkdir -p "$(dirname "$mirrorlist")"
  echo "Server = https://example.com" > "$mirrorlist"
  touch -t 202001010000 "$mirrorlist"

  ENABLE_REFLECTOR="true"
  REFLECTOR_INTERVAL="0"
  write_config

  run _update_mirrorlist
  local name="$(basename "$mirrorlist")"
  ls "$BACKUP_DIR/${name}."* >/dev/null 2>&1
  [ "$?" -eq 0 ]

  rm -f "$mirrorlist"
}

@test "_notify logs to stdout" {
  run _notify info "test" "body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[info] test: body"* ]]
}

@test "_run_as_user executes directly when already target user" {
  run _run_as_user root echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == "hello" ]]
}

@test "_run_as_user invokes runuser for different user" {
  run _run_as_user aur_builder echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == "hello" ]]
  grep "runuser -u aur_builder" "$MOCK_LOG" >/dev/null
}

@test "update_packages runs yay as configured user" {
  AUR_HELPER="yay"
  AUR_USER="aur_builder"
  UPDATE_FREQUENCY="weekly"
  ENABLE_REFLECTOR="false"
  write_config

  run update_packages
  [ "$status" -eq 0 ]
  grep "yay -Syyuu --noconfirm" "$MOCK_LOG" >/dev/null
  grep "runuser -u aur_builder" "$MOCK_LOG" >/dev/null
}

@test "update_packages runs flatpak as configured user" {
  AUR_HELPER="yay"
  AUR_USER="aur_builder"
  FLATPAK_USER="aur_builder"
  UPDATE_FREQUENCY="weekly"
  ENABLE_REFLECTOR="false"
  write_config

  run update_packages
  grep "flatpak update --noninteractive" "$MOCK_LOG" >/dev/null
  grep "runuser -u aur_builder -- flatpak" "$MOCK_LOG" >/dev/null
}

@test "update_packages runs flatpak as FLATPAK_USER when different from AUR_USER" {
  AUR_HELPER="yay"
  AUR_USER="aur_builder"
  FLATPAK_USER="builder"
  UPDATE_FREQUENCY="weekly"
  ENABLE_REFLECTOR="false"
  write_config

  run update_packages
  grep "flatpak update --noninteractive" "$MOCK_LOG" >/dev/null
  grep "runuser -u builder -- flatpak" "$MOCK_LOG" >/dev/null
  ! grep "runuser -u aur_builder -- flatpak" "$MOCK_LOG" >/dev/null
}
