#!/bin/bash
# kk-test-core.sh - Core testing framework
# Provides fundamental logging, counters, and test result tracking
# 
# This is the foundation for all KK testing utilities. It should be sourced
# first by test suites before other framework components.

# Prevent multiple sourcing
if [[ -n "$_KK_TEST_CORE_SOURCED" ]]; then
    return
fi
_KK_TEST_CORE_SOURCED=1

# ============================================================================
# Color Definitions
# ============================================================================

# ANSI color codes
readonly KK_RED='\033[0;31m'
readonly KK_GREEN='\033[0;32m'
readonly KK_YELLOW='\033[1;33m'
readonly KK_BLUE='\033[0;34m'
readonly KK_CYAN='\033[0;36m'
readonly KK_NC='\033[0m'  # No Color

# Backward compatibility aliases
RED="$KK_RED"
GREEN="$KK_GREEN"
YELLOW="$KK_YELLOW"
BLUE="$KK_BLUE"
CYAN="$KK_CYAN"
NC="$KK_NC"

# ============================================================================
# Test Counter Management
# ============================================================================

# Global test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Verbosity levels: "error" (minimal) or "info" (verbose)
VERBOSITY="${VERBOSITY:-error}"

# ============================================================================
# Configuration Management
# ============================================================================

declare -gA _KK_CONFIG=(
    [verbosity]="error"
    [debug]="false"
    [color]="true"
)

# Get a configuration value
kk_config_get() {
    local key="$1"
    echo "${_KK_CONFIG[$key]:-}"
}

# Set a configuration value
kk_config_set() {
    local key="$1"
    local value="$2"
    _KK_CONFIG[$key]="$value"
    # Sync with VERBOSITY global
    if [[ "$key" == "verbosity" ]]; then
        VERBOSITY="$value"
    fi
}

# ============================================================================
# Logging Functions
# ============================================================================

# Log an informational message (shown only if VERBOSITY is "info")
kk_test_log() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

# Log debug information (only if debug mode is enabled)
kk_test_debug() {
    if [[ "${_KK_CONFIG[debug]}" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $*" >&2
    fi
}

# Log an error message (always shown)
kk_test_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Log a warning message (always shown)
kk_test_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

# Print a section header (shown only if VERBOSITY is "info")
kk_test_section() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo ""
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}$*${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo ""
    fi
}

# ============================================================================
# Test Tracking Functions
# ============================================================================

# Mark the start of a test
# Usage: kk_test_start "Test description"
kk_test_start() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo -e "${BLUE}[TEST]${NC} $*"
    fi
    ((TESTS_TOTAL++))
}

# Mark a test as passed
# Usage: kk_test_pass "Test description"
kk_test_pass() {
    if [[ "$VERBOSITY" == "info" ]]; then
        echo -e "${GREEN}[PASS]${NC} $*"
    fi
    ((TESTS_PASSED++))
}

# Mark a test as failed
# Usage: kk_test_fail "Test description"
kk_test_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
}

# Backward compatibility aliases (existing test code uses these)
test_start() { kk_test_start "$@"; }
test_pass() { kk_test_pass "$@"; }
test_fail() { kk_test_fail "$@"; }
test_info() { kk_test_log "$@"; }
test_section() { kk_test_section "$@"; }

# ============================================================================
# Counter Management
# ============================================================================

# Reset all test counters
kk_test_reset_counts() {
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
}

# Get current test counts as string
# Usage: counts=$(kk_test_get_counts)
# Output format: "total:passed:failed"
kk_test_get_counts() {
    echo "$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
}

# Parse test counts from string
# Usage: kk_test_parse_counts "10:8:2" TOTAL PASSED FAILED
kk_test_parse_counts() {
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
# Usage: kk_test_accumulate_counts "5:4:1"
kk_test_accumulate_counts() {
    local counts_str="$1"
    local t p f
    kk_test_parse_counts "$counts_str" t p f
    ((TESTS_TOTAL += t))
    ((TESTS_PASSED += p))
    ((TESTS_FAILED += f))
}

# ============================================================================
# Results Display
# ============================================================================

# Show test results summary
# Usage: kk_test_show_results
kk_test_show_results() {
    local total="${TESTS_TOTAL:-0}"
    local passed="${TESTS_PASSED:-0}"
    local failed="${TESTS_FAILED:-0}"
    
    if [[ "$VERBOSITY" == "info" ]]; then
        echo ""
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}Test Results Summary${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo "Total tests: $total"
        echo -e "Passed: ${GREEN}$passed${NC}"
        echo -e "Failed: ${RED}$failed${NC}"
        
        if [[ $failed -eq 0 ]]; then
            echo -e "${GREEN}✓ All tests passed!${NC}"
        else
            echo -e "${RED}✗ $failed test(s) failed.${NC}"
        fi
    else
        echo "Total tests: $total"
        echo "Passed: $passed"
        echo "Failed: $failed"
    fi
    
    return "$((failed > 0 ? 1 : 0))"
}

# Format test results for output with counter marker
# Usage: echo "$(kk_test_format_counts)"
# Output: __COUNTS__:total:passed:failed
kk_test_format_counts() {
    echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
}

# ============================================================================
# Validation Helpers
# ============================================================================

# Validate verbosity setting
# Usage: kk_test_validate_verbosity "$VERBOSITY"
kk_test_validate_verbosity() {
    local verb="$1"
    if [[ "$verb" != "info" && "$verb" != "error" ]]; then
        kk_test_error "Invalid verbosity '$verb'. Must be 'info' or 'error'."
        return 1
    fi
    return 0
}

# Validate execution mode
# Usage: kk_test_validate_mode "$MODE"
kk_test_validate_mode() {
    local mode="$1"
    if [[ "$mode" != "threaded" && "$mode" != "single" ]]; then
        kk_test_error "Invalid mode '$mode'. Must be 'threaded' or 'single'."
        return 1
    fi
    return 0
}

# Validate worker count
# Usage: kk_test_validate_workers "$WORKERS"
kk_test_validate_workers() {
    local workers="$1"
    if ! [[ "$workers" =~ ^[0-9]+$ ]] || [[ "$workers" -le 0 ]]; then
        kk_test_error "Invalid worker count '$workers'. Must be a positive integer."
        return 1
    fi
    return 0
}

# ============================================================================
# Exports for use in other modules
# ============================================================================

# Export framework version for dependency checking
readonly KK_TEST_CORE_VERSION="1.0.0"

