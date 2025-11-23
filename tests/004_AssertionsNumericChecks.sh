#!/bin/bash
# Unit tests: Numeric assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "AssertionsNumericChecks" "$(dirname "$0")"

# Test kk_assert_num_equals with equal numbers
kk_test_start "kk_assert_num_equals with equal numbers"
if kk_assert_num_equals 42 42 "Equal numbers"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_num_equals fails with unequal numbers
kk_test_start "kk_assert_num_equals fails with unequal numbers"
if ! kk_assert_num_equals 42 43 "Unequal numbers"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_num_gt with greater number
kk_test_start "kk_assert_num_gt with greater number"
if kk_assert_num_gt 5 10 "Greater than"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_num_gt fails when not greater
kk_test_start "kk_assert_num_gt fails when not greater"
if ! kk_assert_num_gt 10 5 "Not greater"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_num_gt fails when numbers are equal
kk_test_start "kk_assert_num_gt fails when numbers are equal"
if ! kk_assert_num_gt 5 5 "Equal numbers"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_num_lt with smaller number
kk_test_start "kk_assert_num_lt with smaller number"
if kk_assert_num_lt 10 5 "Less than"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_num_lt fails when not less
kk_test_start "kk_assert_num_lt fails when not less"
if ! kk_assert_num_lt 5 10 "Not less"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

echo __COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED
