#!/bin/bash
# ktest.sh - Main testing framework orchestrator
# This is the entry point that loads all testing framework components
#
# Usage in test suites:
#   source "$(dirname "$SCRIPT_DIR")/../ktests/lib/ktest.sh"
#
# This will automatically source all framework components in the correct order.

# Prevent multiple sourcing
if [[ -n "${_KTEST_SOURCED:-}" ]]; then
    return
fi
declare -g _KTEST_SOURCED=1

# ============================================================================
# Locale contract (kcl decision D6, review 2026-09-06)
# ============================================================================
# The whole corpus runs under UTF-8. On this machine LANG and LC_ALL are empty,
# which puts bash in the C locale: `${#s}` counts BYTES, `${s,,}` CORRUPTS
# multi-byte text on 5.2 (`ÄÖ` -> garbage) and `.` in a regex does not match a
# multi-byte character — so tests were silently pinning byte semantics while the
# unit docs promise characters (finding X-LOCALE: TSH-04, tregex T3).
#
# Pinned here rather than in each runner because every runner AND every test
# file sources this one entry point, so a test file executed directly behaves
# exactly as it does inside a sweep. A test that needs another locale sets it
# for its own subshell / child process.
export LC_ALL="C.UTF-8"
export LANG="C.UTF-8"

# Get the directory where this file is located
# Use KTESTS_LIB_DIR if already set (from test runner), otherwise compute from BASH_SOURCE
if [[ -n "${KTESTS_LIB_DIR:-}" ]]; then
    _KTEST_LIB_DIR="$KTESTS_LIB_DIR"
else
    _KTEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
_KTEST_ROOT_DIR="$(dirname "$_KTEST_LIB_DIR")"

# ============================================================================
# Load Framework Components
# ============================================================================

# 1. Load core framework first (provides basic functions and constants)
source "$_KTEST_LIB_DIR/ktest_core.sh" || {
    echo "ERROR: Failed to load ktest_core.sh" >&2
    exit 1
}

# 2. Load assertions (requires core.sh)
source "$_KTEST_LIB_DIR/ktest_assertions.sh" || {
    echo "ERROR: Failed to load ktest_assertions.sh" >&2
    exit 1
}

# 3. Load fixtures (requires core.sh)
source "$_KTEST_LIB_DIR/ktest_fixtures.sh" || {
    echo "ERROR: Failed to load ktest_fixtures.sh" >&2
    exit 1
}

# 4. Load test runner (requires core.sh)
source "$_KTEST_LIB_DIR/ktest_runner.sh" || {
    echo "ERROR: Failed to load ktest_runner.sh" >&2
    exit 1
}

# ============================================================================
# Framework Exports
# ============================================================================

# Export framework version (only if not already set)
if [[ -z "${KT__FRAMEWORK_VERSION:-}" ]]; then
    readonly KT__FRAMEWORK_VERSION="1.0.0"
fi

# Export framework directory for templates (only if not already set)
if [[ -z "${KT__FRAMEWORK_DIR:-}" ]]; then
    readonly KT__FRAMEWORK_DIR="$_KTEST_ROOT_DIR"
fi

# ============================================================================
# Provide convenience functions
# ============================================================================

# Quick test setup - one-liner for common initialization
# Usage: kt_test_init "test_name" "$SCRIPT_DIR" [... other args passed to test]
kt_test_init() {
    local test_name="${1:-default}"
    local script_dir="${2:-.}"
    shift 2
    
    # Parse command line arguments if provided
    if [[ $# -gt 0 ]]; then
        kt_runner_parse_args "$@"
    fi
    
    # Set file name for error reporting (from caller's context)
    KT__FILE="$(basename "${BASH_SOURCE[1]}")"
    
    # Initialize fixtures. The fixture directory carries the test FILE name as
    # well as the given name, so two files passing the same name (or one derived
    # from something shared) never share a directory under the parallel runner
    # (kcl review P8-F2).
    kt_fixture_setup "${test_name}.${KT__FILE%.sh}" "$script_dir"
    
    # Set up cleanup trap
    # Output __COUNTS__ only if KK_OUTPUT_COUNTS is set (used by test runner)
    if [[ -n "${KK_OUTPUT_COUNTS:-}" && "${KK_OUTPUT_COUNTS:-}" != "0" ]]; then
        trap 'kt_fixture_teardown; echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"' EXIT
    else
        trap 'kt_fixture_teardown' EXIT
    fi
}

# Show framework information
kt_test_info() {
    echo "KK Testing Framework v$KT__FRAMEWORK_VERSION"
    echo "Framework Directory: $KT__FRAMEWORK_DIR"
    echo ""
    echo "Loaded Components:"
    echo "  - ktest_core.sh v$KT__CORE_VERSION"
    echo "  - ktest_assertions.sh v$KT__ASSERTIONS_VERSION"
    echo "  - ktest_fixtures.sh v$KT__FIXTURES_VERSION"
    echo "  - ktest_runner.sh v$KT__RUNNER_VERSION"
}

