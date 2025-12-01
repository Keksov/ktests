#!/bin/bash
# Integration tests: Regression scenarios and edge cases

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "RegressionScenarios" "$(dirname "$0")"

# Test backward compatibility
kt_test_start "Backward compatibility - test_start function"
if declare -f test_start >/dev/null 2>&1; then
    kt_test_pass "Legacy test_start alias exists"
else
    kt_test_fail "Legacy test_start alias missing"
fi

kt_test_start "Backward compatibility - test_pass function"
if declare -f test_pass >/dev/null 2>&1; then
    kt_test_pass "Legacy test_pass alias exists"
else
    kt_test_fail "Legacy test_pass alias missing"
fi

kt_test_start "Backward compatibility - test_fail function"
if declare -f test_fail >/dev/null 2>&1; then
    kt_test_pass "Legacy test_fail alias exists"
else
    kt_test_fail "Legacy test_fail alias missing"
fi

# Test framework state isolation
kt_test_start "Framework state isolation"
state_before=$TESTS_TOTAL
kt_test_reset_counts
state_after=$TESTS_TOTAL
if (( state_after == 0 )); then
    kt_test_pass "State isolation works"
else
    kt_test_fail "State not properly isolated"
fi

# Restore counts
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0


