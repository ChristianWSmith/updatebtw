#!/bin/sh
# manual-test.sh — Build and run the updatebtw Docker container for manual TUI testing
set -e

cd "$(dirname "$0")/.."

echo "=== Building Docker image ==="
docker build -q -t updatebtw-test -f tests/Dockerfile .

echo "=== Starting container (with TUI) ==="
echo "  Project mounted at /opt/updatebtw (live edits reflected)"
echo "  Launching installer.sh..."
echo ""

docker run -it --rm \
  --name "updatebtw-manual" \
  -v "$(pwd):/opt/updatebtw" \
  updatebtw-test \
  sh -c '/opt/updatebtw/installer.sh; echo "=== Installer finished, dropping to shell ==="; exec /bin/bash'
