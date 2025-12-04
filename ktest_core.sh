#!/bin/bash
# ktest_core.sh - Core testing framework
# Provides fundamental logging, counters, and test result tracking
# 
# This is the foundation for all KK testing utilities. It should be sourced
# first by test suites before other framework components.

# Prevent multiple sourcing
if [[ -n "$_KTEST_CORE_SOURCED" ]]; then
    return
fi
declare -g _KTEST_CORE_SOURCED=1

# ============================================================================
# Color Definitions
# ============================================================================

# ANSI color codes
readonly KT_RED='\033[0;31m'
readonly KT_GREEN='\033[0;32m'
readonly KT_YELLOW='\033[1;33m'
readonly KT_BLUE='\033[0;34m'
readonly KT_CYAN='\033[0;36m'
readonly KT_NC='\033[0m'  # No Color

# ============================================================================
# Test Counter Management
# ============================================================================

# Global test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Verbosity levels: "error" (minimal) or "info" (verbose)
VERBOSITY="${VERBOSITY:-error}"

# Control whether test result output is printed
# Set to "quiet" to suppress [PASS] and [FAIL] messages for intentional test results
declare -g _KTEST_QUIET_MODE="${_KTEST_QUIET_MODE:-normal}"

# ============================================================================
# Configuration Management
# ============================================================================

declare -gA _KT_CONFIG=(
    [verbosity]="error"
    [debug]="false"
    [color]="true"
)

# Get a configuration value
kt_config_get() {
    local key="$1"
    echo "${_KT_CONFIG[$key]:-}"
}

# Set a configuration value
kt_config_set() {
    local key="$1"
    local value="$2"
    _KT_CONFIG[$key]="$value"
    # Sync with VERBOSITY global
    if [[ "$key" == "verbosity" ]]; then
        VERBOSITY="$value"
    fi
}

# ============================================================================
# Logging Functions
# ============================================================================

# Log an informational message (shown only if VERBOSITY is "info")
kt_test_log() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo -e "${KT_BLUE}[INFO]${KT_NC} $*"
    fi
}

# Log debug information (only if debug mode is enabled)
kt_test_debug() {
    if [[ "${_KT_CONFIG[debug]}" == "true" ]]; then
        echo -e "${KT_YELLOW}[DEBUG]${KT_NC} $*" >&2
    fi
}

# Log an error message (always shown)
kt_test_error() {
    echo -e "${KT_RED}[ERROR]${KT_NC} $*" >&2
}

# Log a warning message (always shown)
kt_test_warning() {
    # Only show warnings in info mode
    if [[ "$VERBOSITY" == "info" ]]; then
        echo -e "${KT_YELLOW}[WARN]${KT_NC} $*" >&2
    fi
}

# Print a section header (shown only if VERBOSITY is "info")
kt_test_section() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo ""
        echo -e "${KT_CYAN}========================================${KT_NC}"
        echo -e "${KT_CYAN}$*${KT_NC}"
        echo -e "${KT_CYAN}========================================${KT_NC}"
        echo ""
    fi
}

# ============================================================================
# Test Tracking Functions
# ============================================================================

# Mark the start of a test
# Usage: kt_test_start "Test description"
kt_test_start() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo -e "${KT_BLUE}[TEST]${KT_NC} $*"
    fi
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

# Mark a test as passed
# Usage: kt_test_pass "Test description"
kt_test_pass() {
    if [[ "$VERBOSITY" == "info" && "$_KTEST_QUIET_MODE" != "quiet" ]]; then
        echo -e "${KT_GREEN}[PASS]${KT_NC} $*"
    fi
    # Only increment counter if not in quiet mode (intentional results don't affect stats)
    if [[ "$_KTEST_QUIET_MODE" != "quiet" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
}

# Mark a test as failed
# Usage: kt_test_fail "Test description"
kt_test_fail() {
    local message="$*"
    if [[ "$_KTEST_QUIET_MODE" != "quiet" ]]; then
        if [[ -n "${KT__FILE:-}" ]]; then
            echo -e "${KT_RED}[FAIL]${KT_NC} $message (${KT__FILE})"
        else
            echo -e "${KT_RED}[FAIL]${KT_NC} $message"
        fi
    fi
    # Only increment counter if not in quiet mode (intentional results don't affect stats)
    if [[ "$_KTEST_QUIET_MODE" != "quiet" ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Backward compatibility aliases (existing test code uses these)
test_start() { kt_test_start "$@"; }
test_pass() { kt_test_pass "$@"; }
test_fail() { kt_test_fail "$@"; }
test_info() { kt_test_log "$@"; }
test_section() { kt_test_section "$@"; }

# ============================================================================
# Counter Management
# ============================================================================

# Reset all test counters
kt_test_reset_counts() {
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
}

# Get current test counts as string
# Usage: counts=$(kt_test_get_counts)
# Output format: "total:passed:failed"
kt_test_get_counts() {
    echo "$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
}

# Parse test counts from string
# Usage: kt_test_parse_counts "10:8:2" TOTAL PASSED FAILED
kt_test_parse_counts() {
    local counts_str="$1"
    local -n total_var="$2"
    local -n passed_var="$3"
    local -n failed_var="$4"
    
    IFS=':' read -r total_var passed_var failed_var <<<"$counts_str"
    total_var=${total_var:-0}
    passed_var=${passed_var:-0}
    failed_var=${failed_var:-0}
}

# Accumulate test counts from another test run
# Usage: kt_test_accumulate_counts "5:4:1"
kt_test_accumulate_counts() {
    local counts_str="$1"
    local t p f
    kt_test_parse_counts "$counts_str" t p f
    ((TESTS_TOTAL += t))
    ((TESTS_PASSED += p))
    ((TESTS_FAILED += f))
}

# ============================================================================
# Results Display
# ============================================================================

# Show test results summary
# Usage: kt_test_show_results [failed_file1 failed_file2 ...]
kt_test_show_results() {
    local total="${TESTS_TOTAL:-0}"
    local passed="${TESTS_PASSED:-0}"
    local failed="${TESTS_FAILED:-0}"
    local -a failed_files=("$@")
    
    # Normalize: if TESTS_PASSED > TESTS_TOTAL, cap it to TESTS_TOTAL
    # (this handles cases where test_pass is called multiple times per test_start)
    if (( passed > total )); then
        passed=$total
    fi
    
    if [[ "$VERBOSITY" == "info" ]]; then
        echo ""
        echo -e "${KT_CYAN}========================================${KT_NC}"
        echo -e "${KT_CYAN}Test Results Summary${KT_NC}"
        echo -e "${KT_CYAN}========================================${KT_NC}"
        echo "Total tests: $total"
        echo -e "Passed: ${KT_GREEN}$passed${KT_NC}"
        echo -e "Failed: ${KT_RED}$failed${KT_NC}"
        
        if [[ $failed -eq 0 ]]; then
            echo -e "${KT_GREEN}✓ All tests passed!${KT_NC}"
        else
            echo -e "${KT_RED}✗ $failed test(s) failed.${KT_NC}"
            if [[ ${#failed_files[@]} -gt 0 ]]; then
                echo -e "${KT_RED}Failed test files:${KT_NC}"
                for f in "${failed_files[@]}"; do
                    echo -e "  ${KT_RED}[FAIL]${KT_NC} $f"
                done
            fi
        fi
    else
        echo "Total tests: $total"
        echo "Passed: $passed"
        echo "Failed: $failed"
        
        # Always show failed test files, even in error mode
        if [[ $failed -gt 0 ]] && [[ ${#failed_files[@]} -gt 0 ]]; then
            echo "Failed test files:"
            for f in "${failed_files[@]}"; do
                echo "  [FAIL] $f"
            done
        fi
    fi
    
    return "$((failed > 0 ? 1 : 0))"
}

# Format test results for output with counter marker
# Usage: echo "$(kt_test_format_counts)"
# Output: __COUNTS__:total:passed:failed
kt_test_format_counts() {
    echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
}

# ============================================================================
# Validation Helpers
# ============================================================================

# Validate verbosity setting
# Usage: kt_test_validate_verbosity "$VERBOSITY"
kt_test_validate_verbosity() {
    local verb="$1"
    if [[ "$verb" != "info" && "$verb" != "error" ]]; then
        kt_test_error "Invalid verbosity '$verb'. Must be 'info' or 'error'."
        return 1
    fi
    return 0
}

# Validate execution mode
# Usage: kt_test_validate_mode "$MODE"
kt_test_validate_mode() {
    local mode="$1"
    if [[ "$mode" != "threaded" && "$mode" != "single" ]]; then
        kt_test_error "Invalid mode '$mode'. Must be 'threaded' or 'single'."
        return 1
    fi
    return 0
}

# Validate worker count
# Usage: kt_test_validate_workers "$WORKERS"
kt_test_validate_workers() {
    local workers="$1"
    if ! [[ "$workers" =~ ^[0-9]+$ ]] || [[ "$workers" -le 0 ]]; then
        kt_test_error "Invalid worker count '$workers'. Must be a positive integer."
        return 1
    fi
    return 0
}

# ============================================================================
# Warning Suppression Helper
# ============================================================================

# Temporarily suppress WARN messages while executing a command
# Usage: kt_warn_quiet command arg1 arg2 ...
kt_warn_quiet() {
    local original_verbosity="$VERBOSITY"
    VERBOSITY="error"
    "$@"
    local exit_code=$?
    VERBOSITY="$original_verbosity"
    return $exit_code
}

# ============================================================================
# Exports for use in other modules
# ============================================================================

# Export framework version for dependency checking
readonly KT__CORE_VERSION="1.0.0"

