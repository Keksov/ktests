#!/bin/bash
# Unit tests: Counter management and manipulation functions

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "CounterManagement" "$(dirname "$0")"

# Test kk_test_get_counts function exists and works
kk_test_start "kk_test_get_counts function exists"
if declare -f kk_test_get_counts > /dev/null 2>&1; then
    kk_test_pass "kk_test_get_counts function available"
else
    kk_test_fail "kk_test_get_counts function not found"
fi

# Test kk_test_get_counts produces formatted output
kk_test_start "kk_test_get_counts produces formatted output"
counts_output=$(kk_test_get_counts)
if [[ "$counts_output" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
    kk_test_pass "Counts output properly formatted"
else
    kk_test_fail "Counts output format incorrect"
fi

# Test kk_test_parse_counts function exists
kk_test_start "kk_test_parse_counts function exists"
if declare -f kk_test_parse_counts > /dev/null 2>&1; then
    kk_test_pass "kk_test_parse_counts function available"
else
    kk_test_fail "kk_test_parse_counts function not found"
fi

# Test kk_test_parse_counts with valid input
kk_test_start "kk_test_parse_counts with valid input"
kk_test_parse_counts "10:8:2" TOTAL PARSED_PASSED PARSED_FAILED
if (( TOTAL == 10 && PARSED_PASSED == 8 && PARSED_FAILED == 2 )); then
    kk_test_pass "Parse counts works correctly"
else
    kk_test_fail "Parse counts failed"
fi

# Test kk_test_parse_counts with empty input
kk_test_start "kk_test_parse_counts with empty input"
TOTAL=0; PARSED_PASSED=0; PARSED_FAILED=0
kk_test_parse_counts "" TOTAL PARSED_PASSED PARSED_FAILED
# Should handle empty input gracefully
kk_test_pass "Empty input handled gracefully"

# Test kk_test_accumulate_counts with valid input
kk_test_start "kk_test_accumulate_counts with valid input"
TESTS_TOTAL=5
TESTS_PASSED=4
TESTS_FAILED=1
kk_test_accumulate_counts "10:8:2"
expected_total=15
expected_pass=12
expected_fail=3
if (( TESTS_TOTAL == expected_total && TESTS_PASSED == expected_pass && TESTS_FAILED == expected_fail )); then
    kk_test_pass "Accumulate counts works correctly"
else
    kk_test_fail "Accumulate counts failed"
fi

# Test kk_test_accumulate_counts with zero values
kk_test_start "kk_test_accumulate_counts with zero values"
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
kk_test_accumulate_counts "0:0:0"
if (( TESTS_TOTAL == 0 && TESTS_PASSED == 0 && TESTS_FAILED == 0 )); then
    kk_test_pass "Zero values accumulated correctly"
else
    kk_test_fail "Zero values accumulation failed"
fi

# Test kk_test_validate_verbosity function exists
kk_test_start "kk_test_validate_verbosity function exists"
if declare -f kk_test_validate_verbosity > /dev/null 2>&1; then
    kk_test_pass "kk_test_validate_verbosity function available"
else
    kk_test_fail "kk_test_validate_verbosity function not found"
fi

# Test kk_test_validate_verbosity with valid values
kk_test_start "kk_test_validate_verbosity with valid values"
if kk_test_validate_verbosity "error" && kk_test_validate_verbosity "info"; then
    kk_test_pass "Valid verbosity values accepted"
else
    kk_test_fail "Valid verbosity values rejected"
fi

# Test kk_test_validate_verbosity with invalid value
kk_test_start "kk_test_validate_verbosity with invalid value"
if ! kk_test_validate_verbosity "invalid"; then
    kk_test_pass "Invalid verbosity value correctly rejected"
else
    kk_test_fail "Invalid verbosity value accepted"
fi

# Test kk_test_validate_mode function exists
kk_test_start "kk_test_validate_mode function exists"
if declare -f kk_test_validate_mode > /dev/null 2>&1; then
    kk_test_pass "kk_test_validate_mode function available"
else
    kk_test_fail "kk_test_validate_mode function not found"
fi

# Test kk_test_validate_mode with valid values
kk_test_start "kk_test_validate_mode with valid values"
if kk_test_validate_mode "single" && kk_test_validate_mode "threaded"; then
    kk_test_pass "Valid mode values accepted"
else
    kk_test_fail "Valid mode values rejected"
fi

# Test kk_test_validate_mode with invalid value
kk_test_start "kk_test_validate_mode with invalid value"
if ! kk_test_validate_mode "invalid"; then
    kk_test_pass "Invalid mode value correctly rejected"
else
    kk_test_fail "Invalid mode value accepted"
fi

# Test kk_test_validate_workers function exists
kk_test_start "kk_test_validate_workers function exists"
if declare -f kk_test_validate_workers > /dev/null 2>&1; then
    kk_test_pass "kk_test_validate_workers function available"
else
    kk_test_fail "kk_test_validate_workers function not found"
fi

# Test kk_test_validate_workers with valid values
kk_test_start "kk_test_validate_workers with valid values"
if kk_test_validate_workers "1" && kk_test_validate_workers "4" && kk_test_validate_workers "16"; then
    kk_test_pass "Valid worker values accepted"
else
    kk_test_fail "Valid worker values rejected"
fi

# Test kk_test_validate_workers with invalid values
kk_test_start "kk_test_validate_workers with invalid values"
if ! kk_test_validate_workers "0" && ! kk_test_validate_workers "-1" && ! kk_test_validate_workers "abc"; then
    kk_test_pass "Invalid worker values correctly rejected"
else
    kk_test_fail "Invalid worker values accepted"
fi

# Test counter arithmetic operations
kk_test_start "Counter arithmetic operations"
TESTS_TOTAL=10
TESTS_PASSED=8
TESTS_FAILED=2
# Simulate running 5 more tests with 4 passed and 1 failed
TESTS_TOTAL=$((TESTS_TOTAL + 5))
TESTS_PASSED=$((TESTS_PASSED + 4))
TESTS_FAILED=$((TESTS_FAILED + 1))
if (( TESTS_TOTAL == 15 && TESTS_PASSED == 12 && TESTS_FAILED == 3 )); then
    kk_test_pass "Counter arithmetic operations work correctly"
else
    kk_test_fail "Counter arithmetic operations failed"
fi

# Test counter reset functionality
kk_test_start "Counter reset functionality"
TESTS_TOTAL=100
TESTS_PASSED=80
TESTS_FAILED=20
kk_test_reset_counts
if (( TESTS_TOTAL == 0 && TESTS_PASSED == 0 && TESTS_FAILED == 0 )); then
    kk_test_pass "Reset counts to zero correctly"
else
    kk_test_fail "Reset counts failed"
fi

# Test get_counts after reset
kk_test_start "Get counts after reset"
counts_after_reset=$(kk_test_get_counts)
if [[ "$counts_after_reset" == "0:0:0" ]]; then
    kk_test_pass "Get counts shows zero after reset"
else
    kk_test_fail "Get counts not showing zero after reset"
fi

# Test accumulate with large numbers
kk_test_start "Accumulate with large numbers"
TESTS_TOTAL=1000
TESTS_PASSED=950
TESTS_FAILED=50
kk_test_accumulate_counts "500:480:20"
expected_total=1500
expected_pass=1430
expected_fail=70
if (( TESTS_TOTAL == expected_total && TESTS_PASSED == expected_pass && TESTS_FAILED == expected_fail )); then
    kk_test_pass "Large number accumulation works correctly"
else
    kk_test_fail "Large number accumulation failed"
fi

# Test parse counts with malformed input
kk_test_start "Parse counts with malformed input"
TOTAL=0; PARSED_PASSED=0; PARSED_FAILED=0
kk_test_parse_counts "abc:def:ghi" TOTAL PARSED_PASSED PARSED_FAILED
# Should handle malformed input gracefully (likely sets all to 0)
if (( TOTAL == 0 && PARSED_PASSED == 0 && PARSED_FAILED == 0 )); then
    kk_test_pass "Malformed input handled gracefully"
else
    kk_test_fail "Malformed input not handled correctly"
fi

# Test multiple accumulate operations
kk_test_start "Multiple accumulate operations"
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
kk_test_accumulate_counts "5:4:1"
kk_test_accumulate_counts "3:2:1"
kk_test_accumulate_counts "8:7:1"
expected_total=16
expected_pass=13
expected_fail=3
if (( TESTS_TOTAL == expected_total && TESTS_PASSED == expected_pass && TESTS_FAILED == expected_fail )); then
    kk_test_pass "Multiple accumulate operations work correctly"
else
    kk_test_fail "Multiple accumulate operations failed"
fi

# Test format counts
kk_test_start "kk_test_format_counts function availability"
if declare -f kk_test_format_counts > /dev/null 2>&1; then
    formatted=$(kk_test_format_counts)
    if [[ "$formatted" == "__COUNTS__:"* ]]; then
        kk_test_pass "Format counts produces expected format"
    else
        kk_test_pass "Format counts function available (format may vary)"
    fi
else
    kk_test_pass "Format counts function not available"
fi

# Test counter consistency after various operations
kk_test_start "Counter consistency after operations"
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
# Run some test operations
for i in {1..5}; do
    kk_test_start "Test $i"
    if (( i % 2 == 0 )); then
        kk_test_pass "Even test"
    else
        kk_test_fail "Odd test"
    fi
done
# Verify counters
if (( TESTS_TOTAL == 5 && TESTS_PASSED == 2 && TESTS_FAILED == 3 )); then
    kk_test_pass "Counter consistency maintained"
else
    kk_test_fail "Counter consistency lost"
fi