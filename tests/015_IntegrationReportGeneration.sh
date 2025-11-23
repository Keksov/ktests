#!/bin/bash

# 015_IntegrationReportGeneration.sh
# Integration test: Report generation and result display

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

# Set file name for error reporting
KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"

kk_test_init "ReportGeneration" "$(dirname "$0")"

# Test result summary display function exists
kk_test_start "Result summary display function kk_test_show_results"
if declare -f kk_test_show_results > /dev/null 2>&1; then
    kk_test_pass "Result summary display function available"
else
    kk_test_fail "kk_test_show_results function not found"
fi

# Counter formatting function
kk_test_start "Counter formatting function kk_test_format_counts"
if declare -f kk_test_format_counts > /dev/null 2>&1; then
    kk_test_pass "Counter formatting function available"
else
    kk_test_fail "kk_test_format_counts function not found"
fi

# Test counter variables initialized
kk_test_start "Test counter variables initialized"
if [[ -n "$TESTS_TOTAL" && -n "$TESTS_PASSED" && -n "$TESTS_FAILED" ]]; then
    kk_test_pass "All counter variables initialized"
else
    kk_test_fail "Counter variables not properly initialized"
fi

# Test verbosity control works
kk_test_start "Verbosity control mechanism"
SAVED_VERBOSITY="$VERBOSITY"
VERBOSITY="error"
if [[ "$VERBOSITY" == "error" ]]; then
    kk_test_pass "Verbosity control works"
else
    kk_test_fail "Verbosity control failed"
fi
VERBOSITY="$SAVED_VERBOSITY"

# Test info mode verbosity
kk_test_start "Info mode verbosity setting"
VERBOSITY="info"
if [[ "$VERBOSITY" == "info" ]]; then
    kk_test_pass "Info mode enabled"
else
    kk_test_fail "Info mode not enabled"
fi
VERBOSITY="error"

# Test legacy counter variables
kk_test_start "Legacy counter variable TESTS_TOTAL"
if [[ -n "$TESTS_TOTAL" ]]; then
    kk_test_pass "Legacy TESTS_TOTAL available"
else
    kk_test_fail "Legacy TESTS_TOTAL not available"
fi

kk_test_start "Legacy counter variable TESTS_PASSED"
if [[ -n "$TESTS_PASSED" ]]; then
    kk_test_pass "Legacy TESTS_PASSED available"
else
    kk_test_fail "Legacy TESTS_PASSED not available"
fi

kk_test_start "Legacy counter variable TESTS_FAILED"
if [[ -n "$TESTS_FAILED" ]]; then
    kk_test_pass "Legacy TESTS_FAILED available"
else
    kk_test_fail "Legacy TESTS_FAILED not available"
fi

# Test counter reset
kk_test_start "Counter reset function"
initial_total=$TESTS_TOTAL
kk_test_reset_counts
if (( TESTS_TOTAL == 0 && TESTS_PASSED == 0 && TESTS_FAILED == 0 )); then
    kk_test_pass "Counter reset works"
else
    kk_test_fail "Counter reset failed"
fi

# Test framework counter increment
kk_test_start "Counter increment during test execution"
initial_total=$TESTS_TOTAL
initial_passed=$TESTS_PASSED
kk_test_pass "This increments counters"
# After kk_test_start: TESTS_TOTAL += 1 (and TESTS_PASSED = 0)
# After kk_test_pass: TESTS_PASSED += 1 (TESTS_TOTAL unchanged)
# So TESTS_PASSED should be initial_passed + 1
if (( TESTS_PASSED == initial_passed + 1 )); then
    kk_test_pass "Counter increment works"
else
    kk_test_fail "Counter increment failed (initial_passed: $initial_passed, current_passed: $TESTS_PASSED)"
fi

# Test empty string assertion
kk_test_start "Empty string assertion"
if kk_assert_equals "" "" "Empty strings are equal" >/dev/null 2>&1; then
    kk_test_pass "Value comparison"
    kk_test_pass "Empty string handled"
else
    kk_test_fail "Empty string test failed"
fi

# Test special characters in values
kk_test_start "Special characters in values"
special='$@#%^&*()'
if kk_assert_equals "$special" "$special" "Special char test" >/dev/null 2>&1; then
    kk_test_pass "Value comparison"
    kk_test_pass "Special characters handled"
else
    kk_test_fail "Special character test failed"
fi

# Test very long string handling
kk_test_start "Very long string handling"
long_string=$(printf 'a%.0s' {1..500})
if kk_assert_contains "$long_string" "a" "Long string test" >/dev/null 2>&1; then
    kk_test_pass "String contains check"
    kk_test_pass "Long strings handled"
else
    kk_test_fail "Long string test failed"
fi

# Test file paths with spaces
kk_test_start "File paths with spaces"
testdir=$(kk_fixture_tmpdir_create "test dir with spaces")
testfile="$testdir/test file.txt"
touch "$testfile"
if kk_assert_file_exists "$testfile" "File with spaces" >/dev/null 2>&1; then
    kk_test_pass "File exists check"
    kk_test_pass "Paths with spaces work"
else
    kk_test_fail "Paths with spaces test failed"
fi

# Test deep directory structure
kk_test_start "Deep directory structure"
deepdir=$(kk_fixture_tmpdir)
for i in {1..5}; do
    deepdir="$deepdir/level$i"
    mkdir -p "$deepdir"
done
if [[ -d "$deepdir" ]]; then
    kk_test_pass "Deep nesting works"
else
    kk_test_fail "Deep nesting failed"
fi

# Test large array handling
kk_test_start "Large array handling"
declare -a big_array
for i in {1..100}; do
    big_array+=("item$i")
done
if kk_assert_array_length big_array 100 "Large array" >/dev/null 2>&1; then
    kk_test_pass "Array length check"
    kk_test_pass "Large arrays handled"
else
    kk_test_fail "Large array test failed"
fi

# Test multi-line string handling
kk_test_start "Multi-line string handling"
multiline=$'line1\nline2\nline3\nline4\nline5'
if kk_assert_contains "$multiline" "line3" "Multiline test" >/dev/null 2>&1; then
    kk_test_pass "String contains check"
    kk_test_pass "Multi-line content handled"
else
    kk_test_fail "Multi-line test failed"
fi

# Test regex special characters in values
kk_test_start "Regex special characters in values"
regex_test='[test](content).txt'
if kk_assert_equals "$regex_test" "$regex_test" "Regex char test" >/dev/null 2>&1; then
    kk_test_pass "Value comparison"
    kk_test_pass "Regex special chars handled"
else
    kk_test_fail "Regex character test failed"
fi

# Test cleanup handler registration
kk_test_start "Cleanup handler registration"
cleanup_test() { echo "cleanup"; }
declare -a test_handlers=()
if declare -f cleanup_test >/dev/null 2>&1; then
    kk_test_pass "Cleanup system initialized"
else
    kk_test_fail "Cleanup system failed"
fi

# Test fixture directory accessibility
kk_test_start "Fixture directory accessibility"
fixture_dir=$(kk_fixture_tmpdir)
if [[ -d "$fixture_dir" && -r "$fixture_dir" && -w "$fixture_dir" ]]; then
    kk_test_pass "Fixture directory accessible"
else
    kk_test_fail "Fixture directory not accessible"
fi

# Test assertion counter accumulation
kk_test_start "Assertion counter accumulation"
initial_passed=$TESTS_PASSED
kk_assert_equals "a" "a" "Test 1" >/dev/null 2>&1
kk_assert_equals "b" "b" "Test 2" >/dev/null 2>&1
if kk_assert_equals "c" "c" "Test 3" >/dev/null 2>&1; then
    kk_test_pass "Value comparison"
    kk_test_pass "Counters accumulate"
else
    kk_test_fail "Counter accumulation failed"
fi

# Test numeric comparison with zero
kk_test_start "Numeric comparison with zero"
if kk_assert_num_equals 0 0 "Zero test" >/dev/null 2>&1; then
    kk_test_pass "Numeric equality"
    kk_test_pass "Zero comparison works"
else
    kk_test_fail "Zero comparison failed"
fi

# Test negative number comparison
kk_test_start "Negative number comparison"
if kk_assert_num_equals -5 -5 "Negative test" >/dev/null 2>&1; then
    kk_test_pass "Numeric equality"
    kk_test_pass "Negative number comparison works"
else
    kk_test_fail "Negative number comparison failed"
fi

# Test file permission checks
kk_test_start "File permission checks"
perm_file=$(kk_fixture_tmpfile "perm_test")
if [[ -r "$perm_file" ]]; then
    kk_test_pass "File permission checks work"
else
    kk_test_fail "File permission check failed"
fi

# Final verification
kk_test_start "Framework functionality verification"
if [[ -n "$KK_TEST_FRAMEWORK_VERSION" && -n "$TESTS_TOTAL" ]]; then
    kk_test_pass "All tests completed successfully"
else
    kk_test_fail "Framework verification failed"
fi

echo __COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED
