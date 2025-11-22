#!/bin/bash
# kk-test.sh - Main testing framework orchestrator
# This is the entry point that loads all testing framework components
#
# Usage in test suites:
#   source "$(dirname "$SCRIPT_DIR")/../kktests/lib/kk-test.sh"
#
# This will automatically source all framework components in the correct order.

# Get the directory where this file is located
_KK_TEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_KK_TEST_ROOT_DIR="$(dirname "$_KK_TEST_LIB_DIR")"

# ============================================================================
# Load Framework Components
# ============================================================================

# 1. Load core framework first (provides basic functions and constants)
source "$_KK_TEST_LIB_DIR/kk-test-core.sh" || {
    echo "ERROR: Failed to load kk-test-core.sh" >&2
    exit 1
}

# 2. Load assertions (requires core.sh)
source "$_KK_TEST_LIB_DIR/kk-test-assertions.sh" || {
    echo "ERROR: Failed to load kk-test-assertions.sh" >&2
    exit 1
}

# 3. Load fixtures (requires core.sh)
source "$_KK_TEST_LIB_DIR/kk-test-fixtures.sh" || {
    echo "ERROR: Failed to load kk-test-fixtures.sh" >&2
    exit 1
}

# 4. Load test runner (requires core.sh)
source "$_KK_TEST_LIB_DIR/kk-test-runner.sh" || {
    echo "ERROR: Failed to load kk-test-runner.sh" >&2
    exit 1
}

# ============================================================================
# Framework Exports
# ============================================================================

# Export framework version
readonly KK_TEST_FRAMEWORK_VERSION="1.0.0"

# Export framework directory for templates
readonly KK_TEST_FRAMEWORK_DIR="$_KK_TEST_ROOT_DIR"

# ============================================================================
# Provide convenience functions
# ============================================================================

# Quick test setup - one-liner for common initialization
# Usage: kk_test_init "test_name" "$SCRIPT_DIR"
kk_test_init() {
    local test_name="${1:-default}"
    local script_dir="${2:-.}"
    
    # Initialize fixtures
    kk_fixture_setup "$test_name" "$script_dir"
    
    # Set up cleanup trap
    trap 'kk_fixture_teardown' EXIT
}

# Show framework information
kk_test_info() {
    echo "KK Testing Framework v$KK_TEST_FRAMEWORK_VERSION"
    echo "Framework Directory: $KK_TEST_FRAMEWORK_DIR"
    echo ""
    echo "Loaded Components:"
    echo "  - kk-test-core.sh v$KK_TEST_CORE_VERSION"
    echo "  - kk-test-assertions.sh v$KK_TEST_ASSERTIONS_VERSION"
    echo "  - kk-test-fixtures.sh v$KK_TEST_FIXTURES_VERSION"
    echo "  - kk-test-runner.sh v$KK_TEST_RUNNER_VERSION"
}

