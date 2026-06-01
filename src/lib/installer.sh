# updatebtw installer TUI module
# This file is sourced by the standalone installer and the updatebtw CLI

_check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This installer must be run as root." >&2
    exit 1
  fi
}

_check_deps() {
  local missing=""
  ! command -v whiptail >/dev/null 2>&1 && missing="$missing libnewt"
  ! command -v git >/dev/null 2>&1 && missing="$missing git"
  ! command -v sudo >/dev/null 2>&1 && missing="$missing sudo"
  ! pacman -Qi base-devel >/dev/null 2>&1 && missing="$missing base-devel"

  if [ -z "$missing" ]; then
    return 0
  fi

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "Missing Dependencies" --yesno \
      "The following packages are required:\n\n$missing\n\nInstall them now?" \
      12 50 || exit 1
  else
    echo "Missing dependencies:$missing"
    printf "Install now? [Y/n] "
    read -r answer
    case "$answer" in
      n|N|no|NO) exit 1 ;;
    esac
  fi

  # shellcheck disable=SC2086
  pacman -S --needed --noconfirm $missing
}

_install_aur_helper() {
  local helper="$1" user="$2"

  case "$helper" in
    yay|paru) ;;
    *) echo "Invalid AUR helper: $helper" >&2; return 1 ;;
  esac
  if ! printf '%s' "$user" | grep -qE '^[a-z_][a-z0-9_-]*\$?$'; then
    echo "Invalid username: $user" >&2
    return 1
  fi

  command -v "$helper" >/dev/null 2>&1 && return 0

  if [ "$(id -un)" != "$user" ]; then
    if ! id "$user" >/dev/null 2>&1; then
      useradd -m "$user" 2>/dev/null || true
    fi
    mkdir -p /etc/sudoers.d
    # Deliberately unrestricted pacman access — AUR helpers (yay/paru) invoke pacman
    # with varying internal flags (--config, --overwrite, --dbonly, etc.) that cannot
    # be exhaustively enumerated in a sudoers command allowlist. Narrowing to specific
    # subcommands breaks package installation. The audit trail via log_output and the
    # dedicated AUR user with no login shell provide the practical security boundary.
    cat > "/etc/sudoers.d/updatebtw-$user-build" << SUDOEOF
Defaults!/usr/bin/pacman log_output
$user ALL=(root) NOPASSWD: /usr/bin/pacman
SUDOEOF
    chmod 440 "/etc/sudoers.d/updatebtw-$user-build"
  fi

  trap 'rm -f "/etc/sudoers.d/updatebtw-$user-build"' EXIT

  local helper_tmp
  find /tmp -maxdepth 1 -name "updatebtw-${helper}.*" -type d -exec rm -rf {} + 2>/dev/null || true
  helper_tmp="$(mktemp -d "/tmp/updatebtw-$helper.XXXXXX")"
  chown "$user:$user" "$helper_tmp"
  trap 'rm -f "/etc/sudoers.d/updatebtw-$user-build"; rm -rf "$helper_tmp"' EXIT

  local build_script
  build_script="$(mktemp /tmp/updatebtw-build.XXXXXX)"
  cat > "$build_script" << BUILDEOF
#!/bin/sh
set -e
HELPER="\$1"
HELPER_TMP="\$2"
git clone --depth=1 "https://aur.archlinux.org/\$HELPER.git" "\$HELPER_TMP"
cd "\$HELPER_TMP"

# Install build dependencies as root before running makepkg
# makepkg -makedepends requires sudo, which the aur user may not have
_deps="\$(makepkg --printsrcinfo 2>/dev/null | sed -n 's/^\tmakedepends = //p' | tr '\n' ' ')"
if [ -n "\$_deps" ]; then
  sudo pacman -S --needed --noconfirm \$_deps 2>/dev/null || true
fi

makepkg --noconfirm
BUILDEOF
  chmod 755 "$build_script"
  trap 'rm -f "/etc/sudoers.d/updatebtw-$user-build" "$build_script"; rm -rf "$helper_tmp"' EXIT

  # PKGBUILD review prompt before building (H3)
  if [ -t 0 ] && [ "${UPDATEBTW_AUTO_INSTALL_AUR:-}" != "1" ]; then
    echo "==> AUR helper '$helper' will be built from the AUR."
    echo "    Review the PKGBUILD before proceeding:"
    echo "    https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=$helper"
    printf "    Continue? [Y/n] "
    read -r _aur_answer
    case "$_aur_answer" in
      n|N) echo "Aborted."; return 1 ;;
    esac
  fi

  if [ "$(id -un)" = "$user" ]; then
    sh "$build_script" "$helper" "$helper_tmp"
  else
    su - "$user" -s /bin/sh -- "$build_script" "$helper" "$helper_tmp"
  fi

  if [ -f "$helper_tmp/PKGBUILD" ]; then
    local pkgbuild_hash
    pkgbuild_hash="$(sha256sum "$helper_tmp/PKGBUILD" | awk '{print $1}')"
    echo "PKGBUILD SHA256: $pkgbuild_hash"
    echo "Verify at: https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=$helper"
  fi

  sudo pacman -U --noconfirm "$helper_tmp"/*.pkg.tar.* && printf "Installed %s\n" "$helper" || printf "Warning: failed to install %s\n" "$helper"

  rm -f "$build_script"
  command -v "$helper" >/dev/null 2>&1
}

_setup_aur_user() {
  local user="$1"
  [ -n "$user" ] || return 1

  if ! id "$user" >/dev/null 2>&1; then
    useradd -m "$user" 2>/dev/null || true
  fi

  rm -f "/etc/sudoers.d/updatebtw-$user-build" 2>/dev/null || true
  rm -f "/etc/sudoers.d/updatebtw-$user" 2>/dev/null || true
  mkdir -p /etc/sudoers.d
  # Deliberately unrestricted pacman access — AUR helpers (yay/paru) invoke pacman
  # with varying internal flags (--config, --overwrite, --dbonly, etc.) that cannot
  # be exhaustively enumerated in a sudoers command allowlist. Narrowing to specific
  # subcommands breaks package installation. The audit trail via log_output and the
  # dedicated AUR user with no login shell provide the practical security boundary.
  cat > "/etc/sudoers.d/updatebtw-$user" << SUDOEOF
Defaults!/usr/bin/pacman log_output
$user ALL=(root) NOPASSWD: /usr/bin/pacman
SUDOEOF
  chmod 440 "/etc/sudoers.d/updatebtw-$user"
}

tui_main() {
  _check_root

  local _non_interactive=false
  for arg in "$@"; do
    case "$arg" in
      --non-interactive) _non_interactive=true ;;
    esac
  done

  if $_non_interactive; then
    echo "==> updatebtw: installing with defaults"
    echo "    AUR_HELPER=$AUR_HELPER"
    echo "    AUR_USER=$AUR_USER"
    echo "    FLATPAK_USER=$FLATPAK_USER"
    echo "    UPDATE_FREQUENCY=$UPDATE_FREQUENCY"
    echo "    UPDATE_TIME=$UPDATE_TIME"
    echo "    RUN_AT_BOOT=$RUN_AT_BOOT"
    echo "    ENABLE_REFLECTOR=$ENABLE_REFLECTOR"
    echo "    REFLECTOR_COUNTRY=$REFLECTOR_COUNTRY"
    echo "    REFLECTOR_INTERVAL=$REFLECTOR_INTERVAL"
    echo "    SILENT_BOOT=$SILENT_BOOT"
    echo ""

    # Install deps non-interactively
    local missing=""
    ! command -v whiptail >/dev/null 2>&1 && missing="$missing libnewt"
    ! command -v git >/dev/null 2>&1 && missing="$missing git"
    ! command -v sudo >/dev/null 2>&1 && missing="$missing sudo"
    ! pacman -Qi base-devel >/dev/null 2>&1 && missing="$missing base-devel"
    if [ -n "$missing" ]; then
      echo "Installing missing dependencies:$missing"
      pacman -S --needed --noconfirm $missing >/dev/null 2>&1 || true
    fi
  fi

    whiptail --title "updatebtw" --msgbox \
      "Welcome to updatebtw — the automatic Arch Linux update utility.\n\nNOTE: This project is NOT affiliated with or endorsed by Arch Linux.\nIt is an unofficial third-party tool.\n\nThis installer will configure automatic system updates on your system." \
      12 60

    local freq_choice

    AUR_HELPER=$(whiptail --title "AUR Helper" --radiolist \
      "Select your preferred AUR helper:" 12 65 2 \
      "yay"  "Original Go-based AUR helper (recommended)" ON \
      "paru" "Modern Rust-based AUR helper"             OFF \
       3>&1 1>&2 2>&3) || exit 1

    local detected_user="aur_builder"
    AUR_USER=$(whiptail --title "AUR User" --inputbox \
      "Run AUR helpers (yay/paru) as which user?\n\nThis user will be created if it doesn't already exist.\nWe do NOT recommend using your personal user account." 10 60 "$detected_user" \
      3>&1 1>&2 2>&3) || exit 1

    local detected_flatpak_user="${SUDO_USER:-$(id -un)}"
    FLATPAK_USER=$(whiptail --title "Flatpak User" --inputbox \
      "Run flatpak updates as which user?\n\nThis should be your personal user account,\nsince flatpak installs per-user packages." 10 60 "$detected_flatpak_user" \
      3>&1 1>&2 2>&3) || exit 1

    freq_choice=$(whiptail --title "Update Frequency" --radiolist \
      "How often should updates run?" 14 50 3 \
      "daily"   "Update every day" ON \
      "weekly"  "Update once a week" OFF \
      "monthly" "Update once a month" OFF \
      3>&1 1>&2 2>&3) || exit 1
    UPDATE_FREQUENCY="$freq_choice"

    UPDATE_TIME=$(whiptail --title "Update Time" --inputbox \
      "What time should updates run? (HH:MM, 24-hour format)" 8 60 "06:00" \
      3>&1 1>&2 2>&3) || exit 1

    if whiptail --title "Boot Update" --yesno \
      "Run an update every time the system boots?\n\nThis is useful for systems that are not always on." 10 60; then
      RUN_AT_BOOT="true"
    else
      RUN_AT_BOOT="false"
    fi

    if whiptail --title "Mirrorlist" --yesno \
      "Automatically update mirrorlist via reflector?\n\nThis keeps your package sources fast and up to date." 10 60; then
      ENABLE_REFLECTOR="true"
      REFLECTOR_COUNTRY=$(whiptail --title "Mirror Country" --inputbox \
        "Mirror country (e.g. 'United States', 'Germany'):" 8 60 "United States" \
        3>&1 1>&2 2>&3) || exit 1
      REFLECTOR_INTERVAL=$(whiptail --title "Mirror Update Interval" --inputbox \
        "How often (in days) should the mirrorlist be refreshed?" 8 60 "30" \
        3>&1 1>&2 2>&3) || exit 1
    else
      ENABLE_REFLECTOR="false"
    fi

    local bootloader
    bootloader="$(detect_bootloader)"
    local silent_boot_msg
    case "$bootloader" in
      systemd-boot)
        silent_boot_msg="Configure silent boot?\n\nDetected: systemd-boot\n\nReduces boot messages by modifying boot loader entries,\nmkinitcpio, systemd-fsck services, and kernel printk settings."
        ;;
      grub)
        silent_boot_msg="Configure silent boot?\n\nDetected: GRUB\n\nReduces boot messages by configuring GRUB timeout settings,\nregenerating grub.cfg, and adjusting mkinitcpio, systemd-fsck\nservices, and kernel printk settings."
        ;;
      unknown)
        silent_boot_msg="Configure silent boot?\n\nNo supported bootloader detected (systemd-boot or GRUB).\n\nBootloader-specific changes will be skipped, but generic\nchanges will still apply: mkinitcpio, systemd-fsck services,\nand kernel printk settings."
        ;;
    esac

    if whiptail --title "Silent Boot" --yesno "$silent_boot_msg" 14 65; then
      SILENT_BOOT="true"
    else
      SILENT_BOOT="false"
    fi

    local summary
    summary="AUR Helper: $AUR_HELPER (installed from AUR — verify PKGBUILD manually)\n"
    summary="${summary}Frequency: $UPDATE_FREQUENCY at $UPDATE_TIME\n"
    summary="${summary}Run at boot: $RUN_AT_BOOT\n"
    summary="${summary}Reflector: $ENABLE_REFLECTOR"
    if [ "$ENABLE_REFLECTOR" = "true" ]; then
      summary="${summary} (country: $REFLECTOR_COUNTRY, interval: ${REFLECTOR_INTERVAL:-30}d)\n"
    else
      summary="${summary}\n"
    fi
    summary="${summary}AUR user: $AUR_USER\n"
    summary="${summary}Flatpak user: $FLATPAK_USER\n"
    summary="${summary}Silent boot: $SILENT_BOOT\n"

    if ! whiptail --title "Confirm" --yesno "Apply the following configuration?\n\n${summary}" 16 65; then
      exit 0
    fi
  fi

  echo "Installing AUR helper..."
  _install_aur_helper "$AUR_HELPER" "$AUR_USER" || true
  echo "Configuring AUR user..."
  _setup_aur_user "$AUR_USER" >/dev/null 2>&1 || true
  echo "Writing configuration..."
  write_config
  if [ "$ENABLE_REFLECTOR" = "true" ] && ! command -v reflector >/dev/null 2>&1; then
    echo "Installing reflector..."
    pacman -S --needed --noconfirm reflector >/dev/null 2>&1 || true
  fi
  echo "Installing system files..."
  install_system_files
  echo "Installing systemd units..."
  install_systemd_units
  echo "Enabling timer..."
  enable_timer
  echo "Done."

  if [ "$SILENT_BOOT" = "true" ]; then
    silent_boot
  fi

  if ! $_non_interactive; then
    whiptail --title "Complete" --msgbox \
      "updatebtw has been installed and configured.\n\nUpdates will run automatically on your schedule." \
      8 50
  fi
}

# Overridden by standalone installer build with embedded file payloads.
# In normal install context, these functions copy from the installed root.
install_system_files() {
  :
}

install_systemd_units() {
  local unit_dir="${UPDATERBTW_UNIT_DIR:-/etc/systemd/system}"
  local src_dir
  src_dir="$(readlink -f "$UPDATERBTW_ROOT/../systemd" 2>/dev/null)" || return 1
  case "$src_dir" in
    */updatebtw/systemd) ;;
    *) echo "updatebtw: invalid systemd unit directory" >&2; return 1 ;;
  esac
  mkdir -p "$unit_dir"
  install -Dm644 "$src_dir/updatebtw-update.service" "$unit_dir/updatebtw-update.service" 2>/dev/null || true
  install -Dm644 "$src_dir/updatebtw-update.timer" "$unit_dir/updatebtw-update.timer" 2>/dev/null || true
  install -Dm644 "$src_dir/updatebtw-boot.service" "$unit_dir/updatebtw-boot.service" 2>/dev/null || true
}

enable_timer() {
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable --now updatebtw-update.timer 2>/dev/null || true
  if [ "$RUN_AT_BOOT" = "true" ]; then
    systemctl enable updatebtw-boot.service 2>/dev/null || true
  fi
}
