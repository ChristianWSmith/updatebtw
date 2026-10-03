load ../helpers/mocks.sh

setup_file() {
  export FIXTURES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../fixtures" && pwd)"
}

setup() {
  mocks_setup
  . "$UPDATERBTW_ROOT/config.sh"
}

teardown() {
  mocks_teardown
}

@test "read_config returns ok when file doesn't exist" {
  run read_config
  [ "$status" -eq 0 ]
}

@test "write_config writes valid config file" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="daily"
  UPDATE_TIME="08:00"
  RUN_AT_BOOT="true"
  ENABLE_REFLECTOR="false"
  SILENT_BOOT="true"

  write_config
  [ -f "$UPDATERBTW_CONFIG" ]
}

@test "read_config reads back written values" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="daily"
  UPDATE_TIME="08:00"
  RUN_AT_BOOT="true"
  ENABLE_REFLECTOR="false"
  SILENT_BOOT="true"

  write_config

  # Reset and read
  AUR_HELPER=""
  UPDATE_FREQUENCY=""
  read_config

  [ "$AUR_HELPER" = "yay" ]
  [ "$UPDATE_FREQUENCY" = "daily" ]
  [ "$UPDATE_TIME" = "08:00" ]
  [ "$RUN_AT_BOOT" = "true" ]
  [ "$ENABLE_REFLECTOR" = "false" ]
  [ "$SILENT_BOOT" = "true" ]
}

@test "validate_config accepts valid values" {
  AUR_HELPER="paru"
  UPDATE_FREQUENCY="weekly"
  UPDATE_TIME="06:00"
  AUR_USER=""
  run validate_config
  [ "$status" -eq 0 ]
}

@test "validate_config rejects invalid AUR_HELPER" {
  AUR_HELPER="invalid"
  UPDATE_FREQUENCY="weekly"
  run validate_config
  [ "$status" -eq 1 ]
}

@test "validate_config rejects invalid UPDATE_FREQUENCY" {
  AUR_HELPER="paru"
  UPDATE_FREQUENCY="hourly"
  run validate_config
  [ "$status" -eq 1 ]
}

@test "validate_config rejects both invalid" {
  AUR_HELPER="invalid"
  UPDATE_FREQUENCY="hourly"
  run validate_config
  [ "$status" -eq 1 ]
}

@test "calendar_from_config generates daily expression" {
  UPDATE_FREQUENCY="daily"
  UPDATE_TIME="03:00"
  result="$(calendar_from_config)"
  [ "$result" = "*-*-* 03:00:00" ]
}

@test "calendar_from_config generates weekly expression" {
  UPDATE_FREQUENCY="weekly"
  UPDATE_TIME="06:00"
  result="$(calendar_from_config)"
  [ "$result" = "Mon *-*-* 06:00:00" ]
}

@test "calendar_from_config generates monthly expression" {
  UPDATE_FREQUENCY="monthly"
  UPDATE_TIME="12:00"
  result="$(calendar_from_config)"
  [ "$result" = "*-*-01 12:00:00" ]
}

@test "write_config creates parent directory" {
  UPDATERBTW_CONFIG="/tmp/updatebtw-test-dir/nested/config.conf"
  AUR_HELPER="paru"
  UPDATE_FREQUENCY="weekly"
  write_config
  [ -f "$UPDATERBTW_CONFIG" ]
  rm -rf "/tmp/updatebtw-test-dir"
}

@test "write_config rejects command substitution in UPDATE_TIME" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="weekly"
  UPDATE_TIME='$(touch /tmp/updatebtw-pwned)'
  run write_config
  [ "$status" -eq 1 ]
  [ ! -f /tmp/updatebtw-pwned ]
  [ ! -f "$UPDATERBTW_CONFIG" ] || ! grep -q 'pwned' "$UPDATERBTW_CONFIG"
}

@test "write_config rejects backticks in AUR_USER" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="weekly"
  AUR_USER='`id`'
  run write_config
  [ "$status" -eq 1 ]
}

@test "write_config rejects invalid AUR_HELPER" {
  AUR_HELPER="malicious"
  UPDATE_FREQUENCY="weekly"
  run write_config
  [ "$status" -eq 1 ]
}

@test "write_config rejects invalid UPDATE_FREQUENCY" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="hourly"
  run write_config
  [ "$status" -eq 1 ]
}

@test "write_config rejects invalid RUN_AT_BOOT" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="weekly"
  RUN_AT_BOOT="yes"
  run write_config
  [ "$status" -eq 1 ]
}

@test "write_config rejects invalid REFLECTOR_COUNTRY" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="weekly"
  REFLECTOR_COUNTRY='$(rm -rf /)'
  run write_config
  [ "$status" -eq 1 ]
}

@test "write_config rejects invalid AUR_USER with metacharacters" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="weekly"
  AUR_USER="foo; rm -rf /"
  run write_config
  [ "$status" -eq 1 ]
}

@test "write_config applies default when AUR_HELPER is empty" {
  AUR_HELPER=""
  UPDATE_FREQUENCY="weekly"
  write_config
  grep 'AUR_HELPER="yay"' "$UPDATERBTW_CONFIG"
}

@test "validate_config rejects invalid REFLECTOR_COUNTRY" {
  AUR_HELPER="yay"
  UPDATE_FREQUENCY="weekly"
  UPDATE_TIME="06:00"
  REFLECTOR_COUNTRY='bad;country'
  run validate_config
  [ "$status" -eq 1 ]
}

@test "_validate_config_value accepts valid values" {
  . "$UPDATERBTW_ROOT/config.sh"
  _validate_config_value AUR_HELPER yay
  _validate_config_value AUR_HELPER paru
  _validate_config_value UPDATE_TIME "06:00"
  _validate_config_value UPDATE_TIME "23:59"
  _validate_config_value RUN_AT_BOOT true
  _validate_config_value RUN_AT_BOOT false
  _validate_config_value AUR_USER aur_builder
  _validate_config_value FLATPAK_USER myuser
  _validate_config_value REFLECTOR_COUNTRY "United States"
  _validate_config_value REFLECTOR_INTERVAL "30"
  _validate_config_value BLACKLIST_MODULES "sp5100_tco,nouveau"
}

@test "_validate_config_value rejects invalid values" {
  . "$UPDATERBTW_ROOT/config.sh"
  run _validate_config_value AUR_HELPER malicious
  [ "$status" -eq 1 ]
  run _validate_config_value UPDATE_TIME "99:99"
  [ "$status" -eq 1 ]
  run _validate_config_value UPDATE_TIME '$(id)'
  [ "$status" -eq 1 ]
  run _validate_config_value RUN_AT_BOOT "maybe"
  [ "$status" -eq 1 ]
  run _validate_config_value AUR_USER "foo;bar"
  [ "$status" -eq 1 ]
  run _validate_config_value AUR_USER "../etc"
  [ "$status" -eq 1 ]
  run _validate_config_value REFLECTOR_COUNTRY '$(id)'
  [ "$status" -eq 1 ]
}
