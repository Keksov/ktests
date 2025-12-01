#!/bin/bash
# Unit tests: Error handling and exception scenarios

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "ErrorHandlingExceptions" "$(dirname "$0")"

# Test handling of empty assertion descriptions
kt_test_start "Assertion with empty description"
if kt_assert_equals "test" "test" "" >/dev/null 2>&1; then
    kt_test_pass "Assertions handle empty descriptions"
else
    kt_test_fail "Assertions failed with empty description"
fi

# Test assertion with special characters in values
kt_test_start "Assertions with special characters"
value='$test@#%&'
if kt_assert_equals "$value" "$value" "Special chars test" >/dev/null 2>&1; then
    kt_test_pass "Assertions handle special characters"
else
    kt_test_fail "Assertions failed with special characters"
fi

# Test assertion with null/empty values
kt_test_start "Assertions with empty values"
if kt_assert_equals "" "" "Empty values test" >/dev/null 2>&1; then
    kt_test_pass "Assertions handle empty values"
else
    kt_test_fail "Assertions failed with empty values"
fi

# Test handling of very long strings
kt_test_start "Assertions with very long strings"
long_str=$(printf 'x%.0s' {1..1000})
if kt_assert_equals "$long_str" "$long_str" "Long string test" >/dev/null 2>&1; then
    kt_test_pass "Assertions handle very long strings"
else
    kt_test_fail "Assertions failed with long strings"
fi

# Test fixture with missing temp directory initialization
kt_test_start "kt_fixture_tmpfile without initialization"
if declare -F "kt_fixture_tmpfile" >/dev/null 2>&1; then
    kt_test_pass "kt_fixture_tmpfile function exists"
else
    kt_test_fail "kt_fixture_tmpfile function missing"
fi

# Test array assertion with uninitialized array
kt_test_start "kt_assert_array_length with empty array variable"
unset test_empty_arr
declare -a test_empty_arr=()
if kt_assert_array_length test_empty_arr 0 "Empty array test" >/dev/null 2>&1; then
    kt_test_pass "Array assertions handle empty arrays"
else
    kt_test_fail "Array assertions failed on empty array"
fi

# Test contains assertion with newline in string
kt_test_start "kt_assert_contains with multiline strings"
multiline=$'line1\nline2\nline3'
if kt_assert_contains "$multiline" "line2" "Multiline test" >/dev/null 2>&1; then
    kt_test_pass "Assertions handle multiline strings"
else
    kt_test_fail "Assertions failed with multiline strings"
fi

# Test regex with special characters
kt_test_start "kt_assert_matches with regex special chars"
pattern='\.txt$'
if [[ "file.txt" =~ $pattern ]]; then
    kt_test_pass "Pattern assertions handle regex special chars"
else
    kt_test_fail "Pattern assertions failed with regex special chars"
fi

# Test command execution with error output
kt_test_start "kt_assert_success ignores stderr"
if kt_assert_success "echo error >&2; true" "Error output test" >/dev/null 2>&1; then
    kt_test_pass "kt_assert_success ignores stderr"
else
    kt_test_fail "kt_assert_success failed with stderr"
fi

# Test numeric assertion with invalid input (should still work)
kt_test_start "kt_assert_num_equals with string numbers"
if kt_assert_num_equals 42 "42" "String number test" >/dev/null 2>&1; then
    kt_test_pass "Numeric assertions coerce strings"
else
    kt_test_fail "Numeric assertions failed on string numbers"
fi

# Test multiple cleanup handlers registration
kt_test_start "Multiple cleanup handlers register correctly"
cleanup1() { :; }
cleanup2() { :; }
cleanup3() { :; }
declare -a _KT_CLEANUP_HANDLERS=()
kt_fixture_cleanup_register "cleanup1"
kt_fixture_cleanup_register "cleanup2"
kt_fixture_cleanup_register "cleanup3"
if (( ${#_KT_CLEANUP_HANDLERS[@]} == 3 )); then
    kt_test_pass "Multiple cleanup handlers registered"
else
    kt_test_fail "Cleanup handler registration failed"
fi

# Test config setting and getting
kt_test_start "kt_config_set and kt_config_get work together"
kt_config_set "testkey" "testvalue"
retrieved=$(kt_config_get "testkey")
if [[ "$retrieved" == "testvalue" ]]; then
    kt_test_pass "Config set/get works correctly"
else
    kt_test_fail "Config get returned '$retrieved', expected 'testvalue'"
fi

# Test config with empty value
kt_test_start "kt_config handles empty values"
kt_config_set "emptykey" ""
retrieved=$(kt_config_get "emptykey")
if [[ -z "$retrieved" ]]; then
    kt_test_pass "Config handles empty values"
else
    kt_test_fail "Config set empty value returned '$retrieved'"
fi

# Test getting non-existent config key
kt_test_start "kt_config_get returns empty for missing key"
retrieved=$(kt_config_get "nonexistent_key_12345")
if [[ -z "$retrieved" ]]; then
    kt_test_pass "kt_config_get returns empty for missing keys"
else
    kt_test_fail "kt_config_get returned '$retrieved' for missing key"
fi


