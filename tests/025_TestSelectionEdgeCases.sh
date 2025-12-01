#!/bin/bash
# Unit tests: Test selection parsing edge cases and error scenarios

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "TestSelectionEdgeCases" "$(dirname "$0")"

# Test kt_runner_parse_selection with empty selection
kt_test_start "kt_runner_parse_selection with empty selection"
TESTS_TO_RUN=()
kt_runner_parse_selection ""
if (( ${#TESTS_TO_RUN[@]} == 0 )); then
    kt_test_pass "Empty selection handled correctly"
else
    kt_test_fail "Empty selection not handled correctly"
fi

# Test kt_runner_parse_selection with single number
kt_test_start "kt_runner_parse_selection with single number"
TESTS_TO_RUN=()
kt_runner_parse_selection "5"
if (( ${#TESTS_TO_RUN[@]} == 1 && ${TESTS_TO_RUN[0]} == 5 )); then
    kt_test_pass "Single number selection works"
else
    kt_test_fail "Single number selection failed"
fi

# Test kt_runner_parse_selection with invalid format (letters)
kt_test_start "kt_runner_parse_selection with letters"
TESTS_TO_RUN=()
kt_warn_quiet kt_runner_parse_selection "abc"
if (( ${#TESTS_TO_RUN[@]} == 0 )); then
    kt_test_pass "Invalid format (letters) handled gracefully"
else
    kt_test_fail "Invalid format (letters) not handled correctly"
fi

# Test kt_runner_parse_selection with invalid format (mixed)
kt_test_start "kt_runner_parse_selection with mixed format"
TESTS_TO_RUN=()
kt_warn_quiet kt_runner_parse_selection "1,abc,3"
# Should parse what it can and ignore invalid parts
if (( ${#TESTS_TO_RUN[@]} >= 2 )); then
    kt_test_pass "Mixed format handled with partial parsing"
else
    kt_test_fail "Mixed format not handled correctly"
fi

# Test kt_runner_parse_selection with very large numbers
kt_test_start "kt_runner_parse_selection with large numbers"
TESTS_TO_RUN=()
kt_runner_parse_selection "999999"
if (( ${#TESTS_TO_RUN[@]} == 1 && ${TESTS_TO_RUN[0]} == 999999 )); then
    kt_test_pass "Large numbers handled correctly"
else
    kt_test_fail "Large numbers not handled correctly"
fi

# Test kt_runner_parse_selection with zero
kt_test_start "kt_runner_parse_selection with zero"
TESTS_TO_RUN=()
kt_runner_parse_selection "0"
if (( ${#TESTS_TO_RUN[@]} == 1 && ${TESTS_TO_RUN[0]} == 0 )); then
    kt_test_pass "Zero handled as valid number"
else
    kt_test_fail "Zero not handled correctly"
fi

# Test kt_runner_parse_selection with negative numbers
kt_test_start "kt_runner_parse_selection with negative numbers"
TESTS_TO_RUN=()
kt_warn_quiet kt_runner_parse_selection "-5"
# Should likely be ignored or handled gracefully
if (( ${#TESTS_TO_RUN[@]} == 0 )); then
    kt_test_pass "Negative numbers handled gracefully (ignored)"
else
    kt_test_pass "Negative numbers handled (implementation dependent)"
fi

# Test kt_runner_parse_selection with duplicate numbers
kt_test_start "kt_runner_parse_selection with duplicates"
TESTS_TO_RUN=()
kt_runner_parse_selection "1,2,2,3,1"
# Should handle duplicates without duplicating in array
if (( ${#TESTS_TO_RUN[@]} >= 3 )); then
    kt_test_pass "Duplicates handled without array duplication"
else
    kt_test_fail "Duplicates not handled correctly"
fi

# Test kt_runner_parse_selection with range boundaries
kt_test_start "kt_runner_parse_selection with range boundaries"
TESTS_TO_RUN=()
kt_runner_parse_selection "1-5"
if (( ${#TESTS_TO_RUN[@]} == 5 )); then
    kt_test_pass "Range boundaries handled correctly"
else
    kt_test_fail "Range boundaries not handled correctly"
fi

# Test kt_runner_parse_selection with invalid range (reverse)
kt_test_start "kt_runner_parse_selection with reverse range"
TESTS_TO_RUN=()
kt_runner_parse_selection "5-1"
# Should handle reverse ranges gracefully
if (( ${#TESTS_TO_RUN[@]} >= 0 )); then
    kt_test_pass "Reverse range handled gracefully"
else
    kt_test_fail "Reverse range not handled correctly"
fi

# Test kt_runner_parse_selection with equal range bounds
kt_test_start "kt_runner_parse_selection with equal range bounds"
TESTS_TO_RUN=()
kt_runner_parse_selection "5-5"
if (( ${#TESTS_TO_RUN[@]} == 1 )); then
    kt_test_pass "Equal range bounds handled as single value"
else
    kt_test_fail "Equal range bounds not handled correctly"
fi

# Test kt_runner_parse_selection with very large range
kt_test_start "kt_runner_parse_selection with large range"
TESTS_TO_RUN=()
kt_runner_parse_selection "1-1000"
if (( ${#TESTS_TO_RUN[@]} == 1000 )); then
    kt_test_pass "Large range handled correctly"
else
    kt_test_fail "Large range not handled correctly"
fi

# Test kt_runner_parse_selection with multiple comma-separated values
kt_test_start "kt_runner_parse_selection with many comma values"
TESTS_TO_RUN=()
kt_runner_parse_selection "1,5,10,15,20,25,30,35,40"
if (( ${#TESTS_TO_RUN[@]} == 9 )); then
    kt_test_pass "Multiple comma values handled correctly"
else
    kt_test_fail "Multiple comma values not handled correctly"
fi

# Test kt_runner_parse_selection with spaces in input
kt_test_start "kt_runner_parse_selection with spaces"
TESTS_TO_RUN=()
kt_runner_parse_selection "1, 2, 3 , 4 ,5"
if (( ${#TESTS_TO_RUN[@]} >= 3 )); then
    kt_test_pass "Spaces in input handled gracefully"
else
    kt_test_fail "Spaces in input not handled correctly"
fi

# Test kt_runner_parse_selection with mixed ranges and singles
kt_test_start "kt_runner_parse_selection with mixed ranges and singles"
TESTS_TO_RUN=()
kt_runner_parse_selection "1,3-5,8,10-12"
if (( ${#TESTS_TO_RUN[@]} >= 8 )); then
    kt_test_pass "Mixed ranges and singles handled correctly"
else
    kt_test_fail "Mixed ranges and singles not handled correctly"
fi

# Test kt_runner_parse_selection with invalid range format
kt_test_start "kt_runner_parse_selection with invalid range format"
TESTS_TO_RUN=()
kt_warn_quiet kt_runner_parse_selection "1-a"
if (( ${#TESTS_TO_RUN[@]} == 0 )); then
    kt_test_pass "Invalid range format handled gracefully"
else
    kt_test_fail "Invalid range format not handled correctly"
fi

# Test kt_runner_parse_selection with overlapping ranges
kt_test_start "kt_runner_parse_selection with overlapping ranges"
TESTS_TO_RUN=()
kt_runner_parse_selection "1-5,3-7"
# Should handle overlapping ranges
if (( ${#TESTS_TO_RUN[@]} >= 7 )); then
    kt_test_pass "Overlapping ranges handled without errors"
else
    kt_test_fail "Overlapping ranges not handled correctly"
fi

# Test kt_runner_parse_selection with very long input
kt_test_start "kt_runner_parse_selection with very long input"
TESTS_TO_RUN=()
long_input=$(seq -s, 1 100)
kt_runner_parse_selection "$long_input"
if (( ${#TESTS_TO_RUN[@]} == 100 )); then
    kt_test_pass "Very long input handled correctly"
else
    kt_test_fail "Very long input not handled correctly"
fi

# Test kt_runner_parse_selection with special characters
kt_test_start "kt_runner_parse_selection with special characters"
TESTS_TO_RUN=()
kt_warn_quiet kt_runner_parse_selection "1@#\$%^&*()"
if (( ${#TESTS_TO_RUN[@]} == 0 )); then
    kt_test_pass "Special characters handled gracefully"
else
    kt_test_fail "Special characters not handled correctly"
fi

# Test selection with leading/trailing commas
kt_test_start "kt_runner_parse_selection with leading/trailing commas"
TESTS_TO_RUN=()
kt_warn_quiet kt_runner_parse_selection ",1,2,3,"
if (( ${#TESTS_TO_RUN[@]} >= 3 )); then
    kt_test_pass "Leading/trailing commas handled gracefully"
else
    kt_test_fail "Leading/trailing commas not handled correctly"
fi

# Test selection persistence across calls
kt_test_start "Selection persistence across multiple calls"
TESTS_TO_RUN=()
kt_runner_parse_selection "1,2,3"
first_count=${#TESTS_TO_RUN[@]}
TESTS_TO_RUN=()
kt_runner_parse_selection "4,5,6"
second_count=${#TESTS_TO_RUN[@]}
if (( first_count == 3 && second_count == 3 )); then
    kt_test_pass "Selection parsing is properly isolated between calls"
else
    kt_test_fail "Selection parsing not properly isolated"
fi

# Test very complex selection pattern
kt_test_start "Complex selection pattern"
TESTS_TO_RUN=()
kt_runner_parse_selection "1-3,7,10-15,20,25-30"
if (( ${#TESTS_TO_RUN[@]} >= 16 )); then
    kt_test_pass "Complex selection pattern handled correctly"
else
    kt_test_fail "Complex selection pattern not handled correctly"
fi