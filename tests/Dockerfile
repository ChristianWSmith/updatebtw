FROM archlinux:base-devel

# Install test dependencies
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
      bats \
      sudo \
      procps-ng \
    && pacman -Scc --noconfirm

# Create test user (for running pacman/yay tests if needed)
RUN useradd -m builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Create mock directories
RUN mkdir -p /var/lib/pacman /etc/pacman.d /boot/loader/entries

# Copy project
COPY . /opt/updatebtw
WORKDIR /opt/updatebtw

# Make entry point executable
RUN chmod +x src/updatebtw

CMD ["bats", "tests/bats/"]
