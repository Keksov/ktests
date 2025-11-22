#!/bin/bash
# kk-test-assertions.sh - Assertion helpers for testing
# Provides common assertion patterns for testing shell functions
#
# Requires: kk-test-core.sh to be sourced first

# Prevent multiple sourcing
if [[ -n "$_KK_TEST_ASSERTIONS_SOURCED" ]]; then
    return
fi
_KK_TEST_ASSERTIONS_SOURCED=1

# Ensure core framework is available
if [[ -z "$_KK_TEST_CORE_SOURCED" ]]; then
    echo "ERROR: kk-test-core.sh must be sourced before kk-test-assertions.sh" >&2
    return 1
fi

# ============================================================================
# Value Assertions
# ============================================================================

# Assert that two values are equal
# Usage: kk_assert_equals "expected" "actual" "description"
kk_assert_equals() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-Value comparison}"
    
    if [[ "$expected" == "$actual" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected: '$expected', got: '$actual')"
        return 1
    fi
}

# Assert that two values are NOT equal
# Usage: kk_assert_not_equals "not_expected" "actual" "description"
kk_assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local desc="${3:-Value inequality check}"
    
    if [[ "$not_expected" != "$actual" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (value should not be '$actual')"
        return 1
    fi
}

# Assert that a value is true (non-empty, non-zero)
# Usage: kk_assert_true "value" "description"
kk_assert_true() {
    local value="$1"
    local desc="${2:-Truth assertion}"
    
    if [[ -n "$value" && "$value" != "0" && "$value" != "false" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected true-like value, got: '$value')"
        return 1
    fi
}

# Assert that a value is false (empty, zero, or "false")
# Usage: kk_assert_false "value" "description"
kk_assert_false() {
    local value="$1"
    local desc="${2:-False assertion}"
    
    if [[ -z "$value" || "$value" == "0" || "$value" == "false" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected false-like value, got: '$value')"
        return 1
    fi
}

# ============================================================================
# String Assertions
# ============================================================================

# Assert that a string contains a substring
# Usage: kk_assert_contains "haystack" "needle" "description"
kk_assert_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="${3:-String contains check}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected to find '$needle' in '$haystack')"
        return 1
    fi
}

# Assert that a string does NOT contain a substring
# Usage: kk_assert_not_contains "haystack" "needle" "description"
kk_assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="${3:-String does not contain check}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (should not find '$needle' in '$haystack')"
        return 1
    fi
}

# Assert that a string matches a regex pattern
# Usage: kk_assert_matches "string" "regex_pattern" "description"
kk_assert_matches() {
    local string="$1"
    local pattern="$2"
    local desc="${3:-Regex match check}"
    
    if [[ "$string" =~ $pattern ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected '$string' to match pattern '$pattern')"
        return 1
    fi
}

# Assert that a string does NOT match a regex pattern
# Usage: kk_assert_not_matches "string" "regex_pattern" "description"
kk_assert_not_matches() {
    local string="$1"
    local pattern="$2"
    local desc="${3:-Regex non-match check}"
    
    if [[ ! "$string" =~ $pattern ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected '$string' to NOT match pattern '$pattern')"
        return 1
    fi
}

# ============================================================================
# Numeric Assertions
# ============================================================================

# Assert numeric equality
# Usage: kk_assert_num_equals 5 5 "description"
kk_assert_num_equals() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-Numeric equality}"
    
    if (( expected == actual )); then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected: $expected, got: $actual)"
        return 1
    fi
}

# Assert numeric greater than
# Usage: kk_assert_num_gt 10 5 "description"
kk_assert_num_gt() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-Numeric greater than}"
    
    if (( actual > expected )); then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected $actual > $expected)"
        return 1
    fi
}

# Assert numeric less than
# Usage: kk_assert_num_lt 5 10 "description"
kk_assert_num_lt() {
    local max="$1"
    local actual="$2"
    local desc="${3:-Numeric less than}"
    
    if (( actual < max )); then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected $actual < $max)"
        return 1
    fi
}

# ============================================================================
# File System Assertions
# ============================================================================

# Assert that a file exists
# Usage: kk_assert_file_exists "/path/to/file" "description"
kk_assert_file_exists() {
    local filepath="$1"
    local desc="${2:-File exists check}"
    
    if [[ -f "$filepath" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (file not found: '$filepath')"
        return 1
    fi
}

# Assert that a file does NOT exist
# Usage: kk_assert_file_not_exists "/path/to/file" "description"
kk_assert_file_not_exists() {
    local filepath="$1"
    local desc="${2:-File does not exist check}"
    
    if [[ ! -f "$filepath" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (file should not exist: '$filepath')"
        return 1
    fi
}

# Assert that a directory exists
# Usage: kk_assert_dir_exists "/path/to/dir" "description"
kk_assert_dir_exists() {
    local dirpath="$1"
    local desc="${2:-Directory exists check}"
    
    if [[ -d "$dirpath" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (directory not found: '$dirpath')"
        return 1
    fi
}

# Assert that a directory does NOT exist
# Usage: kk_assert_dir_not_exists "/path/to/dir" "description"
kk_assert_dir_not_exists() {
    local dirpath="$1"
    local desc="${2:-Directory does not exist check}"
    
    if [[ ! -d "$dirpath" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (directory should not exist: '$dirpath')"
        return 1
    fi
}

# Assert that a file is readable
# Usage: kk_assert_file_readable "/path/to/file" "description"
kk_assert_file_readable() {
    local filepath="$1"
    local desc="${2:-File readable check}"
    
    if [[ -r "$filepath" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (file not readable: '$filepath')"
        return 1
    fi
}

# Assert that a file is writable
# Usage: kk_assert_file_writable "/path/to/file" "description"
kk_assert_file_writable() {
    local filepath="$1"
    local desc="${2:-File writable check}"
    
    if [[ -w "$filepath" ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (file not writable: '$filepath')"
        return 1
    fi
}

# ============================================================================
# Command Execution Assertions
# ============================================================================

# Assert that a command succeeds (exit code 0)
# Usage: kk_assert_success "command arg1 arg2" "description"
kk_assert_success() {
    local cmd="$1"
    local desc="${2:-Command success check}"
    
    if eval "$cmd" >/dev/null 2>&1; then
        kk_test_pass "$desc"
        return 0
    else
        local exit_code=$?
        kk_test_fail "$desc (command failed with exit code $exit_code)"
        return 1
    fi
}

# Assert that a command fails (non-zero exit code)
# Usage: kk_assert_failure "command arg1 arg2" "description"
kk_assert_failure() {
    local cmd="$1"
    local desc="${2:-Command failure check}"
    
    if ! eval "$cmd" >/dev/null 2>&1; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (command should have failed)"
        return 1
    fi
}

# ============================================================================
# Output Assertions
# ============================================================================

# Assert that command output contains a string
# Usage: output=$(some_command); kk_assert_output_contains "$output" "needle" "description"
kk_assert_output_contains() {
    local output="$1"
    local needle="$2"
    local desc="${3:-Output contains check}"
    
    if [[ "$output" == *"$needle"* ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected to find '$needle' in output)"
        kk_test_debug "Output was: $output"
        return 1
    fi
}

# Assert that command output does NOT contain a string
# Usage: output=$(some_command); kk_assert_output_not_contains "$output" "needle" "description"
kk_assert_output_not_contains() {
    local output="$1"
    local needle="$2"
    local desc="${3:-Output does not contain check}"
    
    if [[ "$output" != *"$needle"* ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (should not find '$needle' in output)"
        kk_test_debug "Output was: $output"
        return 1
    fi
}

# Assert that command output matches a regex
# Usage: output=$(some_command); kk_assert_output_matches "$output" "pattern" "description"
kk_assert_output_matches() {
    local output="$1"
    local pattern="$2"
    local desc="${3:-Output matches pattern}"
    
    if [[ "$output" =~ $pattern ]]; then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (output does not match pattern '$pattern')"
        kk_test_debug "Output was: $output"
        return 1
    fi
}

# ============================================================================
# Array Assertions
# ============================================================================

# Assert that an array has a specific length
# Usage: kk_assert_array_length "arr" 5 "description" (passes by reference)
kk_assert_array_length() {
    local -n arr="$1"
    local expected_len="$2"
    local desc="${3:-Array length check}"
    
    local actual_len="${#arr[@]}"
    
    if (( actual_len == expected_len )); then
        kk_test_pass "$desc"
        return 0
    else
        kk_test_fail "$desc (expected length $expected_len, got $actual_len)"
        return 1
    fi
}

# Assert that an array contains a value
# Usage: kk_assert_array_contains "arr" "value" "description" (passes by reference)
kk_assert_array_contains() {
    local -n arr="$1"
    local needle="$2"
    local desc="${3:-Array contains check}"
    
    for item in "${arr[@]}"; do
        if [[ "$item" == "$needle" ]]; then
            kk_test_pass "$desc"
            return 0
        fi
    done
    
    kk_test_fail "$desc (value '$needle' not found in array)"
    return 1
}

# ============================================================================
# Exports for use in tests
# ============================================================================

readonly KK_TEST_ASSERTIONS_VERSION="1.0.0"

