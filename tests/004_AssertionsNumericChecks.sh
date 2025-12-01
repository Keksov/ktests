#!/bin/bash
# Unit tests: Numeric assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "AssertionsNumericChecks" "$(dirname "$0")"

# Test kt_assert_num_equals with equal numbers
kt_test_start "kt_assert_num_equals with equal numbers"
if kt_assert_num_equals 42 42 "Equal numbers"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_num_equals fails with unequal numbers
kt_test_start "kt_assert_num_equals fails with unequal numbers"
if ! kt_assert_quiet kt_assert_num_equals 42 43 "Unequal numbers"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_num_gt with greater number
kt_test_start "kt_assert_num_gt with greater number"
if kt_assert_num_gt 5 10 "Greater than"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_num_gt fails when not greater
kt_test_start "kt_assert_num_gt fails when not greater"
if ! kt_assert_quiet kt_assert_num_gt 10 5 "Not greater"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_num_gt fails when numbers are equal
kt_test_start "kt_assert_num_gt fails when numbers are equal"
if ! kt_assert_quiet kt_assert_num_gt 5 5 "Equal numbers"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_num_lt with smaller number
kt_test_start "kt_assert_num_lt with smaller number"
if kt_assert_num_lt 10 5 "Less than"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_num_lt fails when not less
kt_test_start "kt_assert_num_lt fails when not less"
if ! kt_assert_quiet kt_assert_num_lt 5 10 "Not less"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi


