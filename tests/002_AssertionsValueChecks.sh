#!/bin/bash
# Unit tests: Value assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "AssertionsValueChecks" "$(dirname "$0")"

# Test kk_assert_equals with equal values
kk_test_start "kk_assert_equals with equal values"
if kk_assert_equals "test" "test" "Equal values"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_equals with unequal values should fail
kk_test_start "kk_assert_equals with unequal values should fail"
if ! kk_assert_equals "test1" "test2" "Unequal values"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_not_equals with different values
kk_test_start "kk_assert_not_equals with different values"
if kk_assert_not_equals "test1" "test2" "Different values"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_not_equals with same values should fail
kk_test_start "kk_assert_not_equals with same values should fail"
if ! kk_assert_not_equals "test" "test" "Same values"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_true with non-empty string
kk_test_start "kk_assert_true with non-empty string"
if kk_assert_true "non-empty" "Non-empty test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_true with empty string should fail
kk_test_start "kk_assert_true with empty string should fail"
if ! kk_assert_true "" "Empty string test"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_true with string 'false' should fail
kk_test_start "kk_assert_true with string 'false' should fail"
if ! kk_assert_true "false" "False string test"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_false with empty string
kk_test_start "kk_assert_false with empty string"
if kk_assert_false "" "Empty string test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_false with non-empty string should fail
kk_test_start "kk_assert_false with non-empty string should fail"
if ! kk_assert_false "non-empty" "Non-empty test"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_false with zero string
kk_test_start "kk_assert_false with zero string"
if kk_assert_false "0" "Zero test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi


