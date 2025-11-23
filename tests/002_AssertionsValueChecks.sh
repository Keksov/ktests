#!/bin/bash
# Unit tests: Value assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "AssertionsValueChecks" "$(dirname "$0")"

# Test kk_assert_equals with equal values
kk_test_start "kk_assert_equals with equal values"
if kk_assert_equals "test" "test" "Equal values" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_equals detects equal values"
else
    kk_test_fail "kk_assert_equals failed with equal values"
fi

# Test kk_assert_equals with unequal values should fail
kk_test_start "kk_assert_equals with unequal values should fail"
if ! kk_assert_equals "test1" "test2" "Unequal values" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_equals detects unequal values"
else
    kk_test_fail "kk_assert_equals should have failed with unequal values"
fi

# Test kk_assert_not_equals with different values
kk_test_start "kk_assert_not_equals with different values"
if kk_assert_not_equals "test1" "test2" "Different values" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_not_equals detects different values"
else
    kk_test_fail "kk_assert_not_equals failed with different values"
fi

# Test kk_assert_not_equals with same values should fail
kk_test_start "kk_assert_not_equals with same values should fail"
if ! kk_assert_not_equals "test" "test" "Same values" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_not_equals detects identical values"
else
    kk_test_fail "kk_assert_not_equals should have failed with identical values"
fi

# Test kk_assert_true with non-empty string
kk_test_start "kk_assert_true with non-empty string"
if kk_assert_true "non-empty" "Non-empty test" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_true accepts non-empty values"
else
    kk_test_fail "kk_assert_true failed with non-empty value"
fi

# Test kk_assert_true with empty string should fail
kk_test_start "kk_assert_true with empty string should fail"
if ! kk_assert_true "" "Empty string test" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_true rejects empty values"
else
    kk_test_fail "kk_assert_true should have failed with empty value"
fi

# Test kk_assert_true with string 'false' should fail
kk_test_start "kk_assert_true with string 'false' should fail"
if ! kk_assert_true "false" "False string test" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_true rejects 'false' string"
else
    kk_test_fail "kk_assert_true should have failed with 'false'"
fi

# Test kk_assert_false with empty string
kk_test_start "kk_assert_false with empty string"
if kk_assert_false "" "Empty string test" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_false accepts empty values"
else
    kk_test_fail "kk_assert_false failed with empty value"
fi

# Test kk_assert_false with non-empty string should fail
kk_test_start "kk_assert_false with non-empty string should fail"
if ! kk_assert_false "non-empty" "Non-empty test" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_false rejects non-empty values"
else
    kk_test_fail "kk_assert_false should have failed with non-empty"
fi

# Test kk_assert_false with zero string
kk_test_start "kk_assert_false with zero string"
if kk_assert_false "0" "Zero test" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_false accepts zero value"
else
    kk_test_fail "kk_assert_false failed with zero"
fi
