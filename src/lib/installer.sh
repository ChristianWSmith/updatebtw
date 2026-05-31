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
  command -v "$helper" >/dev/null 2>&1 && return 0

  if [ "$(id -un)" != "$user" ]; then
    if ! id "$user" >/dev/null 2>&1; then
      useradd -m "$user" 2>/dev/null || true
    fi
    mkdir -p /etc/sudoers.d
    echo "$user ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$user" 2>/dev/null || true
  fi

  rm -rf "/tmp/$helper" 2>/dev/null || true
  if [ "$(id -un)" = "$user" ]; then
    git clone --depth=1 "https://aur.archlinux.org/$helper.git" "/tmp/$helper"
    cd "/tmp/$helper"
    makepkg -si --noconfirm
  else
    su - "$user" -c "
      git clone --depth=1 https://aur.archlinux.org/$helper.git /tmp/$helper
      cd /tmp/$helper
      makepkg -si --noconfirm
    "
  fi && printf "Installed %s\n" "$helper" || printf "Warning: failed to install %s\n" "$helper"

  command -v "$helper" >/dev/null 2>&1
}

_setup_aur_user() {
  local user="$1"
  [ -n "$user" ] || return 1

  if ! id "$user" >/dev/null 2>&1; then
    useradd -m "$user" 2>/dev/null || true
  fi

  rm -f "/etc/sudoers.d/$user" 2>/dev/null || true
  mkdir -p /etc/sudoers.d
  echo "$user ALL=(ALL) NOPASSWD: /usr/bin/pacman" > "/etc/sudoers.d/updatebtw-$user"
}

tui_main() {
  _check_root
  _check_deps

  whiptail() { command whiptail "$@" </dev/tty; }

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

  if whiptail --title "Silent Boot" --yesno \
    "Configure silent boot?\n\nReduces kernel messages during boot for a cleaner experience.\nModifies boot loader entries, mkinitcpio, and systemd-fsck services." 12 60; then
    SILENT_BOOT="true"
  else
    SILENT_BOOT="false"
  fi

  local summary
  summary="AUR Helper: $AUR_HELPER\n"
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

  whiptail --title "Complete" --msgbox \
    "updatebtw has been installed and configured.\n\nUpdates will run automatically on your schedule." \
    8 50
}

# Overridden by standalone installer build with embedded file payloads.
# In normal install context, these functions copy from the installed root.
install_system_files() {
  :
}

install_systemd_units() {
  local unit_dir="${UPDATERBTW_UNIT_DIR:-/etc/systemd/system}"
  mkdir -p "$unit_dir"
  install -Dm644 "$UPDATERBTW_ROOT/../systemd/updatebtw-update.service" "$unit_dir/updatebtw-update.service" 2>/dev/null || true
  install -Dm644 "$UPDATERBTW_ROOT/../systemd/updatebtw-update.timer" "$unit_dir/updatebtw-update.timer" 2>/dev/null || true
  install -Dm644 "$UPDATERBTW_ROOT/../systemd/updatebtw-boot.service" "$unit_dir/updatebtw-boot.service" 2>/dev/null || true
}

enable_timer() {
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable --now updatebtw-update.timer 2>/dev/null || true
  if [ "$RUN_AT_BOOT" = "true" ]; then
    systemctl enable updatebtw-boot.service 2>/dev/null || true
  fi
}
