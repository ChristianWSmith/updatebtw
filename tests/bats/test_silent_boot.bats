load ../helpers/mocks.sh

setup_file() {
  export FIXTURES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../fixtures" && pwd)"
}

setup() {
  mocks_setup
  . "$UPDATERBTW_ROOT/backup.sh"
  . "$UPDATERBTW_ROOT/silent-boot.sh"
}

teardown() {
  mocks_teardown
}

@test "set_kernel_options removes existing options and adds new ones" {
  local testdir="$(mktemp -d /tmp/updatebtw-testboot.XXXXXX)"
  local entry="$testdir/arch.conf"
  cp "$FIXTURES_DIR/boot/loader/entries/arch.conf" "$entry"

  set_kernel_options "$testdir" "quiet loglevel=3 audit=0"

  grep "options" "$entry" | grep -v "^#" > /tmp/options_line.txt
  local opts="$(cat /tmp/options_line.txt)"

  # Should keep non-matching options (root= and rw not in new options)
  [[ "$opts" == *"root=PARTUUID"* ]]
  [[ "$opts" == *" rw "* ]]
  # Should remove old options that conflict with new ones (quiet, loglevel=3 appear only once)
  [[ "$opts" == *"quiet"* ]]
  [[ "$opts" == *"loglevel=3"* ]]
  # Should have the new options
  [[ "$opts" == *"audit=0"* ]]

  rm -rf "$testdir"
}

@test "set_kernel_options preserves entry structure" {
  local testdir="$(mktemp -d /tmp/updatebtw-testboot.XXXXXX)"
  local entry="$testdir/arch.conf"
  cp "$FIXTURES_DIR/boot/loader/entries/arch.conf" "$entry"

  set_kernel_options "$testdir" "quiet loglevel=3 audit=0"

  grep "^title " "$entry" >/dev/null
  grep "^linux " "$entry" >/dev/null
  grep "^initrd " "$entry" >/dev/null
  grep "^options " "$entry" >/dev/null

  rm -rf "$testdir"
}

@test "set_kernel_options creates backup" {
  local testdir="$(mktemp -d /tmp/updatebtw-testboot.XXXXXX)"
  local entry="$testdir/arch.conf"
  cp "$FIXTURES_DIR/boot/loader/entries/arch.conf" "$entry"

  set_kernel_options "$testdir" "quiet"

  local name="$(basename "$entry")"
  ls "$BACKUP_DIR/${name}."* >/dev/null 2>&1
  [ "$?" -eq 0 ]

  rm -rf "$testdir"
}

@test "set_printk writes correct content" {
  local dest="$(mktemp /tmp/updatebtw-printk.XXXXXX)"

  set_printk "$dest"

  grep "kernel.printk = 3 3 3 3" "$dest" >/dev/null
  rm -f "$dest"
}

@test "set_printk creates parent directory" {
  local dest="/tmp/updatebtw-printk-test/20-quiet-printk.conf"

  set_printk "$dest"

  [ -f "$dest" ]
  [ "$(cat "$dest")" = "kernel.printk = 3 3 3 3" ]
  rm -rf "/tmp/updatebtw-printk-test"
}

@test "patch_mkinitcpio replaces udev with systemd and removes fsck" {
  local testfile="$(mktemp /tmp/updatebtw-mkinitcpio.XXXXXX)"
  cp "$FIXTURES_DIR/etc/mkinitcpio.conf" "$testfile"

  patch_mkinitcpio "$testfile"

  # udev replaced with systemd, fsck removed per Arch Wiki
  grep -E "HOOKS=\(base systemd autodetect modconf block filesystems keyboard\s*\)" "$testfile" >/dev/null
  rm -f "$testfile"
}

@test "patch_mkinitcpio creates backup" {
  local testfile="$(mktemp /tmp/updatebtw-mkinitcpio.XXXXXX)"
  cp "$FIXTURES_DIR/etc/mkinitcpio.conf" "$testfile"

  patch_mkinitcpio "$testfile"

  local name="$(basename "$testfile")"
  ls "$BACKUP_DIR/${name}."* >/dev/null 2>&1
  [ "$?" -eq 0 ]

  rm -f "$testfile"
}

@test "patch_fsck_services adds StandardOutput and StandardError" {
  local testdir="$(mktemp -d /tmp/updatebtw-fsck.XXXXXX)"

  patch_fsck_services

  local override_file="/etc/systemd/system/systemd-fsck@.service.d/silent.conf"
  [ -f "$override_file" ]
  grep "StandardOutput=null" "$override_file" >/dev/null
  grep "StandardError=journal+console" "$override_file" >/dev/null
  rm -rf "$testdir"
}

@test "patch_fsck_services does not duplicate lines on re-run" {
  patch_fsck_services
  patch_fsck_services
  patch_fsck_services

  local override_file="/etc/systemd/system/systemd-fsck@.service.d/silent.conf"
  local count
  count="$(grep -c "StandardOutput=null" "$override_file" || true)"
  [ "$count" -eq 1 ]
}

@test "detect_bootloader returns systemd-boot when loader.conf exists" {
  local testdir="$(mktemp -d /tmp/updatebtw-bootloader.XXXXXX)"
  mkdir -p "$testdir/boot/loader"
  touch "$testdir/boot/loader/loader.conf"

  local test_script="$(mktemp /tmp/test_detect.XXXXXX.sh)"
  cat > "$test_script" << 'SCRIPT'
#!/bin/sh
detect_bootloader_test() {
  local loader_conf="$1"
  local grub_conf="$2"
  [ -f "$loader_conf" ] && echo "systemd-boot" && return 0
  [ -f "$grub_conf" ] && echo "grub" && return 0
  echo "unknown"
  return 0
}
detect_bootloader_test "$1" "$2"
SCRIPT
  chmod +x "$test_script"

  local result
  result="$("$test_script" "$testdir/boot/loader/loader.conf" "/nonexistent/grub")"
  [ "$result" = "systemd-boot" ]

  rm -f "$test_script"
  rm -rf "$testdir"
}

@test "detect_bootloader returns grub when /etc/default/grub exists" {
  local testdir="$(mktemp -d /tmp/updatebtw-bootloader.XXXXXX)"
  mkdir -p "$testdir/etc/default"
  touch "$testdir/etc/default/grub"

  local test_script="$(mktemp /tmp/test_detect.XXXXXX.sh)"
  cat > "$test_script" << 'SCRIPT'
#!/bin/sh
detect_bootloader_test() {
  local loader_conf="$1"
  local grub_conf="$2"
  [ -f "$loader_conf" ] && echo "systemd-boot" && return 0
  [ -f "$grub_conf" ] && echo "grub" && return 0
  echo "unknown"
  return 0
}
detect_bootloader_test "$1" "$2"
SCRIPT
  chmod +x "$test_script"

  local result
  result="$("$test_script" "/nonexistent/loader.conf" "$testdir/etc/default/grub")"
  [ "$result" = "grub" ]

  rm -f "$test_script"
  rm -rf "$testdir"
}

@test "detect_bootloader returns unknown when neither exists" {
  local test_script="$(mktemp /tmp/test_detect.XXXXXX.sh)"
  cat > "$test_script" << 'SCRIPT'
#!/bin/sh
detect_bootloader_test() {
  local loader_conf="$1"
  local grub_conf="$2"
  [ -f "$loader_conf" ] && echo "systemd-boot" && return 0
  [ -f "$grub_conf" ] && echo "grub" && return 0
  echo "unknown"
  return 0
}
detect_bootloader_test "$1" "$2"
SCRIPT
  chmod +x "$test_script"

  local result
  result="$("$test_script" "/nonexistent/loader.conf" "/nonexistent/grub")"
  [ "$result" = "unknown" ]

  rm -f "$test_script"
}

@test "set_grub_silent sets GRUB_DEFAULT=0" {
  local testfile="$(mktemp /tmp/updatebtw-grub.XXXXXX)"
  cp "$FIXTURES_DIR/etc/grub/grub" "$testfile"

  set_grub_silent "$testfile"

  grep "^GRUB_DEFAULT=0$" "$testfile" >/dev/null
  rm -f "$testfile"
}

@test "set_grub_silent sets GRUB_TIMEOUT=0" {
  local testfile="$(mktemp /tmp/updatebtw-grub.XXXXXX)"
  cp "$FIXTURES_DIR/etc/grub/grub" "$testfile"

  set_grub_silent "$testfile"

  grep "^GRUB_TIMEOUT=0$" "$testfile" >/dev/null
  rm -f "$testfile"
}

@test "set_grub_silent sets GRUB_RECORDFAIL_TIMEOUT=10" {
  local testfile="$(mktemp /tmp/updatebtw-grub.XXXXXX)"
  cp "$FIXTURES_DIR/etc/grub/grub" "$testfile"

  set_grub_silent "$testfile"

  grep "^GRUB_RECORDFAIL_TIMEOUT=10$" "$testfile" >/dev/null
  rm -f "$testfile"
}

@test "set_grub_silent preserves other GRUB settings" {
  local testfile="$(mktemp /tmp/updatebtw-grub.XXXXXX)"
  cp "$FIXTURES_DIR/etc/grub/grub" "$testfile"

  set_grub_silent "$testfile"

  grep "^GRUB_DISTRIBUTOR=" "$testfile" >/dev/null
  grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$testfile" >/dev/null
  rm -f "$testfile"
}

@test "set_grub_silent creates backup" {
  local testfile="$(mktemp /tmp/updatebtw-grub.XXXXXX)"
  cp "$FIXTURES_DIR/etc/grub/grub" "$testfile"

  set_grub_silent "$testfile"

  local name="$(basename "$testfile")"
  ls "$BACKUP_DIR/${name}."* >/dev/null 2>&1
  [ "$?" -eq 0 ]

  rm -f "$testfile"
}

@test "set_grub_silent appends missing keys" {
  local testfile="$(mktemp /tmp/updatebtw-grub-minimal.XXXXXX)"
  cat > "$testfile" << 'EOF'
GRUB_DISTRIBUTOR="Arch"
EOF

  set_grub_silent "$testfile"

  grep "^GRUB_DEFAULT=0$" "$testfile" >/dev/null
  grep "^GRUB_TIMEOUT=0$" "$testfile" >/dev/null
  grep "^GRUB_RECORDFAIL_TIMEOUT=10$" "$testfile" >/dev/null
  rm -f "$testfile"
}

@test "set_grub_silent does not duplicate existing keys" {
  local testfile="$(mktemp /tmp/updatebtw-grub-dup.XXXXXX)"
  cat > "$testfile" << 'EOF'
GRUB_DEFAULT=5
GRUB_TIMEOUT=10
GRUB_RECORDFAIL_TIMEOUT=10
GRUB_DISTRIBUTOR="Arch"
EOF

  set_grub_silent "$testfile"

  local count_default count_timeout count_recordfail
  count_default="$(grep -c "^GRUB_DEFAULT=" "$testfile" || true)"
  count_timeout="$(grep -c "^GRUB_TIMEOUT=" "$testfile" || true)"
  count_recordfail="$(grep -c "^GRUB_RECORDFAIL_TIMEOUT=" "$testfile" || true)"

  [ "$count_default" -eq 1 ]
  [ "$count_timeout" -eq 1 ]
  [ "$count_recordfail" -eq 1 ]
  rm -f "$testfile"
}
