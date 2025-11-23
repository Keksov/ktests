#!/bin/bash
# Unit tests: String matching assertions

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "AssertionsStringMatching" "$(dirname "$0")"

# Test kk_assert_contains finds substring
kk_test_start "kk_assert_contains finds substring"
if kk_assert_contains "hello world" "world" "Substring match"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_contains fails when substring missing
kk_test_start "kk_assert_contains fails when substring missing"
if ! kk_assert_contains "hello world" "xyz" "Missing substring"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_not_contains with missing substring
kk_test_start "kk_assert_not_contains with missing substring"
if kk_assert_not_contains "hello world" "xyz" "Missing substring"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_not_contains fails when substring present
kk_test_start "kk_assert_not_contains fails when substring present"
if ! kk_assert_not_contains "hello world" "world" "Present substring"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_matches with valid regex pattern
kk_test_start "kk_assert_matches with valid regex pattern"
if kk_assert_matches "test123" "[0-9]+" "Regex match"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_matches fails with non-matching pattern
kk_test_start "kk_assert_matches fails with non-matching pattern"
if ! kk_assert_matches "test" "[0-9]+" "Non-matching pattern"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_not_matches with non-matching pattern
kk_test_start "kk_assert_not_matches with non-matching pattern"
if kk_assert_not_matches "test" "[0-9]+" "Non-matching pattern"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_not_matches fails when pattern matches
kk_test_start "kk_assert_not_matches fails when pattern matches"
if ! kk_assert_not_matches "test123" "[0-9]+" "Matching pattern"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_matches with word boundary pattern
kk_test_start "kk_assert_matches with word boundary pattern"
if kk_assert_matches "the word" "\bword\b" "Word boundary"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_matches with alternation pattern
kk_test_start "kk_assert_matches with alternation pattern"
if kk_assert_matches "cat" "cat|dog" "Alternation"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

echo __COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED
