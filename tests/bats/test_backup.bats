load ../helpers/mocks.sh

setup() {
  . "$UPDATERBTW_ROOT/backup.sh"
}

@test "backup_file creates backup with timestamp" {
  local testfile="$(mktemp /tmp/updatebtw-testfile.XXXXXX)"
  echo "test content" > "$testfile"

  backup_file "$testfile"

  local name="$(basename "$testfile")"
  ls "$BACKUP_DIR/${name}."* >/dev/null 2>&1
  [ "$?" -eq 0 ]

  rm -f "$testfile"
}

@test "backup_file returns 1 for nonexistent file" {
  run backup_file "/nonexistent/path"
  [ "$status" -eq 1 ]
}

@test "restore_file restores most recent backup" {
  local testfile="$(mktemp /tmp/updatebtw-restore.XXXXXX)"
  echo "original" > "$testfile"

  backup_file "$testfile"
  echo "modified" > "$testfile"
  restore_file "$testfile"

  [ "$(cat "$testfile")" = "original" ]
  rm -f "$testfile"
}

@test "restore_file returns 1 when no backup exists" {
  run restore_file "/nonexistent/path"
  [ "$status" -eq 1 ]
}

@test "list_backups lists files" {
  local testfile="$(mktemp /tmp/updatebtw-list.XXXXXX)"
  echo "content" > "$testfile"

  backup_file "$testfile"

  run list_backups "$(basename "$testfile")"
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  rm -f "$testfile"
}

@test "backup rotation keeps only N backups" {
  local testfile="$(mktemp /tmp/updatebtw-rotate.XXXXXX)"
  local name="$(basename "$testfile")"

  for i in $(seq 1 10); do
    echo "content $i" > "$testfile"
    backup_file "$testfile"
  done

  local count
  count="$(ls "$BACKUP_DIR/${name}."* 2>/dev/null | wc -l)"
  [ "$count" -le 5 ]

  rm -f "$testfile"
}
