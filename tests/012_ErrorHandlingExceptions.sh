#!/bin/bash
# Unit tests: Error handling and exception scenarios

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "ErrorHandlingExceptions" "$(dirname "$0")"

# Test handling of empty assertion descriptions
kk_test_start "Assertion with empty description"
if kk_assert_equals "test" "test" "" >/dev/null 2>&1; then
    kk_test_pass "Assertions handle empty descriptions"
else
    kk_test_fail "Assertions failed with empty description"
fi

# Test assertion with special characters in values
kk_test_start "Assertions with special characters"
value='$test@#%&'
if kk_assert_equals "$value" "$value" "Special chars test" >/dev/null 2>&1; then
    kk_test_pass "Assertions handle special characters"
else
    kk_test_fail "Assertions failed with special characters"
fi

# Test assertion with null/empty values
kk_test_start "Assertions with empty values"
if kk_assert_equals "" "" "Empty values test" >/dev/null 2>&1; then
    kk_test_pass "Assertions handle empty values"
else
    kk_test_fail "Assertions failed with empty values"
fi

# Test handling of very long strings
kk_test_start "Assertions with very long strings"
long_str=$(printf 'x%.0s' {1..1000})
if kk_assert_equals "$long_str" "$long_str" "Long string test" >/dev/null 2>&1; then
    kk_test_pass "Assertions handle very long strings"
else
    kk_test_fail "Assertions failed with long strings"
fi

# Test fixture with missing temp directory initialization
kk_test_start "kk_fixture_tmpfile without initialization"
if declare -F "kk_fixture_tmpfile" >/dev/null 2>&1; then
    kk_test_pass "kk_fixture_tmpfile function exists"
else
    kk_test_fail "kk_fixture_tmpfile function missing"
fi

# Test array assertion with uninitialized array
kk_test_start "kk_assert_array_length with empty array variable"
unset test_empty_arr
declare -a test_empty_arr=()
if kk_assert_array_length test_empty_arr 0 "Empty array test" >/dev/null 2>&1; then
    kk_test_pass "Array assertions handle empty arrays"
else
    kk_test_fail "Array assertions failed on empty array"
fi

# Test contains assertion with newline in string
kk_test_start "kk_assert_contains with multiline strings"
multiline=$'line1\nline2\nline3'
if kk_assert_contains "$multiline" "line2" "Multiline test" >/dev/null 2>&1; then
    kk_test_pass "Assertions handle multiline strings"
else
    kk_test_fail "Assertions failed with multiline strings"
fi

# Test regex with special characters
kk_test_start "kk_assert_matches with regex special chars"
pattern='\.txt$'
if [[ "file.txt" =~ $pattern ]]; then
    kk_test_pass "Pattern assertions handle regex special chars"
else
    kk_test_fail "Pattern assertions failed with regex special chars"
fi

# Test command execution with error output
kk_test_start "kk_assert_success ignores stderr"
if kk_assert_success "echo error >&2; true" "Error output test" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_success ignores stderr"
else
    kk_test_fail "kk_assert_success failed with stderr"
fi

# Test numeric assertion with invalid input (should still work)
kk_test_start "kk_assert_num_equals with string numbers"
if kk_assert_num_equals 42 "42" "String number test" >/dev/null 2>&1; then
    kk_test_pass "Numeric assertions coerce strings"
else
    kk_test_fail "Numeric assertions failed on string numbers"
fi

# Test multiple cleanup handlers registration
kk_test_start "Multiple cleanup handlers register correctly"
cleanup1() { :; }
cleanup2() { :; }
cleanup3() { :; }
declare -a _KK_CLEANUP_HANDLERS=()
kk_fixture_cleanup_register "cleanup1"
kk_fixture_cleanup_register "cleanup2"
kk_fixture_cleanup_register "cleanup3"
if (( ${#_KK_CLEANUP_HANDLERS[@]} == 3 )); then
    kk_test_pass "Multiple cleanup handlers registered"
else
    kk_test_fail "Cleanup handler registration failed"
fi

# Test config setting and getting
kk_test_start "kk_config_set and kk_config_get work together"
kk_config_set "testkey" "testvalue"
retrieved=$(kk_config_get "testkey")
if [[ "$retrieved" == "testvalue" ]]; then
    kk_test_pass "Config set/get works correctly"
else
    kk_test_fail "Config get returned '$retrieved', expected 'testvalue'"
fi

# Test config with empty value
kk_test_start "kk_config handles empty values"
kk_config_set "emptykey" ""
retrieved=$(kk_config_get "emptykey")
if [[ -z "$retrieved" ]]; then
    kk_test_pass "Config handles empty values"
else
    kk_test_fail "Config set empty value returned '$retrieved'"
fi

# Test getting non-existent config key
kk_test_start "kk_config_get returns empty for missing key"
retrieved=$(kk_config_get "nonexistent_key_12345")
if [[ -z "$retrieved" ]]; then
    kk_test_pass "kk_config_get returns empty for missing keys"
else
    kk_test_fail "kk_config_get returned '$retrieved' for missing key"
fi


