#!/usr/bin/env bash
# Unit tests: String matching assertions

# Only source if framework not already loaded
if [[ -z "$_KTEST_SOURCED" ]]; then
    source "$(dirname "$0")/../ktest_source.sh" || source "$KTEST_SOURCE_PATH" || exit 1
fi

kt_test_init "AssertionsStringMatching" "$(dirname "$0")"

# Test kt_assert_contains finds substring
kt_test_start "kt_assert_contains finds substring"
if kt_assert_contains "hello world" "world" "Substring match"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_contains fails when substring missing
kt_test_start "kt_assert_contains fails when substring missing"
if ! kt_assert_quiet kt_assert_contains "hello world" "xyz" "Missing substring"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_not_contains with missing substring
kt_test_start "kt_assert_not_contains with missing substring"
if kt_assert_not_contains "hello world" "xyz" "Missing substring"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_not_contains fails when substring present
kt_test_start "kt_assert_not_contains fails when substring present"
if ! kt_assert_quiet kt_assert_not_contains "hello world" "world" "Present substring"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_matches with valid regex pattern
kt_test_start "kt_assert_matches with valid regex pattern"
if kt_assert_matches "test123" "[0-9]+" "Regex match"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_matches fails with non-matching pattern
kt_test_start "kt_assert_matches fails with non-matching pattern"
if ! kt_assert_quiet kt_assert_matches "test" "[0-9]+" "Non-matching pattern"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_not_matches with non-matching pattern
kt_test_start "kt_assert_not_matches with non-matching pattern"
if kt_assert_not_matches "test" "[0-9]+" "Non-matching pattern"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_not_matches fails when pattern matches
kt_test_start "kt_assert_not_matches fails when pattern matches"
if ! kt_assert_quiet kt_assert_not_matches "test123" "[0-9]+" "Matching pattern"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_matches with word boundary pattern
kt_test_start "kt_assert_matches with word boundary pattern"
# a POSIX ERE word boundary: GNU's backslash-b is an extension (BSD and musl
# regex lack it; launch L2.1)
if kt_assert_matches "the word" "(^|[^[:alnum:]_])word([^[:alnum:]_]|$)" "Word boundary"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_matches with alternation pattern
kt_test_start "kt_assert_matches with alternation pattern"
if kt_assert_matches "cat" "cat|dog" "Alternation"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi
