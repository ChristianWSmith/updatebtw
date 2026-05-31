FROM archlinux:base-devel

# Install test and runtime dependencies
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
      bats \
      sudo \
      procps-ng \
      git \
      libnewt \
      reflector \
    && pacman -Scc --noconfirm

# Create test users
RUN useradd -m aur_builder && \
    useradd -m test_user && \
    echo "test_user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Create mock directories
RUN mkdir -p /var/lib/pacman /etc/pacman.d /boot/loader/entries

# Mock yay and paru as logging scripts (can't build AUR packages in CI)
RUN cat > /usr/local/bin/yay << 'EOF'
#!/bin/sh
echo "yay $*" >> /var/log/updatebtw-integration.log
EOF
RUN chmod +x /usr/local/bin/yay

RUN cat > /usr/local/bin/paru << 'EOF'
#!/bin/sh
echo "paru $*" >> /var/log/updatebtw-integration.log
EOF
RUN chmod +x /usr/local/bin/paru

# Mock flatpak as logging script
RUN cat > /usr/local/bin/flatpak << 'EOF'
#!/bin/sh
echo "flatpak $*" >> /var/log/updatebtw-integration.log
EOF
RUN chmod +x /usr/local/bin/flatpak

# Mock reflector as logging script
RUN cat > /usr/local/bin/reflector << 'EOF'
#!/bin/sh
echo "reflector $*" >> /var/log/updatebtw-integration.log
EOF
RUN chmod +x /usr/local/bin/reflector

# Mock systemd-inhibit (Docker has no systemd)
RUN cat > /usr/local/bin/systemd-inhibit << 'EOF'
#!/bin/sh
# Extract command after --mode=block and exec it
while [ $# -gt 0 ] && [ "$1" != "--mode=block" ]; do shift; done
shift 2>/dev/null
exec "$@"
EOF
RUN chmod +x /usr/local/bin/systemd-inhibit

# Mock systemctl
RUN cat > /usr/local/bin/systemctl << 'EOF'
#!/bin/sh
echo "systemctl $*" >> /var/log/updatebtw-integration.log
case "$1" in
  is-enabled)
    case "$2" in
      updatebtw-update.timer)
        if [ -f /etc/systemd/system/updatebtw-update.timer ]; then
          echo "enabled"
          exit 0
        else
          echo "disabled"
          exit 3
        fi
        ;;
    esac
    exit 0
    ;;
esac
EOF
RUN chmod +x /usr/local/bin/systemctl

# Create a fresh mirrorlist for reflector tests
RUN echo "Server = https://mirror.archlinux.org/aur/$arch/latest" > /etc/pacman.d/mirrorlist
RUN touch -t 202001010000 /etc/pacman.d/mirrorlist

# Create mock mkinitcpio.conf for silent boot tests
RUN cat > /etc/mkinitcpio.conf << 'EOF'
# vim:set ft=sh
MODULES=()
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)
EOF

# Create mock systemd-fsck services
RUN mkdir -p /usr/lib/systemd/system
RUN cat > /usr/lib/systemd/system/systemd-fsck@.service << 'EOF'
[Unit]
Description=File System Check on %f
Documentation=man:systemd-fsck@.service(8)

[Service]
Type=oneshot
ExecStart=/usr/lib/systemd/systemd-fsck
EOF

RUN cat > /usr/lib/systemd/system/systemd-fsck-root.service << 'EOF'
[Unit]
Description=File System Check on Root Device
Documentation=man:systemd-fsck@.service(8)

[Service]
Type=oneshot
ExecStart=/usr/lib/systemd/systemd-fsck
EOF

# Create mock boot entries for silent boot tests
RUN cat > /boot/loader/entries/arch.conf << 'EOF'
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=12345678-1234-1234-1234-123456789012 rw
EOF

# Create loader.conf so detect_bootloader returns systemd-boot
RUN cat > /boot/loader/loader.conf << 'EOF'
default arch.conf
timeout 4
EOF

# Copy project
COPY . /opt/updatebtw
WORKDIR /opt/updatebtw

# Make entry point executable
RUN chmod +x src/updatebtw

CMD ["bats", "tests/integration/bats/"]
