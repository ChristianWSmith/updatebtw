#!/bin/sh
# run-tests.sh — Run updatebtw test suite in Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Building Docker test image ==="
docker build -t updatebtw-test -f "$SCRIPT_DIR/Dockerfile" "$PROJECT_DIR"

echo ""
echo "=== Running Bats tests ==="
docker run --rm updatebtw-test bats "${@:-tests/bats/}"
