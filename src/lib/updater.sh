# updatebtw updater module

update_packages() {
  read_config

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
    _run_as_user "$aur_user" flatpak update --noninteractive || {
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
  echo "[$type] $summary: $body"
  if command -v notify-send >/dev/null 2>&1; then
    local urgency="normal"
    local icon="update-none"
    case "$type" in
      error)   urgency="critical"; icon="error" ;;
      success) urgency="normal";   icon="update-none" ;;
      info)    urgency="low";      icon="update-none" ;;
    esac
    notify-send -i "$icon" -u "$urgency" -a "updatebtw" "$summary" "$body"
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
