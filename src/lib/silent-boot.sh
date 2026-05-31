# updatebtw silent boot module

detect_bootloader() {
  [ -f /boot/loader/loader.conf ] && echo "systemd-boot" && return 0
  [ -f /etc/default/grub ] && echo "grub" && return 0
  echo "unknown"
  return 0
}

set_kernel_options() {
  local entries_dir="${1:-/boot/loader/entries}"
  local kernel_options="${2:-quiet loglevel=3 vt.global_cursor_default=0 systemd.show_status=auto rd.udev.log_level=3 nowatchdog modprobe.blacklist=sp5100_tco audit=0}"

  read -ra option_tokens <<< "$kernel_options"
  local option_keys=()
  local token
  for token in "${option_tokens[@]}"; do
    option_keys+=("${token%%=*}")
  done

  [ -d "$entries_dir" ] || return 0
  local entry
  for entry in "$entries_dir"/*; do
    [ -f "$entry" ] || continue
    backup_file "$entry" 2>/dev/null || true

    local tmpfile
    tmpfile="$(mktemp)"
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

    chmod 755 "$tmpfile"
    chown root:root "$tmpfile"
    mv "$tmpfile" "$entry"
  done
}

set_grub_silent() {
  local grub_cfg="${1:-/etc/default/grub}"
  [ -f "$grub_cfg" ] || return 0

  backup_file "$grub_cfg" 2>/dev/null || true

  local tmpfile
  tmpfile="$(mktemp)"

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
        printf 'GRUB_TIMEOUT=0\n' >> "$tmpfile"
        has_timeout=true
        ;;
      GRUB_RECORDFAIL_TIMEOUT)
        printf 'GRUB_RECORDFAIL_TIMEOUT=$GRUB_TIMEOUT\n' >> "$tmpfile"
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
    printf 'GRUB_TIMEOUT=0\n' >> "$tmpfile"
  fi
  if ! $has_recordfail; then
    printf 'GRUB_RECORDFAIL_TIMEOUT=$GRUB_TIMEOUT\n' >> "$tmpfile"
  fi

  chmod 644 "$tmpfile"
  chown root:root "$tmpfile"
  mv "$tmpfile" "$grub_cfg"

  if command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
  fi
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

  local tmpfile
  tmpfile="$(mktemp)"
  local line

  while IFS= read -r line; do
    local key="${line%%=*}"
    key="${key## }"
    if [ "$key" = "HOOKS" ]; then
      local new_line
      new_line="$(printf '%s\n' "$line" | sed 's/udev/systemd fsck/g')"
      new_line="$(printf '%s\n' "$new_line" | sed 's/\(.*\)fsck\(.*\)fsck\(.*\)/\1fsck\2\3/g')"
      new_line="$(printf '%s\n' "$new_line" | sed 's/  / /g')"
      printf '%s\n' "$new_line" >> "$tmpfile"
    else
      printf '%s\n' "$line" >> "$tmpfile"
    fi
  done < "$src"

  chmod 644 "$tmpfile"
  chown root:root "$tmpfile"
  mv "$tmpfile" "$src"
}

patch_fsck_services() {
  local files=("$@")
  if [ ${#files[@]} -eq 0 ]; then
    files=(/usr/lib/systemd/system/systemd-fsck@.service /usr/lib/systemd/system/systemd-fsck-root.service)
  fi

  local file
  for file in "${files[@]}"; do
    [ -f "$file" ] || continue
    backup_file "$file" 2>/dev/null || true

    local tmpfile
    tmpfile="$(mktemp)"
    local in_service=false
    local line key

    while IFS= read -r line; do
      key="${line%%=*}"
      if [ "$line" = "[Service]" ]; then
        in_service=true
        printf '%s\n' "$line" >> "$tmpfile"
        printf 'StandardOutput=null\n' >> "$tmpfile"
        printf 'StandardError=journal+console\n' >> "$tmpfile"
      elif $in_service && { [ "$key" = "StandardOutput" ] || [ "$key" = "StandardError" ]; }; then
        :
      else
        printf '%s\n' "$line" >> "$tmpfile"
      fi
    done < "$file"

    chmod 644 "$tmpfile"
    chown root:root "$tmpfile"
    mv "$tmpfile" "$file"
  done
}

silent_boot() {
  local bootloader
  bootloader="$(detect_bootloader)"
  case "$bootloader" in
    systemd-boot)
      set_kernel_options
      ;;
    grub)
      set_grub_silent
      ;;
    unknown)
      echo "Warning: Unknown bootloader — skipping bootloader-specific changes"
      ;;
  esac

  set_printk
  patch_mkinitcpio
  patch_fsck_services

  if [ -f /etc/mkinitcpio.conf ] && [ -f /boot/vmlinuz-linux ]; then
    mkinitcpio -P
  fi

  touch ~root/.hushlogin
  touch ~"${SUDO_USER:-$(id -un)}"/.hushlogin 2>/dev/null || true

  systemctl unmask systemd-journald-audit.socket 2>/dev/null || true
  systemctl stop systemd-journald-audit.socket 2>/dev/null || true
  systemctl disable systemd-journald-audit.socket 2>/dev/null || true
  systemctl mask systemd-journald-audit.socket 2>/dev/null || true
}
