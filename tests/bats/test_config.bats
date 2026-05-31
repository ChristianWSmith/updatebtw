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
