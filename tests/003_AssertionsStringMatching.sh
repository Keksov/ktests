#!/bin/bash
# Unit tests: String matching assertions

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "AssertionsStringMatching" "$(dirname "$0")"

# Test kk_assert_contains finds substring
kk_test_start "kk_assert_contains finds substring"
if kk_assert_contains "hello world" "world" "Substring match" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_contains detects present substring"
else
    kk_test_fail "kk_assert_contains failed to find substring"
fi

# Test kk_assert_contains fails when substring missing
kk_test_start "kk_assert_contains fails when substring missing"
if ! kk_assert_contains "hello world" "xyz" "Missing substring" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_contains detects missing substring"
else
    kk_test_fail "kk_assert_contains should have failed with missing substring"
fi

# Test kk_assert_not_contains with missing substring
kk_test_start "kk_assert_not_contains with missing substring"
if kk_assert_not_contains "hello world" "xyz" "Missing substring" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_not_contains detects missing substring"
else
    kk_test_fail "kk_assert_not_contains failed with missing substring"
fi

# Test kk_assert_not_contains fails when substring present
kk_test_start "kk_assert_not_contains fails when substring present"
if ! kk_assert_not_contains "hello world" "world" "Present substring" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_not_contains detects present substring"
else
    kk_test_fail "kk_assert_not_contains should have failed with present substring"
fi

# Test kk_assert_matches with valid regex pattern
kk_test_start "kk_assert_matches with valid regex pattern"
if kk_assert_matches "test123" "[0-9]+" "Regex match" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_matches detects matching pattern"
else
    kk_test_fail "kk_assert_matches failed with valid pattern"
fi

# Test kk_assert_matches fails with non-matching pattern
kk_test_start "kk_assert_matches fails with non-matching pattern"
if ! kk_assert_matches "test" "[0-9]+" "Non-matching pattern" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_matches detects non-matching pattern"
else
    kk_test_fail "kk_assert_matches should have failed with non-matching pattern"
fi

# Test kk_assert_not_matches with non-matching pattern
kk_test_start "kk_assert_not_matches with non-matching pattern"
if kk_assert_not_matches "test" "[0-9]+" "Non-matching pattern" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_not_matches detects non-matching pattern"
else
    kk_test_fail "kk_assert_not_matches failed with non-matching pattern"
fi

# Test kk_assert_not_matches fails when pattern matches
kk_test_start "kk_assert_not_matches fails when pattern matches"
if ! kk_assert_not_matches "test123" "[0-9]+" "Matching pattern" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_not_matches detects matching pattern"
else
    kk_test_fail "kk_assert_not_matches should have failed with matching pattern"
fi

# Test kk_assert_matches with word boundary pattern
kk_test_start "kk_assert_matches with word boundary pattern"
if kk_assert_matches "the word" "\bword\b" "Word boundary" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_matches handles word boundary patterns"
else
    kk_test_fail "kk_assert_matches failed with word boundary"
fi

# Test kk_assert_matches with alternation pattern
kk_test_start "kk_assert_matches with alternation pattern"
if kk_assert_matches "cat" "cat|dog" "Alternation" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_matches handles alternation patterns"
else
    kk_test_fail "kk_assert_matches failed with alternation"
fi
