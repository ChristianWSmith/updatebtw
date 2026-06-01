# Integration tests for silent boot

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

  # Reset mock files to original state
  cat > /etc/mkinitcpio.conf << 'EOF'
# vim:set ft=sh
MODULES=()
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)
EOF

  cat > /usr/lib/systemd/system/systemd-fsck@.service << 'EOF'
[Unit]
Description=File System Check on %f
Documentation=man:systemd-fsck@.service(8)

[Service]
Type=oneshot
ExecStart=/usr/lib/systemd/systemd-fsck
EOF

  cat > /usr/lib/systemd/system/systemd-fsck-root.service << 'EOF'
[Unit]
Description=File System Check on Root Device
Documentation=man:systemd-fsck@.service(8)

[Service]
Type=oneshot
ExecStart=/usr/lib/systemd/systemd-fsck
EOF

  cat > /boot/loader/entries/arch.conf << 'EOF'
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=12345678-1234-1234-1234-123456789012 rw
EOF

  cat > /boot/loader/loader.conf << 'EOF'
default arch.conf
timeout 4
EOF

  rm -f /etc/sysctl.d/20-quiet-printk.conf
  rm -f /root/.hushlogin
}

@test "silent boot patches mkinitcpio.conf" {
  sudo SILENT_BOOT=true bash "$INSTALLER" --non-interactive

  local content
  content="$(cat /etc/mkinitcpio.conf)"
  [[ "$content" == *"systemd"* ]]
  [[ "$content" == *"fsck"* ]]
}

@test "silent boot writes printk config" {
  sudo SILENT_BOOT=true bash "$INSTALLER" --non-interactive

  [ -f /etc/sysctl.d/20-quiet-printk.conf ]
  local content
  content="$(cat /etc/sysctl.d/20-quiet-printk.conf)"
  [[ "$content" == *"kernel.printk = 3 3 3 3"* ]]
}

@test "silent boot patches fsck services" {
  sudo SILENT_BOOT=true bash "$INSTALLER" --non-interactive

  local fsck_content
  fsck_content="$(cat /etc/systemd/system/systemd-fsck@.service.d/silent.conf)"
  [[ "$fsck_content" == *"StandardOutput=null"* ]]
  [[ "$fsck_content" == *"StandardError=journal+console"* ]]
}

@test "silent boot modifies boot entry options" {
  sudo SILENT_BOOT=true bash "$INSTALLER" --non-interactive

  local content
  content="$(cat /boot/loader/entries/arch.conf)"
  [[ "$content" == *"quiet"* ]]
  [[ "$content" == *"loglevel=3"* ]]
}

@test "silent boot creates hushlogin" {
  sudo SILENT_BOOT=true bash "$INSTALLER" --non-interactive

  [ -f /root/.hushlogin ]
}

@test "silent boot creates backup of mkinitcpio.conf" {
  sudo SILENT_BOOT=true bash "$INSTALLER" --non-interactive

  ls /var/lib/updatebtw/backups/mkinitcpio.conf.* >/dev/null 2>&1
}

@test "silent boot creates backup of boot entry" {
  sudo SILENT_BOOT=true bash "$INSTALLER" --non-interactive

  ls /var/lib/updatebtw/backups/arch.conf.* >/dev/null 2>&1
}
