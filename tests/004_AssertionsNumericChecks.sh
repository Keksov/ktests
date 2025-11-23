#!/bin/bash
# Unit tests: Numeric assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "AssertionsNumericChecks" "$(dirname "$0")"

# Test kk_assert_num_equals with equal numbers
kk_test_start "kk_assert_num_equals with equal numbers"
if kk_assert_num_equals 42 42 "Equal numbers" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_num_equals detects equal numbers"
else
    kk_test_fail "kk_assert_num_equals failed with equal numbers"
fi

# Test kk_assert_num_equals fails with unequal numbers
kk_test_start "kk_assert_num_equals fails with unequal numbers"
if ! kk_assert_num_equals 42 43 "Unequal numbers" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_num_equals detects unequal numbers"
else
    kk_test_fail "kk_assert_num_equals should have failed with unequal numbers"
fi

# Test kk_assert_num_gt with greater number
kk_test_start "kk_assert_num_gt with greater number"
if kk_assert_num_gt 5 10 "Greater than" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_num_gt detects greater number"
else
    kk_test_fail "kk_assert_num_gt failed with greater number"
fi

# Test kk_assert_num_gt fails when not greater
kk_test_start "kk_assert_num_gt fails when not greater"
if ! kk_assert_num_gt 10 5 "Not greater" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_num_gt detects non-greater number"
else
    kk_test_fail "kk_assert_num_gt should have failed when not greater"
fi

# Test kk_assert_num_gt fails when numbers are equal
kk_test_start "kk_assert_num_gt fails when numbers are equal"
if ! kk_assert_num_gt 5 5 "Equal numbers" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_num_gt detects equal numbers"
else
    kk_test_fail "kk_assert_num_gt should have failed with equal numbers"
fi

# Test kk_assert_num_lt with smaller number
kk_test_start "kk_assert_num_lt with smaller number"
if kk_assert_num_lt 10 5 "Less than" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_num_lt detects smaller number"
else
    kk_test_fail "kk_assert_num_lt failed with smaller number"
fi

# Test kk_assert_num_lt fails when not less
kk_test_start "kk_assert_num_lt fails when not less"
if ! kk_assert_num_lt 5 10 "Not less" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_num_lt detects non-smaller number"
else
    kk_test_fail "kk_assert_num_lt should have failed when not less"
fi
