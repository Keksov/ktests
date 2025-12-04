#!/bin/bash
# ktest_assertions.sh - Assertion helpers for testing
# Provides common assertion patterns for testing shell functions
#
# Requires: ktest_core.sh to be sourced first

# Prevent multiple sourcing
if [[ -n "$_KTEST_ASSERTIONS_SOURCED" ]]; then
    return
fi
declare -g _KTEST_ASSERTIONS_SOURCED=1

# Ensure core framework is available
if [[ -z "$_KTEST_CORE_SOURCED" ]]; then
    echo "ERROR: ktest_core.sh must be sourced before ktest_assertions.sh"
    return 1
fi

# ============================================================================
# Global Variables
# ============================================================================

# Control whether assertion failures are printed to stderr
# Set to "quiet" to suppress output when using "if ! kt_assert_*" pattern
declare -g _KT_ASSERT_QUIET_MODE="${_KT_ASSERT_QUIET_MODE:-normal}"

# Helper function to conditionally output assertion errors
_kt_assert_output_error() {
    local message="$1"
    if [[ "$_KT_ASSERT_QUIET_MODE" != "quiet" ]]; then
        echo -e "$message"
    fi
}

# Wrapper function to suppress assertion failure output
# Usage in tests:
#   if ! kt_assert_quiet kt_assert_equals "a" "b" "test message"; then
#       kt_test_pass "Assertion correctly failed as expected"
#   fi
kt_assert_quiet() {
    local old_mode="$_KT_ASSERT_QUIET_MODE"
    _KT_ASSERT_QUIET_MODE="quiet"
    "$@"
    local result=$?
    _KT_ASSERT_QUIET_MODE="$old_mode"
    return $result
}

# Wrapper function to suppress test result output (intentional passes/failures)
# Useful when testing code that intentionally produces test failures
# Usage in tests:
#   kt_test_quiet kt_test_fail "This should fail"
#   kt_test_quiet kt_test_pass "And this should pass"
kt_test_quiet() {
    local old_mode="$_KTEST_QUIET_MODE"
    _KTEST_QUIET_MODE="quiet"
    "$@"
    local result=$?
    _KTEST_QUIET_MODE="$old_mode"
    return $result
}

# ============================================================================
# Value Assertions
# ============================================================================

# Assert that two values are equal
# Usage: kt_assert_equals "expected" "actual" "description"
kt_assert_equals() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-Value comparison}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected: '$expected', got: '$actual')"
        return 1
    fi
}

# Assert that two values are NOT equal
# Usage: kt_assert_not_equals "not_expected" "actual" "description"
kt_assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local desc="${3:-Value inequality check}"
    
    if [[ "$not_expected" != "$actual" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (value should not be '$actual')"
        return 1
    fi
}

# Assert that a value is true (non-empty, non-zero)
# Usage: kt_assert_true "value" "description"
kt_assert_true() {
    local value="$1"
    local desc="${2:-Truth assertion}"
    
    if [[ -n "$value" && "$value" != "0" && "$value" != "false" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected true-like value, got: '$value')"
        return 1
    fi
}

# Assert that a value is false (empty, zero, or "false")
# Usage: kt_assert_false "value" "description"
kt_assert_false() {
    local value="$1"
    local desc="${2:-False assertion}"
    
    if [[ -z "$value" || "$value" == "0" || "$value" == "false" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected false-like value, got: '$value')"
        return 1
    fi
}

# ============================================================================
# String Assertions
# ============================================================================

# Assert that a string contains a substring
# Usage: kt_assert_contains "haystack" "needle" "description"
kt_assert_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="${3:-String contains check}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected to find '$needle' in '$haystack')"
        return 1
    fi
}

# Assert that a string does NOT contain a substring
# Usage: kt_assert_not_contains "haystack" "needle" "description"
kt_assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="${3:-String does not contain check}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (should not find '$needle' in '$haystack')"
        return 1
    fi
}

# Assert that a string matches a regex pattern
# Usage: kt_assert_matches "string" "regex_pattern" "description"
kt_assert_matches() {
    local string="$1"
    local pattern="$2"
    local desc="${3:-Regex match check}"
    
    if [[ "$string" =~ $pattern ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected '$string' to match pattern '$pattern')"
        return 1
    fi
}

# Assert that a string does NOT match a regex pattern
# Usage: kt_assert_not_matches "string" "regex_pattern" "description"
kt_assert_not_matches() {
    local string="$1"
    local pattern="$2"
    local desc="${3:-Regex non-match check}"
    
    if [[ ! "$string" =~ $pattern ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected '$string' to NOT match pattern '$pattern')"
        return 1
    fi
}

# ============================================================================
# Numeric Assertions
# ============================================================================

# Assert numeric equality
# Usage: kt_assert_num_equals 5 5 "description"
kt_assert_num_equals() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-Numeric equality}"
    
    if (( expected == actual )); then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected: $expected, got: $actual)"
        return 1
    fi
}

# Assert numeric greater than
# Usage: kt_assert_num_gt 10 5 "description"
kt_assert_num_gt() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-Numeric greater than}"
    
    if (( actual > expected )); then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected $actual > $expected)"
        return 1
    fi
}

# Assert numeric less than
# Usage: kt_assert_num_lt 5 10 "description"
kt_assert_num_lt() {
    local max="$1"
    local actual="$2"
    local desc="${3:-Numeric less than}"
    
    if (( actual < max )); then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected $actual < $max)"
        return 1
    fi
}

# ============================================================================
# File System Assertions
# ============================================================================

# Assert that a file exists
# Usage: kt_assert_file_exists "/path/to/file" "description"
kt_assert_file_exists() {
    local filepath="$1"
    local desc="${2:-File exists check}"
    
    if [[ -f "$filepath" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (file not found: '$filepath')"
        return 1
    fi
}

# Assert that a file does NOT exist
# Usage: kt_assert_file_not_exists "/path/to/file" "description"
kt_assert_file_not_exists() {
    local filepath="$1"
    local desc="${2:-File does not exist check}"
    
    if [[ ! -f "$filepath" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (file should not exist: '$filepath')"
        return 1
    fi
}

# Assert that a directory exists
# Usage: kt_assert_dir_exists "/path/to/dir" "description"
kt_assert_dir_exists() {
    local dirpath="$1"
    local desc="${2:-Directory exists check}"
    
    if [[ -d "$dirpath" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (directory not found: '$dirpath')"
        return 1
    fi
}

# Assert that a directory does NOT exist
# Usage: kt_assert_dir_not_exists "/path/to/dir" "description"
kt_assert_dir_not_exists() {
    local dirpath="$1"
    local desc="${2:-Directory does not exist check}"
    
    if [[ ! -d "$dirpath" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (directory should not exist: '$dirpath')"
        return 1
    fi
}

# Assert that a file is readable
# Usage: kt_assert_file_readable "/path/to/file" "description"
kt_assert_file_readable() {
    local filepath="$1"
    local desc="${2:-File readable check}"
    
    if [[ -r "$filepath" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (file not readable: '$filepath')"
        return 1
    fi
}

# Assert that a file is writable
# Usage: kt_assert_file_writable "/path/to/file" "description"
kt_assert_file_writable() {
    local filepath="$1"
    local desc="${2:-File writable check}"
    
    if [[ -w "$filepath" ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (file not writable: '$filepath')"
        return 1
    fi
}

# ============================================================================
# Command Execution Assertions
# ============================================================================

# Assert that a command succeeds (exit code 0)
# Usage: kt_assert_success "command arg1 arg2" "description"
kt_assert_success() {
    local cmd="$1"
    local desc="${2:-Command success check}"
    
    if bash -c "$cmd" >/dev/null 2>&1; then
        return 0
    else
        local exit_code=$?
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (command failed with exit code $exit_code)"
        return 1
    fi
}

# Assert that a command fails (non-zero exit code)
# Usage: kt_assert_failure "command arg1 arg2" "description"
kt_assert_failure() {
    local cmd="$1"
    local desc="${2:-Command failure check}"
    
    if ! bash -c "$cmd" >/dev/null 2>&1; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (command should have failed)"
        return 1
    fi
}

# ============================================================================
# Output Assertions
# ============================================================================

# Assert that command output contains a string
# Usage: output=$(some_command); kt_assert_output_contains "$output" "needle" "description"
kt_assert_output_contains() {
    local output="$1"
    local needle="$2"
    local desc="${3:-Output contains check}"
    
    if [[ "$output" == *"$needle"* ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected to find '$needle' in output)"
        kt_test_debug "Output was: $output"
        return 1
    fi
}

# Assert that command output does NOT contain a string
# Usage: output=$(some_command); kt_assert_output_not_contains "$output" "needle" "description"
kt_assert_output_not_contains() {
    local output="$1"
    local needle="$2"
    local desc="${3:-Output does not contain check}"
    
    if [[ "$output" != *"$needle"* ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (should not find '$needle' in output)"
        kt_test_debug "Output was: $output"
        return 1
    fi
}

# Assert that command output matches a regex
# Usage: output=$(some_command); kt_assert_output_matches "$output" "pattern" "description"
kt_assert_output_matches() {
    local output="$1"
    local pattern="$2"
    local desc="${3:-Output matches pattern}"
    
    if [[ "$output" =~ $pattern ]]; then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (output does not match pattern '$pattern')"
        kt_test_debug "Output was: $output"
        return 1
    fi
}

# ============================================================================
# Array Assertions
# ============================================================================

# Assert that an array has a specific length
# Usage: kt_assert_array_length "arr" 5 "description" (passes by reference)
kt_assert_array_length() {
    local -n arr="$1"
    local expected_len="$2"
    local desc="${3:-Array length check}"
    
    local actual_len="${#arr[@]}"
    
    if (( actual_len == expected_len )); then
        return 0
    else
        _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (expected length $expected_len, got $actual_len)"
        return 1
    fi
}

# Assert that an array contains a value
# Usage: kt_assert_array_contains "arr" "value" "description" (passes by reference)
kt_assert_array_contains() {
    local -n arr="$1"
    local needle="$2"
    local desc="${3:-Array contains check}"
    
    for item in "${arr[@]}"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done
    
            _kt_assert_output_error "${KT_RED}[ASSERTION FAILED]${KT_NC} $desc (value '$needle' not found in array)"
    return 1
}

# ============================================================================
# Exports for use in tests
# ============================================================================

readonly KT__ASSERTIONS_VERSION="1.0.0"

