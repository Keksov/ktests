#!/bin/bash
# Unit tests: Value assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "AssertionsValueChecks" "$(dirname "$0")" "$@"

# Test kt_assert_equals with equal values
kt_test_start "kt_assert_equals with equal values"
if kt_assert_equals "test" "test" "Equal values"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_equals with unequal values should fail
kt_test_start "kt_assert_equals with unequal values should fail"
if ! kt_assert_quiet kt_assert_equals "test1" "test2" "Unequal values"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_not_equals with different values
kt_test_start "kt_assert_not_equals with different values"
if kt_assert_not_equals "test1" "test2" "Different values"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_not_equals with same values should fail
kt_test_start "kt_assert_not_equals with same values should fail"
if ! kt_assert_quiet kt_assert_not_equals "test" "test" "Same values"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_true with non-empty string
kt_test_start "kt_assert_true with non-empty string"
if kt_assert_true "non-empty" "Non-empty test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_true with empty string should fail
kt_test_start "kt_assert_true with empty string should fail"
if ! kt_assert_quiet kt_assert_true "" "Empty string test"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_true with string 'false' should fail
kt_test_start "kt_assert_true with string 'false' should fail"
if ! kt_assert_quiet kt_assert_true "false" "False string test"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_false with empty string
kt_test_start "kt_assert_false with empty string"
if kt_assert_false "" "Empty string test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_false with non-empty string should fail
kt_test_start "kt_assert_false with non-empty string should fail"
if ! kt_assert_quiet kt_assert_false "non-empty" "Non-empty test"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_false with zero string
kt_test_start "kt_assert_false with zero string"
if kt_assert_false "0" "Zero test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi


