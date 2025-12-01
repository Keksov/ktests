#!/bin/bash
# Unit tests: Array assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "AssertionsArrayChecks" "$(dirname "$0")"

# Test kt_assert_array_length with correct length
kt_test_start "kt_assert_array_length with correct length"
declare -a test_arr=("a" "b" "c")
if kt_assert_array_length test_arr 3 "Array length"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_array_length with incorrect length
kt_test_start "kt_assert_array_length with incorrect length"
if ! kt_assert_quiet kt_assert_array_length test_arr 5 "Array length"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_array_length with empty array variable
kt_test_start "kt_assert_array_length with empty array variable"
unset test_empty_arr
declare -a test_empty_arr=()
if kt_assert_array_length test_empty_arr 0 "Empty array test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi


