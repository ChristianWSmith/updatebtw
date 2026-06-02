# updatebtw updater module

UPDATERBTW_STATE_DIR="${UPDATERBTW_STATE_DIR:-/var/lib/updatebtw}"
: "${UPDATERBTW_MIN_UPDATE_INTERVAL:=300}"
_update_lock_fd=""

_check_rate_limit() {
  local state_file="$UPDATERBTW_STATE_DIR/last_update"
  local lock_file="$UPDATERBTW_STATE_DIR/update.lock"
  mkdir -p "$UPDATERBTW_STATE_DIR"
  chmod 700 "$UPDATERBTW_STATE_DIR"

  exec 8> "$lock_file"
  chmod 600 "$lock_file"
  if ! flock -n 8; then
    _notify error "Update In Progress" "Another update is already running"
    return 1
  fi
  _update_lock_fd=8

  if [ -f "$state_file" ]; then
    local last_update now delta
    last_update="$(cat "$state_file")"
    now="$(date "+%s")"
    delta=$(( now - last_update ))
    if [ "$delta" -lt "$UPDATERBTW_MIN_UPDATE_INTERVAL" ]; then
      _notify error "Update Throttled" "Last update was $(( delta ))s ago, minimum interval is ${UPDATERBTW_MIN_UPDATE_INTERVAL}s"
      return 1
    fi
  fi

  return 0
}

_release_locks() {
  [ -n "$_update_lock_fd" ] && flock -u "$_update_lock_fd" 2>/dev/null || true
  flock -u 7 2>/dev/null || true
  rm -f "$UPDATERBTW_STATE_DIR/updatebtw.lock" 2>/dev/null || true
}

update_packages() {
  trap '_notify critical "updatebtw" "Shutdown blocked — system update in progress, please wait"' SIGTERM
  read_config

  if ! _check_rate_limit; then
    return 1
  fi

  trap '_release_locks; _notify critical "updatebtw" "Shutdown blocked — system update in progress, please wait"' EXIT SIGTERM

  _cleanup_old_backups 2>/dev/null || true
  _cleanup_old_logs 2>/dev/null || true

  if [ -e /var/lib/pacman/db.lck ]; then
    _notify error "Update Failed" "/var/lib/pacman/db.lck exists"
    return 1
  fi

  local pacman_lock="$UPDATERBTW_STATE_DIR/updatebtw.lock"
  mkdir -p "$UPDATERBTW_STATE_DIR"
  exec 7> "$pacman_lock"
  if ! flock -n 7; then
    _notify error "Update Failed" "Another pacman process holds the database lock"
    return 1
  fi

  if [ "${ENABLE_REFLECTOR:-true}" = "true" ]; then
    _update_mirrorlist || true
  fi

  _notify info "updatebtw" "Starting system update"
  local helper="${AUR_HELPER:-yay}"
  local aur_user="${AUR_USER:-aur_builder}"
  # SECURITY (inherent — issue #3: auto-install without review):
  # The --noconfirm flag installs all available updates without user interaction.
  # If a malicious package enters the official repos or AUR (supply chain
  # compromise), it would be installed automatically. This is the fundamental
  # tradeoff of automatic updates — convenience vs. review. The software cannot
  # fulfill its purpose of unattended updates without this flag.
  #
  # Mitigations: rate limiting, update logging, desktop notifications,
  # AUR helper runs as unprivileged user.
  case "$helper" in
    yay)  _run_as_user "$aur_user" yay -Syyuu --noconfirm ;;
    paru) _run_as_user "$aur_user" paru -Syyuu --noconfirm ;;
  esac

  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    _notify error "Update Failed" "AUR helper exited with code $exit_code"
    return $exit_code
  fi

  if command -v flatpak >/dev/null 2>&1; then
    local flatpak_user="${FLATPAK_USER:-}"
    if [ -z "$flatpak_user" ]; then
      flatpak_user="${SUDO_USER:-}"
    fi
    if [ -z "$flatpak_user" ]; then
      # SECURITY (inherent — issue #13: flatpak user auto-detect):
      # When FLATPAK_USER is not configured, we attempt to detect the active
      # desktop user via loginctl. If parsing fails or returns the wrong user
      # (e.g., headless system, multiple sessions, loginctl format change),
      # flatpak updates are skipped rather than falling back to the AUR user.
      # Flatpak installs are per-user; running as the wrong user updates the
      # wrong installations. This is inherent to heuristic auto-detection
      # without explicit configuration. Mitigation: explicit FLATPAK_USER
      # config option; clear notification when skipped.
      flatpak_user="$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -1)"
      [ -n "$flatpak_user" ] && flatpak_user="$(id -un "$flatpak_user" 2>/dev/null)" || flatpak_user=""
    fi
    if [ -z "$flatpak_user" ]; then
      _notify error "Flatpak Update Skipped" "FLATPAK_USER not configured and no active session detected"
    else
      _run_flatpak "$flatpak_user" || {
        _notify error "Flatpak Update Failed" "flatpak exited with code $?"
        return 1
      }
    fi
  fi

  _notify success "updatebtw" "Update complete"
  date "+%s" > "$UPDATERBTW_STATE_DIR/last_update"
  chmod 600 "$UPDATERBTW_STATE_DIR/last_update"
}

_update_mirrorlist() {
  local mirrorlist="/etc/pacman.d/mirrorlist"
  local interval_days="${REFLECTOR_INTERVAL:-30}"
  # Clamp to sane bounds to prevent overflow or bypass
  if ! [ "$interval_days" -ge 0 ] 2>/dev/null || ! [ "$interval_days" -le 3650 ] 2>/dev/null; then
    interval_days=30
  fi
  local interval=$(( interval_days * 86400 ))

  if [ -f "$mirrorlist" ]; then
    local last_update
    last_update="$(date -r "$mirrorlist" "+%s")"
    local now
    now="$(date "+%s")"
    local delta=$(( now - last_update ))
    if [ $delta -lt $interval ]; then
      return 0
    fi
  fi

  backup_file "$mirrorlist"
  _notify info "updatebtw" "Updating mirrorlist via reflector"
  if ! timeout 120 reflector --save "$mirrorlist" \
       --country "${REFLECTOR_COUNTRY:-United States}" \
       --protocol "${REFLECTOR_PROTOCOL:-https}" \
       --latest 5 \
       --sort age \
       --age 12 \
       --connection-timeout 10; then
    _notify error "Reflector Failed" "Mirrorlist update failed"
    return 1
  fi
}

_notify() {
  local type="$1"
  local summary="$2"
  local body="$3"
  if [ "$type" = "error" ] && [ -n "$UPDATERBTW_LOG_FILE" ]; then
    body="$body — see $UPDATERBTW_LOG_FILE"
  fi
  echo "[$type] $summary: $body"
  if ! command -v notify-send >/dev/null 2>&1; then
    return 0
  fi

  local urgency="normal"
  local icon="dialog-information"
  case "$type" in
    error)    urgency="critical"; icon="dialog-error" ;;
    success)  urgency="normal";   icon="dialog-information" ;;
    info)     urgency="low";      icon="dialog-information" ;;
    critical) urgency="critical"; icon="dialog-warning" ;;
  esac

  local target_user="${SUDO_USER:-}"
  if [ -z "$target_user" ]; then
    target_user="$(loginctl list-sessions --no-legend 2>/dev/null | while read -r sid uid rest; do
      local stype
      stype="$(loginctl show-session "$sid" -p Type --value 2>/dev/null)"
      if [ "$stype" = "x11" ] || [ "$stype" = "wayland" ]; then
        id -un "$uid" 2>/dev/null && break
      fi
    done)"
    [ -z "$target_user" ] && target_user="$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -1)"
    [ -n "$target_user" ] && target_user="$(id -un "$target_user" 2>/dev/null)" || target_user=""
  fi

  if [ -n "$target_user" ]; then
    local uid
    uid="$(id -u "$target_user" 2>/dev/null)" || return 0

    case "$uid" in
      ''|*[!0-9]*) return 0 ;;
    esac
    if [ "$uid" -lt 1000 ] || [ "$uid" -gt 60000 ]; then
      return 0
    fi

    local bus_path="/run/user/$uid/bus"
    if [ -S "$bus_path" ]; then
      if [ "$(id -un)" = "$target_user" ]; then
        notify-send -i "$icon" -u "$urgency" -a "updatebtw" "$summary" "$body" 2>/dev/null || true
      elif command -v runuser >/dev/null 2>&1; then
        runuser -u "$target_user" -- env \
          XDG_RUNTIME_DIR="/run/user/$uid" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=$bus_path" \
          notify-send -i "$icon" -u "$urgency" -a "updatebtw" "$summary" "$body" 2>/dev/null || true
      fi
    fi
  else
    notify-send -i "$icon" -u "$urgency" -a "updatebtw" "$summary" "$body" 2>/dev/null || true
  fi
  return 0
}

_run_flatpak() {
  local user="$1"
  if [ "$(id -un)" = "$user" ]; then
    flatpak update --noninteractive
  elif command -v runuser >/dev/null 2>&1; then
    local uid home_dir bus_path xdg_data_dirs
    uid="$(id -u "$user" 2>/dev/null)" || return 1
    home_dir="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)" || return 1
    bus_path="/run/user/$uid/bus"
    xdg_data_dirs="$home_dir/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
    if [ -S "$bus_path" ]; then
      runuser -u "$user" -- env \
        HOME="$home_dir" \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$bus_path" \
        XDG_DATA_DIRS="$xdg_data_dirs" \
        flatpak update --noninteractive
    else
      runuser -u "$user" -- env \
        HOME="$home_dir" \
        XDG_DATA_DIRS="$xdg_data_dirs" \
        flatpak update --noninteractive
    fi
  elif command -v sudo >/dev/null 2>&1; then
    local uid home_dir bus_path xdg_data_dirs
    uid="$(id -u "$user" 2>/dev/null)" || return 1
    home_dir="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)" || return 1
    bus_path="/run/user/$uid/bus"
    xdg_data_dirs="$home_dir/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
    if [ -S "$bus_path" ]; then
      sudo -u "$user" -- env \
        HOME="$home_dir" \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$bus_path" \
        XDG_DATA_DIRS="$xdg_data_dirs" \
        flatpak update --noninteractive
    else
      sudo -u "$user" -- env \
        HOME="$home_dir" \
        XDG_DATA_DIRS="$xdg_data_dirs" \
        flatpak update --noninteractive
    fi
  else
    echo "updatebtw: cannot run flatpak as user '$user' — neither runuser nor sudo available" >&2
    return 1
  fi
}

_run_as_user() {
  # SECURITY (inherent — issue #10: AUR user delegation):
  # Commands are executed as the AUR user via runuser or sudo. If the AUR
  # user's environment is compromised (e.g., malicious config files in the
  # user's home directory that the AUR helper reads), the compromise affects
  # the update process. The AUR user is a local account that could be
  # targeted by other local attackers. This is inherent to the multi-user
  # execution model — we must delegate to an unprivileged user to limit
  # the blast radius of AUR helper vulnerabilities.
  #
  # Mitigations: strict argument allowlist (only alphanumerics, _./:@,+=-),
  # dedicated user account with no login shell, direct exec (no shell
  # interpretation) via runuser -u / sudo -u.
  local user="$1"
  shift
  for arg in "$@"; do
    if ! printf '%s' "$arg" | grep -qE '^[a-zA-Z0-9_./:@,+=-]+$'; then
      echo "updatebtw: unsafe argument detected: $arg" >&2
      return 1
    fi
  done
  if [ "$(id -un)" = "$user" ]; then
    "$@"
  elif command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u "$user" -- "$@"
  else
    echo "updatebtw: cannot run as user '$user' — neither runuser nor sudo available" >&2
    return 1
  fi
}

_cleanup_old_logs() {
  local log_dir="${UPDATERBTW_LOG_DIR:-/var/log/updatebtw}"
  [ -d "$log_dir" ] || return 0
  find "$log_dir" -type f -mtime +60 -delete 2>/dev/null || true
}
