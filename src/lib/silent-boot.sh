# updatebtw silent boot module
#
# SECURITY (inherent — issue #12: broad filesystem modifications):
# This module modifies boot loader entries, GRUB config, mkinitcpio hooks,
# sysctl settings, systemd service overrides, and kernel module blacklists.
# Any of these modifications could inadvertently break the boot process or
# reduce system security (e.g., removing fsck from mkinitcpio hooks means
# no filesystem check on boot). The changes are irreversible without restore
# from backup. This is inherent to the scope of the silent boot feature.
# Mitigations: backup before every modification, restore on mkinitcpio
# failure, bootloader detection to avoid unsupported configurations.

BLACKLIST_MODULES="${BLACKLIST_MODULES:-sp5100_tco}"

detect_bootloader() {
  [ -f /boot/loader/loader.conf ] && echo "systemd-boot" && return 0
  [ -f /etc/default/grub ] && echo "grub" && return 0
  echo "unknown"
  return 0
}

set_kernel_options() {
  local entries_dir="${1:-/boot/loader/entries}"
  local kernel_options="${2:-quiet loglevel=3 vt.global_cursor_default=0 systemd.show_status=auto rd.udev.log_level=3}"
  if [ -n "$BLACKLIST_MODULES" ]; then
    kernel_options="$kernel_options modprobe.blacklist=$BLACKLIST_MODULES"
  fi

  read -ra option_tokens <<< "$kernel_options"
  local option_keys=()
  local token
  for token in "${option_tokens[@]}"; do
    option_keys+=("${token%%=*}")
  done

  [ -d "$entries_dir" ] || return 0

  local work_dir
  work_dir="$(mktemp -d)"
  chmod 700 "$work_dir"

  local entry
  for entry in "$entries_dir"/*; do
    [ -f "$entry" ] || continue
    backup_file "$entry" 2>/dev/null || true

    local tmpfile
    tmpfile="$work_dir/entry"
    : > "$tmpfile"
    chmod 644 "$tmpfile"
    chown root:root "$tmpfile"
    local line

    while IFS= read -r line; do
      read -ra line_tokens <<< "$line"
      if [ "${line_tokens[0]}" = "options" ]; then
        local out_line=""
        local token2 key2 skip
        for token2 in "${line_tokens[@]}"; do
          key2="${token2%%=*}"
          skip=false
          local k
          for k in "${option_keys[@]}"; do
            if [ "$key2" = "$k" ]; then
              skip=true
              break
            fi
          done
          if ! $skip; then
            out_line="$out_line$token2 "
          fi
        done
        out_line="$out_line$kernel_options"
        printf '%s\n' "$out_line" >> "$tmpfile"
      else
        printf '%s\n' "$line" >> "$tmpfile"
      fi
    done < "$entry"

    local orig_perms orig_owner orig_group
    orig_perms="$(stat -c '%a' "$entry" 2>/dev/null || echo "644")"
    orig_owner="$(stat -c '%u' "$entry" 2>/dev/null || echo "0")"
    orig_group="$(stat -c '%g' "$entry" 2>/dev/null || echo "0")"
    chmod "$orig_perms" "$tmpfile"
    chown "$orig_owner:$orig_group" "$tmpfile"
    mv -f "$tmpfile" "$entry"
  done

  rm -rf "$work_dir"
}

set_grub_silent() {
  local grub_cfg="${1:-/etc/default/grub}"
  [ -f "$grub_cfg" ] || return 0

  backup_file "$grub_cfg" 2>/dev/null || true

  local work_dir
  work_dir="$(mktemp -d)"
  chmod 700 "$work_dir"

  local tmpfile
  tmpfile="$work_dir/grub"
  : > "$tmpfile"
  chmod 644 "$tmpfile"
  chown root:root "$tmpfile"

  local has_default=false has_timeout=false has_recordfail=false

  while IFS= read -r line; do
    local key="${line%%=*}"
    key="${key## }"
    case "$key" in
      GRUB_DEFAULT)
        printf 'GRUB_DEFAULT=0\n' >> "$tmpfile"
        has_default=true
        ;;
      GRUB_TIMEOUT)
        printf 'GRUB_TIMEOUT=1\n' >> "$tmpfile"
        has_timeout=true
        ;;
      GRUB_RECORDFAIL_TIMEOUT)
        printf 'GRUB_RECORDFAIL_TIMEOUT=10\n' >> "$tmpfile"
        has_recordfail=true
        ;;
      *)
        printf '%s\n' "$line" >> "$tmpfile"
        ;;
    esac
  done < "$grub_cfg"

  if ! $has_default; then
    printf 'GRUB_DEFAULT=0\n' >> "$tmpfile"
  fi
  if ! $has_timeout; then
    printf 'GRUB_TIMEOUT=1\n' >> "$tmpfile"
  fi
  if ! $has_recordfail; then
    printf 'GRUB_RECORDFAIL_TIMEOUT=10\n' >> "$tmpfile"
  fi

  # Hidden style: boots immediately but any key press reveals the menu
  printf 'GRUB_TIMEOUT_STYLE=hidden\n' >> "$tmpfile"

  local orig_perms orig_owner orig_group
  orig_perms="$(stat -c '%a' "$grub_cfg" 2>/dev/null || echo "644")"
  orig_owner="$(stat -c '%u' "$grub_cfg" 2>/dev/null || echo "0")"
  orig_group="$(stat -c '%g' "$grub_cfg" 2>/dev/null || echo "0")"
  chmod "$orig_perms" "$tmpfile"
  chown "$orig_owner:$orig_group" "$tmpfile"
  mv -f "$tmpfile" "$grub_cfg"

  if command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
  fi

  rm -rf "$work_dir"
}

set_printk() {
  local dest="${1:-/etc/sysctl.d/20-quiet-printk.conf}"
  local dest_dir
  dest_dir="$(dirname "$dest")"
  mkdir -p "$dest_dir"
  backup_file "$dest" 2>/dev/null || true
  printf 'kernel.printk = 3 3 3 3\n' > "$dest"
}

patch_mkinitcpio() {
  local src="${1:-/etc/mkinitcpio.conf}"
  [ -f "$src" ] || return 0
  backup_file "$src" 2>/dev/null || true

  local work_dir
  work_dir="$(mktemp -d)"
  chmod 700 "$work_dir"

  local tmpfile
  tmpfile="$work_dir/mkinitcpio"
  : > "$tmpfile"
  chmod 644 "$tmpfile"
  chown root:root "$tmpfile"
  local line

  while IFS= read -r line; do
    local key="${line%%=*}"
    key="${key## }"
    if [ "$key" = "HOOKS" ]; then
      local result="" trailing_paren="" token
      for token in $line; do
        local base="$token" has_paren=false
        case "$token" in
          *")")
            base="${token%)}"
            has_paren=true
            ;;
        esac
        case "$base" in
          udev)
            result="$result systemd"
            $has_paren && trailing_paren=")"
            ;;
          fsck)
            # Don't remove fsck — it's a safety-critical hook that performs
            # filesystem checks on boot. Removing it risks data loss on
            # corrupted filesystems. Silent boot is achieved via the
            # systemd-fsck service override (StandardOutput=null) below.
            result="$result fsck"
            $has_paren && trailing_paren=")"
            ;;
          *)
            result="$result $base"
            $has_paren && trailing_paren=")"
            ;;
        esac
      done
      line="${result# }${trailing_paren}"
      printf '%s\n' "$line" >> "$tmpfile"
    else
      printf '%s\n' "$line" >> "$tmpfile"
    fi
  done < "$src"

  local orig_perms orig_owner orig_group
  orig_perms="$(stat -c '%a' "$src" 2>/dev/null || echo "644")"
  orig_owner="$(stat -c '%u' "$src" 2>/dev/null || echo "0")"
  orig_group="$(stat -c '%g' "$src" 2>/dev/null || echo "0")"
  chmod "$orig_perms" "$tmpfile"
  chown "$orig_owner:$orig_group" "$tmpfile"
  mv -f "$tmpfile" "$src"

  rm -rf "$work_dir"
}

patch_fsck_services() {
  local units=("$@")
  if [ ${#units[@]} -eq 0 ]; then
    units=(systemd-fsck@.service systemd-fsck-root.service)
  fi

  local unit
  for unit in "${units[@]}"; do
    local name="${unit%.service}"
    name="${name##*/}"
    local override_dir="/etc/systemd/system/${name}.service.d"
    mkdir -p "$override_dir"
    local override_file="$override_dir/silent.conf"

    if [ -f "$override_file" ] && grep -q 'StandardOutput=null' "$override_file" 2>/dev/null; then
      continue
    fi

    cat > "$override_file" << 'EOF'
[Service]
StandardOutput=null
StandardError=journal+console
EOF
  done
}

silent_boot() {
  local bootloader
  bootloader="$(detect_bootloader)"
  case "$bootloader" in
    systemd-boot)
      if [ ! -d /boot/loader/entries ] || [ -z "$(ls /boot/loader/entries/*.conf 2>/dev/null)" ]; then
        echo "Warning: No systemd-boot entries found — skipping kernel option changes" >&2
      else
        set_kernel_options
      fi
      ;;
    grub)
      if [ ! -f /etc/default/grub ]; then
        echo "Warning: GRUB config not found — skipping GRUB changes" >&2
      else
        set_grub_silent
      fi
      ;;
    unknown)
      echo "Warning: Unknown bootloader — skipping bootloader-specific changes"
      ;;
  esac

  set_printk
  patch_mkinitcpio
  patch_fsck_services

  if [ -f /etc/mkinitcpio.conf ] && [ -f /boot/vmlinuz-linux ]; then
    mkinitcpio -P || {
      echo "ERROR: mkinitcpio failed — restoring backup of mkinitcpio.conf" >&2
      restore_file /etc/mkinitcpio.conf 2>/dev/null || true
      return 1
    }
  fi

  touch ~root/.hushlogin
  touch ~"${SUDO_USER:-$(id -un)}"/.hushlogin 2>/dev/null || true
}
