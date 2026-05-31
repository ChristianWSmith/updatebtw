# updatebtw updater module

update_packages() {
  trap '_notify critical "updatebtw" "Shutdown blocked — system update in progress, please wait"' SIGTERM
  read_config

  _cleanup_old_backups 2>/dev/null || true
  _cleanup_old_logs 2>/dev/null || true

  if [ -e /var/lib/pacman/db.lck ]; then
    _notify error "Update Failed" "/var/lib/pacman/db.lck exists"
    return 1
  fi

  if [ "${ENABLE_REFLECTOR:-true}" = "true" ]; then
    _update_mirrorlist || true
  fi

  _notify info "updatebtw" "Starting system update"
  local helper="${AUR_HELPER:-yay}"
  local aur_user="${AUR_USER:-aur_builder}"
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
    local flatpak_user="${FLATPAK_USER:-$aur_user}"
    _run_as_user "$flatpak_user" flatpak update --noninteractive || {
      _notify error "Flatpak Update Failed" "flatpak exited with code $?"
      return 1
    }
  fi

  _notify success "updatebtw" "Update complete"
}

_update_mirrorlist() {
  local mirrorlist="/etc/pacman.d/mirrorlist"
  local interval=$(( ${REFLECTOR_INTERVAL:-30} * 86400 ))

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
  if ! reflector --save "$mirrorlist" \
       --country "${REFLECTOR_COUNTRY:-United States}" \
       --protocol "${REFLECTOR_PROTOCOL:-https}" \
       --latest 5; then
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

  if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    local uid
    uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | head -1)
    if [ -n "$uid" ] && [ -S "/run/user/$uid/bus" ]; then
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
    fi
  fi

  if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
    notify-send -i "$icon" -u "$urgency" -a "updatebtw" "$summary" "$body" 2>/dev/null || true
  fi
}

_run_as_user() {
  local user="$1"
  shift
  if [ "$(id -un)" = "$user" ]; then
    "$@"
  elif command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- "$@"
  else
    su - "$user" -c "$*"
  fi
}

_cleanup_old_logs() {
  local log_dir="${UPDATERBTW_LOG_DIR:-/var/log/updatebtw}"
  [ -d "$log_dir" ] || return 0
  find "$log_dir" -type f -mtime +60 -delete 2>/dev/null || true
}
