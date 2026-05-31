#!/bin/sh
# run-integration-tests.sh — Run updatebtw integration test suite in Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Building Docker integration test image ==="
docker build -t updatebtw-integration -f "$SCRIPT_DIR/Dockerfile" "$PROJECT_DIR"

echo ""
echo "=== Running integration tests ==="
docker run --rm updatebtw-integration bats "${@:-tests/integration/bats/}"
