#!/bin/bash
# Unit tests: Array assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "AssertionsArrayChecks" "$(dirname "$0")"

# Test kk_assert_array_length with correct length
kk_test_start "kk_assert_array_length with correct length"
declare -a test_arr=("a" "b" "c")
if kk_assert_array_length test_arr 3 "Array length"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_length with incorrect length
kk_test_start "kk_assert_array_length with incorrect length"
if ! kk_assert_array_length test_arr 5 "Array length"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_array_length with empty array variable
kk_test_start "kk_assert_array_length with empty array variable"
unset test_empty_arr
declare -a test_empty_arr=()
if kk_assert_array_length test_empty_arr 0 "Empty array test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

echo __COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED
