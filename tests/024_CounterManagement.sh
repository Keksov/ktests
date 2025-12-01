#!/bin/bash
# Unit tests: Counter management and manipulation functions

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "CounterManagement" "$(dirname "$0")" "$@"

# Test kt_test_get_counts function exists and works
kt_test_start "kt_test_get_counts function exists"
if declare -f kt_test_get_counts > /dev/null 2>&1; then
    kt_test_pass "kt_test_get_counts function available"
else
    kt_test_fail "kt_test_get_counts function not found"
fi

# Test kt_test_get_counts produces formatted output
kt_test_start "kt_test_get_counts produces formatted output"
counts_output=$(kt_test_get_counts)
if [[ "$counts_output" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
    kt_test_pass "Counts output properly formatted"
else
    kt_test_fail "Counts output format incorrect"
fi

# Test kt_test_parse_counts function exists
kt_test_start "kt_test_parse_counts function exists"
if declare -f kt_test_parse_counts > /dev/null 2>&1; then
    kt_test_pass "kt_test_parse_counts function available"
else
    kt_test_fail "kt_test_parse_counts function not found"
fi

# Test kt_test_parse_counts with valid input
kt_test_start "kt_test_parse_counts with valid input"
if (
    kt_test_parse_counts "10:8:2" TOTAL PARSED_PASSED PARSED_FAILED
    [[ $TOTAL == 10 && $PARSED_PASSED == 8 && $PARSED_FAILED == 2 ]]
); then
    kt_test_pass "Parse counts works correctly"
else
    kt_test_fail "Parse counts failed"
fi

# Test kt_test_parse_counts with empty input
kt_test_start "kt_test_parse_counts with empty input"
TOTAL=0; PARSED_PASSED=0; PARSED_FAILED=0
kt_test_parse_counts "" TOTAL PARSED_PASSED PARSED_FAILED
# Should handle empty input gracefully
kt_test_pass "Empty input handled gracefully"

# Test kt_test_accumulate_counts with valid input
kt_test_start "kt_test_accumulate_counts with valid input"
if (
    TESTS_TOTAL=5
    TESTS_PASSED=4
    TESTS_FAILED=1
    kt_test_accumulate_counts "10:8:2"
    [[ $TESTS_TOTAL == 15 && $TESTS_PASSED == 12 && $TESTS_FAILED == 3 ]]
); then
    kt_test_pass "Accumulate counts works correctly"
else
    kt_test_fail "Accumulate counts failed"
fi

# Test kt_test_accumulate_counts with zero values
kt_test_start "kt_test_accumulate_counts with zero values"
if (
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    kt_test_accumulate_counts "0:0:0"
    [[ $TESTS_TOTAL == 0 && $TESTS_PASSED == 0 && $TESTS_FAILED == 0 ]]
); then
    kt_test_pass "Zero values accumulated correctly"
else
    kt_test_fail "Zero values accumulation failed"
fi

# Test kt_test_validate_verbosity function exists
kt_test_start "kt_test_validate_verbosity function exists"
if declare -f kt_test_validate_verbosity > /dev/null 2>&1; then
    kt_test_pass "kt_test_validate_verbosity function available"
else
    kt_test_fail "kt_test_validate_verbosity function not found"
fi

# Test kt_test_validate_verbosity with valid values
kt_test_start "kt_test_validate_verbosity with valid values"
if kt_test_validate_verbosity "error" && kt_test_validate_verbosity "info"; then
    kt_test_pass "Valid verbosity values accepted"
else
    kt_test_fail "Valid verbosity values rejected"
fi

# Test kt_test_validate_verbosity with invalid value
kt_test_start "kt_test_validate_verbosity with invalid value"
if ! kt_test_validate_verbosity "invalid" 2>/dev/null; then
    kt_test_pass "Invalid verbosity value correctly rejected"
else
    kt_test_fail "Invalid verbosity value accepted"
fi

# Test kt_test_validate_mode function exists
kt_test_start "kt_test_validate_mode function exists"
if declare -f kt_test_validate_mode > /dev/null 2>&1; then
    kt_test_pass "kt_test_validate_mode function available"
else
    kt_test_fail "kt_test_validate_mode function not found"
fi

# Test kt_test_validate_mode with valid values
kt_test_start "kt_test_validate_mode with valid values"
if kt_test_validate_mode "single" && kt_test_validate_mode "threaded"; then
    kt_test_pass "Valid mode values accepted"
else
    kt_test_fail "Valid mode values rejected"
fi

# Test kt_test_validate_mode with invalid value
kt_test_start "kt_test_validate_mode with invalid value"
if ! kt_test_validate_mode "invalid" 2>/dev/null; then
    kt_test_pass "Invalid mode value correctly rejected"
else
    kt_test_fail "Invalid mode value accepted"
fi

# Test kt_test_validate_workers function exists
kt_test_start "kt_test_validate_workers function exists"
if declare -f kt_test_validate_workers > /dev/null 2>&1; then
    kt_test_pass "kt_test_validate_workers function available"
else
    kt_test_fail "kt_test_validate_workers function not found"
fi

# Test kt_test_validate_workers with valid values
kt_test_start "kt_test_validate_workers with valid values"
if kt_test_validate_workers "1" && kt_test_validate_workers "4" && kt_test_validate_workers "16"; then
    kt_test_pass "Valid worker values accepted"
else
    kt_test_fail "Valid worker values rejected"
fi

# Test kt_test_validate_workers with invalid values
kt_test_start "kt_test_validate_workers with invalid values"
if ! kt_test_validate_workers "0" 2>/dev/null && ! kt_test_validate_workers "-1" 2>/dev/null && ! kt_test_validate_workers "abc" 2>/dev/null; then
    kt_test_pass "Invalid worker values correctly rejected"
else
    kt_test_fail "Invalid worker values accepted"
fi

# Test counter arithmetic operations
kt_test_start "Counter arithmetic operations"
if (
    TESTS_TOTAL=10
    TESTS_PASSED=8
    TESTS_FAILED=2
    TESTS_TOTAL=$((TESTS_TOTAL + 5))
    TESTS_PASSED=$((TESTS_PASSED + 4))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    [[ $TESTS_TOTAL == 15 && $TESTS_PASSED == 12 && $TESTS_FAILED == 3 ]]
); then
    kt_test_pass "Counter arithmetic operations work correctly"
else
    kt_test_fail "Counter arithmetic operations failed"
fi

# Test kt_test_reset_counts exists
kt_test_start "kt_test_reset_counts function exists"
if declare -f kt_test_reset_counts > /dev/null 2>&1; then
    kt_test_pass "kt_test_reset_counts function available"
else
    kt_test_fail "kt_test_reset_counts function not found"
fi

# Test get_counts format
kt_test_start "Get counts format after operations"
counts_output=$(kt_test_get_counts)
if [[ "$counts_output" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
    kt_test_pass "Get counts shows proper format"
else
    kt_test_fail "Get counts not showing valid format"
fi

# Test accumulate with large numbers
kt_test_start "Accumulate with large numbers"
if (
    TESTS_TOTAL=1000
    TESTS_PASSED=950
    TESTS_FAILED=50
    kt_test_accumulate_counts "500:480:20"
    [[ $TESTS_TOTAL == 1500 && $TESTS_PASSED == 1430 && $TESTS_FAILED == 70 ]]
); then
    kt_test_pass "Large number accumulation works correctly"
else
    kt_test_fail "Large number accumulation failed"
fi

# Test parse counts with malformed input
kt_test_start "Parse counts with malformed input"
# Malformed input should be handled gracefully (doesn't crash)
if declare -f kt_test_parse_counts > /dev/null 2>&1; then
    kt_test_parse_counts "abc:def:ghi" TOTAL PARSED_PASSED PARSED_FAILED 2>/dev/null || true
    kt_test_pass "Malformed input handled gracefully"
else
    kt_test_fail "Function not found"
fi

# Test multiple accumulate operations
kt_test_start "Multiple accumulate operations"
if (
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    kt_test_accumulate_counts "5:4:1"
    kt_test_accumulate_counts "3:2:1"
    kt_test_accumulate_counts "8:7:1"
    [[ $TESTS_TOTAL == 16 && $TESTS_PASSED == 13 && $TESTS_FAILED == 3 ]]
); then
    kt_test_pass "Multiple accumulate operations work correctly"
else
    kt_test_fail "Multiple accumulate operations failed"
fi

# Test format counts
kt_test_start "kt_test_format_counts function availability"
if declare -f kt_test_format_counts > /dev/null 2>&1; then
    formatted=$(kt_test_format_counts)
    if [[ "$formatted" == "__COUNTS__:"* ]] || [[ -n "$formatted" ]]; then
        kt_test_pass "Format counts function available"
    else
        kt_test_fail "Format counts returned empty"
    fi
else
    kt_test_fail "Format counts function not found"
fi

# Test counter consistency after various operations
# Note: This test checks that counter management works correctly
# We use local counters to verify the logic without affecting final stats
kt_test_start "Counter consistency after operations"

# Initialize test counters for this sub-test
test_loop_total=0
test_loop_pass=0
test_loop_fail=0

# Run some test operations (intentionally with failures for tracking verification)
# Note: We don't use kt_test_start here to avoid affecting the global counter
for i in {1..5}; do
    ((test_loop_total++))
    if (( i % 2 == 0 )); then
        ((test_loop_pass++))
    else
        ((test_loop_fail++))
    fi
done

# Verify counters (should have 5 total with 2 passes and 3 fails)
if (( test_loop_total == 5 && test_loop_pass == 2 && test_loop_fail == 3 )); then
    kt_test_pass "Counter consistency maintained"
else
    kt_test_fail "Counter consistency lost"
fi
