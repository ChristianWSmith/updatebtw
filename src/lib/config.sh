# updatebtw config module

UPDATERBTW_CONFIG="${UPDATERBTW_CONFIG:-/etc/updatebtw/updatebtw.conf}"
AUR_USER="${AUR_USER:-aur_builder}"
FLATPAK_USER="${FLATPAK_USER:-${AUR_USER:-aur_builder}}"

_allowed_config_keys="AUR_HELPER UPDATE_FREQUENCY UPDATE_TIME RUN_AT_BOOT ENABLE_REFLECTOR REFLECTOR_COUNTRY REFLECTOR_PROTOCOL REFLECTOR_INTERVAL SILENT_BOOT AUR_USER FLATPAK_USER BLACKLIST_MODULES"

# Strict allowlist of characters permitted in config values.
# Covers: alphanumerics, _, ., /, space, :, @, comma, +, -
# Excludes: $ ` ; & | ( ) { } ! < > ' " [ ] \ ~ # % ^ * ?
_safe_value_pattern='^[a-zA-Z0-9_./ :@,+.-]*$'

_safe_read_config() {
  # SECURITY (inherent — issue #9: config file trusted as root):
  # This function reads /etc/updatebtw/updatebtw.conf as root and sets shell
  # variables from its contents. Any attacker with root can modify the config
  # file, and validation only protects against malformed content — not against
  # an attacker who controls the file. This is inherent to any config-driven
  # system that runs as root.
  #
  # Mitigations: fd-based TOCTOU mitigation (open fd before checking perms),
  # permission enforcement (600/400 only), root ownership check, symlink
  # rejection, strict character allowlist (excludes $ ` ; & | ( ) { } etc.),
  # per-key format validation, values assigned directly (never sourced).
  local cfg="$1"

  # Open fd FIRST — no prior existence or symlink check eliminates TOCTOU window.
  # If the file doesn't exist, exec fails and we return 0 (nothing to read).
  exec 8< "$cfg" 2>/dev/null || return 0

  # Reject if the original path was a symlink. /proc/self/fd/8 is always a
  # symlink to the open file description, but readlink (without -f) returns
  # the path that was used to open it. If that differs from the canonical
  # resolved path, the original was a symlink.
  local fd_target real_path perms owner
  fd_target="$(readlink /proc/self/fd/8 2>/dev/null)" || { exec 8<&-; return 1; }
  real_path="$(readlink -f /proc/self/fd/8 2>/dev/null)" || { exec 8<&-; return 1; }
  if [ "$fd_target" != "$real_path" ]; then
    echo "updatebtw: config $cfg is a symlink, refusing" >&2
    exec 8<&-
    return 1
  fi

  # Validate permissions via the opened fd (not the original path).
  perms="$(stat -L -c '%a' /proc/self/fd/8 2>/dev/null)" || { exec 8<&-; return 1; }
  if [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
    echo "updatebtw: config has unsafe permissions ($perms), expected 600 or 400" >&2
    exec 8<&-
    return 1
  fi

  owner="$(stat -L -c '%U' /proc/self/fd/8 2>/dev/null)" || { exec 8<&-; return 1; }
  if [ "$owner" != "root" ]; then
    echo "updatebtw: config is not owned by root (owned by $owner)" >&2
    exec 8<&-
    return 1
  fi

  local line key value
  while IFS= read -r line <&8; do
    case "$line" in
      ""|\#*) continue ;;
    esac
    key="${line%%=*}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    local allowed=false k
    for k in $_allowed_config_keys; do
      if [ "$key" = "$k" ]; then
        allowed=true
        break
      fi
    done
    if ! $allowed; then
      echo "updatebtw: config $cfg contains unknown key: $key" >&2
      exec 8<&-
      return 1
    fi

    # Extract value: strip key= and surrounding quotes
    value="${line#*=}"
    # Remove leading/trailing double quotes if present
    case "$value" in
      '"'*'"') value="$(printf '%s' "$value" | sed 's/^"//;s/"$//')" ;;
    esac

    # Strict character allowlist — no dangerous syntax can pass
    if ! printf '%s' "$value" | grep -qE "$_safe_value_pattern"; then
      echo "updatebtw: config $cfg contains invalid characters in: $line" >&2
      exec 8<&-
      return 1
    fi

    # Per-key validation — enforce expected format for each known key
    case "$key" in
      AUR_HELPER)
        case "$value" in yay|paru) ;; *) echo "updatebtw: config $cfg: AUR_HELPER must be 'yay' or 'paru'" >&2; exec 8<&-; return 1 ;; esac ;;
      UPDATE_FREQUENCY)
        case "$value" in daily|weekly|monthly) ;; *) echo "updatebtw: config $cfg: UPDATE_FREQUENCY must be 'daily', 'weekly', or 'monthly'" >&2; exec 8<&-; return 1 ;; esac ;;
      RUN_AT_BOOT|ENABLE_REFLECTOR|SILENT_BOOT)
        case "$value" in true|false) ;; *) echo "updatebtw: config $cfg: $key must be 'true' or 'false'" >&2; exec 8<&-; return 1 ;; esac ;;
      UPDATE_TIME)
        if ! printf '%s' "$value" | grep -qE '^[0-2][0-9]:[0-5][0-9]$'; then
          echo "updatebtw: config $cfg: UPDATE_TIME must be HH:MM format" >&2; exec 8<&-; return 1
        fi ;;
      REFLECTOR_INTERVAL)
        if ! printf '%s' "$value" | grep -qE '^[0-9]+$'; then
          echo "updatebtw: config $cfg: REFLECTOR_INTERVAL must be a number" >&2; exec 8<&-; return 1
        fi ;;
      REFLECTOR_COUNTRY)
        if ! printf '%s' "$value" | grep -qE '^[a-zA-Z0-9 .,-]+$'; then
          echo "updatebtw: config $cfg: REFLECTOR_COUNTRY contains invalid characters" >&2; exec 8<&-; return 1
        fi ;;
      REFLECTOR_PROTOCOL)
        case "$value" in https|http|rsync) ;; *) echo "updatebtw: config $cfg: REFLECTOR_PROTOCOL must be 'https', 'http', or 'rsync'" >&2; exec 8<&-; return 1 ;; esac ;;
      BLACKLIST_MODULES)
        if ! printf '%s' "$value" | grep -qE '^[a-zA-Z0-9_,]+$'; then
          echo "updatebtw: config $cfg: BLACKLIST_MODULES contains invalid characters" >&2; exec 8<&-; return 1
        fi ;;
      AUR_USER|FLATPAK_USER)
        if ! printf '%s' "$value" | grep -qE '^[a-z_][a-z0-9_-]*$'; then
          echo "updatebtw: config $cfg: $key contains invalid characters" >&2; exec 8<&-; return 1
        fi ;;
    esac

    # Set variable directly — never source the file
    case "$key" in
      AUR_HELPER)        AUR_HELPER="$value" ;;
      UPDATE_FREQUENCY)  UPDATE_FREQUENCY="$value" ;;
      UPDATE_TIME)       UPDATE_TIME="$value" ;;
      RUN_AT_BOOT)       RUN_AT_BOOT="$value" ;;
      ENABLE_REFLECTOR)  ENABLE_REFLECTOR="$value" ;;
      REFLECTOR_COUNTRY) REFLECTOR_COUNTRY="$value" ;;
      REFLECTOR_PROTOCOL) REFLECTOR_PROTOCOL="$value" ;;
      REFLECTOR_INTERVAL) REFLECTOR_INTERVAL="$value" ;;
      SILENT_BOOT)       SILENT_BOOT="$value" ;;
      BLACKLIST_MODULES) BLACKLIST_MODULES="$value" ;;
      AUR_USER)          AUR_USER="$value" ;;
      FLATPAK_USER)      FLATPAK_USER="$value" ;;
    esac
  done

  exec 8<&-
}

read_config() {
  _safe_read_config "$UPDATERBTW_CONFIG"
}

write_config() {
  local config_dir
  config_dir="$(dirname "$UPDATERBTW_CONFIG")"
  mkdir -p "$config_dir"
  local default_flatpak_user="${SUDO_USER:-}"
  [ -z "$default_flatpak_user" ] && default_flatpak_user="$(id -un)"

  # Sanitize values: strip double quotes and newlines to prevent heredoc injection
  local s_aur_helper s_freq s_time s_boot s_reflector s_country s_protocol s_interval s_silent s_modules s_aur_user s_flatpak_user
  s_aur_helper="${AUR_HELPER:-yay}"
  s_aur_helper="${s_aur_helper//\"/}"
  s_aur_helper="${s_aur_helper//$'\n'/}"
  s_freq="${UPDATE_FREQUENCY:-weekly}"
  s_freq="${s_freq//\"/}"
  s_freq="${s_freq//$'\n'/}"
  s_time="${UPDATE_TIME:-06:00}"
  s_time="${s_time//\"/}"
  s_time="${s_time//$'\n'/}"
  s_boot="${RUN_AT_BOOT:-false}"
  s_boot="${s_boot//\"/}"
  s_boot="${s_boot//$'\n'/}"
  s_reflector="${ENABLE_REFLECTOR:-true}"
  s_reflector="${s_reflector//\"/}"
  s_reflector="${s_reflector//$'\n'/}"
  s_country="${REFLECTOR_COUNTRY:-United States}"
  s_country="${s_country//\"/}"
  s_country="${s_country//$'\n'/}"
  s_protocol="${REFLECTOR_PROTOCOL:-https}"
  s_protocol="${s_protocol//\"/}"
  s_protocol="${s_protocol//$'\n'/}"
  s_interval="${REFLECTOR_INTERVAL:-30}"
  s_interval="${s_interval//\"/}"
  s_interval="${s_interval//$'\n'/}"
  s_silent="${SILENT_BOOT:-false}"
  s_silent="${s_silent//\"/}"
  s_silent="${s_silent//$'\n'/}"
  s_modules="${BLACKLIST_MODULES:-sp5100_tco}"
  s_modules="${s_modules//\"/}"
  s_modules="${s_modules//$'\n'/}"
  s_aur_user="${AUR_USER:-aur_builder}"
  s_aur_user="${s_aur_user//\"/}"
  s_aur_user="${s_aur_user//$'\n'/}"
  s_flatpak_user="${FLATPAK_USER:-$default_flatpak_user}"
  s_flatpak_user="${s_flatpak_user//\"/}"
  s_flatpak_user="${s_flatpak_user//$'\n'/}"

  # Write to temp file, set permissions, then mv atomically into place.
  # This eliminates the TOCTOU window where the file exists with default
  # umask before chmod/chown are applied.
  local tmp_cfg
  tmp_cfg="$(mktemp "${UPDATERBTW_CONFIG}.XXXXXX")"
  {
    printf '# updatebtw configuration\n'
    printf '# Generated by updatebtw installer\n'
    printf '\n'
    printf 'AUR_HELPER="%s"\n' "$s_aur_helper"
    printf 'UPDATE_FREQUENCY="%s"\n' "$s_freq"
    printf 'UPDATE_TIME="%s"\n' "$s_time"
    printf 'RUN_AT_BOOT="%s"\n' "$s_boot"
    printf 'ENABLE_REFLECTOR="%s"\n' "$s_reflector"
    printf 'REFLECTOR_COUNTRY="%s"\n' "$s_country"
    printf 'REFLECTOR_PROTOCOL="%s"\n' "$s_protocol"
    printf 'REFLECTOR_INTERVAL="%s"\n' "$s_interval"
    printf 'SILENT_BOOT="%s"\n' "$s_silent"
    printf 'BLACKLIST_MODULES="%s"\n' "$s_modules"
    printf 'AUR_USER="%s"\n' "$s_aur_user"
    printf 'FLATPAK_USER="%s"\n' "$s_flatpak_user"
  } > "$tmp_cfg"
  chmod 600 "$tmp_cfg"
  chown root:root "$tmp_cfg" 2>/dev/null || true
  mv -f "$tmp_cfg" "$UPDATERBTW_CONFIG"
}

validate_config() {
  local errors=""
  case "${AUR_HELPER:-yay}" in
    yay|paru) ;;
    *) errors="${errors}error: AUR_HELPER must be 'yay' or 'paru' (got: ${AUR_HELPER})\n" ;;
  esac
  case "${UPDATE_FREQUENCY:-weekly}" in
    daily|weekly|monthly) ;;
    *) errors="${errors}error: UPDATE_FREQUENCY must be 'daily', 'weekly', or 'monthly' (got: ${UPDATE_FREQUENCY})\n" ;;
  esac
  if [ -n "${UPDATE_TIME:-}" ] && ! printf '%s' "${UPDATE_TIME}" | grep -qE '^[0-2][0-9]:[0-5][0-9]$'; then
    errors="${errors}error: UPDATE_TIME must be HH:MM format (got: ${UPDATE_TIME})\n"
  fi
  case "${RUN_AT_BOOT:-false}" in
    true|false) ;;
    *) errors="${errors}error: RUN_AT_BOOT must be 'true' or 'false' (got: ${RUN_AT_BOOT})\n" ;;
  esac
  case "${ENABLE_REFLECTOR:-true}" in
    true|false) ;;
    *) errors="${errors}error: ENABLE_REFLECTOR must be 'true' or 'false' (got: ${ENABLE_REFLECTOR})\n" ;;
  esac
  case "${REFLECTOR_PROTOCOL:-https}" in
    https|http|rsync) ;;
    *) errors="${errors}error: REFLECTOR_PROTOCOL must be 'https', 'http', or 'rsync' (got: ${REFLECTOR_PROTOCOL})\n" ;;
  esac
  if [ -n "${REFLECTOR_INTERVAL:-}" ] && ! printf '%s' "${REFLECTOR_INTERVAL}" | grep -qE '^[0-9]+$'; then
    errors="${errors}error: REFLECTOR_INTERVAL must be a number (got: ${REFLECTOR_INTERVAL})\n"
  fi
  case "${SILENT_BOOT:-false}" in
    true|false) ;;
    *) errors="${errors}error: SILENT_BOOT must be 'true' or 'false' (got: ${SILENT_BOOT})\n" ;;
  esac
  if [ -n "${BLACKLIST_MODULES:-}" ] && ! printf '%s' "${BLACKLIST_MODULES}" | grep -qE '^[a-zA-Z0-9_,]+$'; then
    errors="${errors}error: BLACKLIST_MODULES contains invalid characters (got: ${BLACKLIST_MODULES})\n"
  fi
  if [ -n "${AUR_USER:-}" ]; then
    if ! printf '%s' "${AUR_USER}" | grep -qE '^[a-z_][a-z0-9_-]*$'; then
      errors="${errors}error: AUR_USER contains invalid characters (got: ${AUR_USER})\n"
    fi
    local aur_uid
    aur_uid="$(id -u "$AUR_USER" 2>/dev/null)" || true
    if [ -n "$aur_uid" ] && [ "$aur_uid" -ge 1000 ] 2>/dev/null; then
      local aur_shell
      aur_shell="$(getent passwd "$AUR_USER" 2>/dev/null | cut -d: -f7)"
      case "$aur_shell" in
        */nologin|*/false) ;;
        *)
          errors="${errors}error: AUR_USER '$AUR_USER' appears to be a login user (UID $aur_uid). Use a dedicated system account.\n"
          ;;
      esac
    fi
  fi
  if [ -n "${FLATPAK_USER:-}" ] && ! printf '%s' "${FLATPAK_USER}" | grep -qE '^[a-z_][a-z0-9_-]*$'; then
    errors="${errors}error: FLATPAK_USER contains invalid characters (got: ${FLATPAK_USER})\n"
  fi
  if [ -n "$errors" ]; then
    printf '%b' "$errors" >&2
    return 1
  fi
  return 0
}

calendar_from_config() {
  local time="${UPDATE_TIME:-06:00}"
  case "${UPDATE_FREQUENCY:-weekly}" in
    daily)   echo "*-*-* ${time}:00" ;;
    weekly)  echo "Mon *-*-* ${time}:00" ;;
    monthly) echo "*-*-01 ${time}:00" ;;
  esac
}
