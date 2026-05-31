# updatebtw backup module

UPDATERBTW_BACKUP_DIR="${UPDATERBTW_BACKUP_DIR:-/var/lib/updatebtw/backups}"
UPDATERBTW_BACKUP_KEEP="${UPDATERBTW_BACKUP_KEEP:-10}"

backup_file() {
  local src="$1"
  [ -f "$src" ] || return 1
  mkdir -p "$UPDATERBTW_BACKUP_DIR"
  chmod 700 "$UPDATERBTW_BACKUP_DIR"
  local name
  name="$(basename "$src")"
  local ts rand
  ts="$(date "+%Y%m%d_%H%M%S")"
  rand="$(head -c 4 /dev/urandom | od -An -tx4 | tr -d ' ')"
  cp -a "$src" "$UPDATERBTW_BACKUP_DIR/${name}.${ts}.${rand}"
  chmod 600 "$UPDATERBTW_BACKUP_DIR/${name}.${ts}.${rand}"
  chown root:root "$UPDATERBTW_BACKUP_DIR/${name}.${ts}.${rand}" 2>/dev/null || true
  _rotate_backups "$name"
}

restore_file() {
  local src="$1"
  local name
  name="$(basename "$src")"
  local latest
  latest="$(ls -t "$UPDATERBTW_BACKUP_DIR/${name}."* 2>/dev/null | head -1)"
  [ -n "$latest" ] || return 1
  cp -a "$latest" "$src"
}

list_backups() {
  local name="${1:-}"
  if [ -n "$name" ]; then
    ls -1t "$UPDATERBTW_BACKUP_DIR/${name}."* 2>/dev/null || true
  else
    ls -1t "$UPDATERBTW_BACKUP_DIR"/* 2>/dev/null || true
  fi
}

_rotate_backups() {
  local name="$1"
  local keep="${UPDATERBTW_BACKUP_KEEP:-10}"
  ls -t "$UPDATERBTW_BACKUP_DIR/${name}."* 2>/dev/null \
    | tail -n +$((keep + 1)) \
    | xargs rm -f 2>/dev/null || true
}

_cleanup_old_backups() {
  [ -d "$UPDATERBTW_BACKUP_DIR" ] || return 0
  find "$UPDATERBTW_BACKUP_DIR" -type f -mtime +60 -delete 2>/dev/null || true
}
