#!/bin/bash
# Test suite runner for comprehensive testing framework validation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../ktests.sh" "$SCRIPT_DIR" "Comprehensive Test Suite" '.*' "$@"
