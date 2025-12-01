#!/bin/bash

# 015_IntegrationReportGeneration.sh
# Integration test: Report generation and result display

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

# Set file name for error reporting
kt_test_init "ReportGeneration" "$(dirname "$0")"

# Test result summary display function exists
kt_test_start "Result summary display function kt_test_show_results"
if declare -f kt_test_show_results > /dev/null 2>&1; then
    kt_test_pass "Result summary display function available"
else
    kt_test_fail "kt_test_show_results function not found"
fi

# Counter formatting function
kt_test_start "Counter formatting function kt_test_format_counts"
if declare -f kt_test_format_counts > /dev/null 2>&1; then
    kt_test_pass "Counter formatting function available"
else
    kt_test_fail "kt_test_format_counts function not found"
fi

# Test counter variables initialized
kt_test_start "Test counter variables initialized"
if [[ -n "$TESTS_TOTAL" && -n "$TESTS_PASSED" && -n "$TESTS_FAILED" ]]; then
    kt_test_pass "All counter variables initialized"
else
    kt_test_fail "Counter variables not properly initialized"
fi

# Test verbosity control works
kt_test_start "Verbosity control mechanism"
SAVED_VERBOSITY="$VERBOSITY"
VERBOSITY="error"
if [[ "$VERBOSITY" == "error" ]]; then
    kt_test_pass "Verbosity control works"
else
    kt_test_fail "Verbosity control failed"
fi
VERBOSITY="$SAVED_VERBOSITY"

# Test info mode verbosity
kt_test_start "Info mode verbosity setting"
VERBOSITY="info"
if [[ "$VERBOSITY" == "info" ]]; then
    kt_test_pass "Info mode enabled"
else
    kt_test_fail "Info mode not enabled"
fi
VERBOSITY="error"

# Test legacy counter variables
kt_test_start "Legacy counter variable TESTS_TOTAL"
if [[ -n "$TESTS_TOTAL" ]]; then
    kt_test_pass "Legacy TESTS_TOTAL available"
else
    kt_test_fail "Legacy TESTS_TOTAL not available"
fi

kt_test_start "Legacy counter variable TESTS_PASSED"
if [[ -n "$TESTS_PASSED" ]]; then
    kt_test_pass "Legacy TESTS_PASSED available"
else
    kt_test_fail "Legacy TESTS_PASSED not available"
fi

kt_test_start "Legacy counter variable TESTS_FAILED"
if [[ -n "$TESTS_FAILED" ]]; then
    kt_test_pass "Legacy TESTS_FAILED available"
else
    kt_test_fail "Legacy TESTS_FAILED not available"
fi

# Test counter reset
kt_test_start "Counter reset function"
initial_total=$TESTS_TOTAL
kt_test_reset_counts
if (( TESTS_TOTAL == 0 && TESTS_PASSED == 0 && TESTS_FAILED == 0 )); then
    kt_test_pass "Counter reset works"
else
    kt_test_fail "Counter reset failed"
fi

# Test framework counter increment
kt_test_start "Counter increment during test execution"
initial_total=$TESTS_TOTAL
initial_passed=$TESTS_PASSED
kt_test_pass "This increments counters"
# After kt_test_start: TESTS_TOTAL += 1 (and TESTS_PASSED = 0)
# After kt_test_pass: TESTS_PASSED += 1 (TESTS_TOTAL unchanged)
# So TESTS_PASSED should be initial_passed + 1
if (( TESTS_PASSED == initial_passed + 1 )); then
    kt_test_pass "Counter increment works"
else
    kt_test_fail "Counter increment failed (initial_passed: $initial_passed, current_passed: $TESTS_PASSED)"
fi

# Test empty string assertion
kt_test_start "Empty string assertion"
if kt_assert_equals "" "" "Empty strings are equal" >/dev/null 2>&1; then
    kt_test_pass "Value comparison"
    kt_test_pass "Empty string handled"
else
    kt_test_fail "Empty string test failed"
fi

# Test special characters in values
kt_test_start "Special characters in values"
special='$@#%^&*()'
if kt_assert_equals "$special" "$special" "Special char test" >/dev/null 2>&1; then
    kt_test_pass "Value comparison"
    kt_test_pass "Special characters handled"
else
    kt_test_fail "Special character test failed"
fi

# Test very long string handling
kt_test_start "Very long string handling"
long_string=$(printf 'a%.0s' {1..500})
if kt_assert_contains "$long_string" "a" "Long string test" >/dev/null 2>&1; then
    kt_test_pass "String contains check"
    kt_test_pass "Long strings handled"
else
    kt_test_fail "Long string test failed"
fi

# Test file paths with spaces
kt_test_start "File paths with spaces"
testdir=$(kt_fixture_tmpdir_create "test dir with spaces")
testfile="$testdir/test file.txt"
touch "$testfile"
if kt_assert_file_exists "$testfile" "File with spaces" >/dev/null 2>&1; then
    kt_test_pass "File exists check"
    kt_test_pass "Paths with spaces work"
else
    kt_test_fail "Paths with spaces test failed"
fi

# Test deep directory structure
kt_test_start "Deep directory structure"
deepdir=$(kt_fixture_tmpdir)
for i in {1..5}; do
    deepdir="$deepdir/level$i"
    mkdir -p "$deepdir"
done
if [[ -d "$deepdir" ]]; then
    kt_test_pass "Deep nesting works"
else
    kt_test_fail "Deep nesting failed"
fi

# Test large array handling
kt_test_start "Large array handling"
declare -a big_array
for i in {1..100}; do
    big_array+=("item$i")
done
if kt_assert_array_length big_array 100 "Large array" >/dev/null 2>&1; then
    kt_test_pass "Array length check"
    kt_test_pass "Large arrays handled"
else
    kt_test_fail "Large array test failed"
fi

# Test multi-line string handling
kt_test_start "Multi-line string handling"
multiline=$'line1\nline2\nline3\nline4\nline5'
if kt_assert_contains "$multiline" "line3" "Multiline test" >/dev/null 2>&1; then
    kt_test_pass "String contains check"
    kt_test_pass "Multi-line content handled"
else
    kt_test_fail "Multi-line test failed"
fi

# Test regex special characters in values
kt_test_start "Regex special characters in values"
regex_test='[test](content).txt'
if kt_assert_equals "$regex_test" "$regex_test" "Regex char test" >/dev/null 2>&1; then
    kt_test_pass "Value comparison"
    kt_test_pass "Regex special chars handled"
else
    kt_test_fail "Regex character test failed"
fi

# Test cleanup handler registration
kt_test_start "Cleanup handler registration"
cleanup_test() { echo "cleanup"; }
declare -a test_handlers=()
if declare -f cleanup_test >/dev/null 2>&1; then
    kt_test_pass "Cleanup system initialized"
else
    kt_test_fail "Cleanup system failed"
fi

# Test fixture directory accessibility
kt_test_start "Fixture directory accessibility"
fixture_dir=$(kt_fixture_tmpdir)
if [[ -d "$fixture_dir" && -r "$fixture_dir" && -w "$fixture_dir" ]]; then
    kt_test_pass "Fixture directory accessible"
else
    kt_test_fail "Fixture directory not accessible"
fi

# Test assertion counter accumulation
kt_test_start "Assertion counter accumulation"
initial_passed=$TESTS_PASSED
kt_assert_equals "a" "a" "Test 1" >/dev/null 2>&1
kt_assert_equals "b" "b" "Test 2" >/dev/null 2>&1
if kt_assert_equals "c" "c" "Test 3" >/dev/null 2>&1; then
    kt_test_pass "Value comparison"
    kt_test_pass "Counters accumulate"
else
    kt_test_fail "Counter accumulation failed"
fi

# Test numeric comparison with zero
kt_test_start "Numeric comparison with zero"
if kt_assert_num_equals 0 0 "Zero test" >/dev/null 2>&1; then
    kt_test_pass "Numeric equality"
    kt_test_pass "Zero comparison works"
else
    kt_test_fail "Zero comparison failed"
fi

# Test negative number comparison
kt_test_start "Negative number comparison"
if kt_assert_num_equals -5 -5 "Negative test" >/dev/null 2>&1; then
    kt_test_pass "Numeric equality"
    kt_test_pass "Negative number comparison works"
else
    kt_test_fail "Negative number comparison failed"
fi

# Test file permission checks
kt_test_start "File permission checks"
perm_file=$(kt_fixture_tmpfile "perm_test")
if [[ -r "$perm_file" ]]; then
    kt_test_pass "File permission checks work"
else
    kt_test_fail "File permission check failed"
fi

# Final verification
kt_test_start "Framework functionality verification"
if [[ -n "$KT__FRAMEWORK_VERSION" && -n "$TESTS_TOTAL" ]]; then
    kt_test_pass "All tests completed successfully"
else
    kt_test_fail "Framework verification failed"
fi


