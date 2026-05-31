load ../helpers/mocks.sh

setup_file() {
  export FIXTURES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../fixtures" && pwd)"
}

setup() {
  . "$UPDATERBTW_ROOT/backup.sh"
  . "$UPDATERBTW_ROOT/silent-boot.sh"
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

@test "patch_mkinitcpio replaces udev with systemd fsck" {
  local testfile="$(mktemp /tmp/updatebtw-mkinitcpio.XXXXXX)"
  cp "$FIXTURES_DIR/etc/mkinitcpio.conf" "$testfile"

  patch_mkinitcpio "$testfile"

  # udev replaced with systemd fsck, duplicate fsck removed
  grep -E "HOOKS=\(base systemd fsck autodetect modconf block filesystems keyboard\s*\)" "$testfile" >/dev/null
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
  local service="$testdir/systemd-fsck-root.service"

  cat > "$service" << 'EOF'
[Unit]
Description=File System Check on Root Device
Documentation=man:systemd-fsck-root.service(8)
DefaultDependencies=no
BindsTo=dev-%i.device
After=dev-%i.device
Before=local-fs.target
Wants=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/lib/systemd/systemd-fsck
TimeoutSec=0
EOF

  patch_fsck_services "$service"

  grep "StandardOutput=null" "$service" >/dev/null
  grep "StandardError=journal+console" "$service" >/dev/null
  rm -rf "$testdir"
}

@test "patch_fsck_services does not duplicate lines on re-run" {
  local testdir="$(mktemp -d /tmp/updatebtw-fsck-dedup.XXXXXX)"
  local service="$testdir/systemd-fsck-root.service"

  cat > "$service" << 'EOF'
[Unit]
Description=Test

[Service]
Type=oneshot
ExecStart=/bin/true
EOF

  # Run twice
  patch_fsck_services "$service"
  patch_fsck_services "$service"
  patch_fsck_services "$service"

  local count
  count="$(grep -c "StandardOutput=null" "$service" || true)"
  [ "$count" -eq 1 ]

  rm -rf "$testdir"
}
