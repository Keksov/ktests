#!/bin/bash
# Integration tests: Regression scenarios and edge cases

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "RegressionScenarios" "$(dirname "$0")"

# Test backward compatibility
kk_test_start "Backward compatibility - test_start function"
if declare -f test_start >/dev/null 2>&1; then
    kk_test_pass "Legacy test_start alias exists"
else
    kk_test_fail "Legacy test_start alias missing"
fi

kk_test_start "Backward compatibility - test_pass function"
if declare -f test_pass >/dev/null 2>&1; then
    kk_test_pass "Legacy test_pass alias exists"
else
    kk_test_fail "Legacy test_pass alias missing"
fi

kk_test_start "Backward compatibility - test_fail function"
if declare -f test_fail >/dev/null 2>&1; then
    kk_test_pass "Legacy test_fail alias exists"
else
    kk_test_fail "Legacy test_fail alias missing"
fi

# Test framework state isolation
kk_test_start "Framework state isolation"
state_before=$TESTS_TOTAL
kk_test_reset_counts
state_after=$TESTS_TOTAL
if (( state_after == 0 )); then
    kk_test_pass "State isolation works"
else
    kk_test_fail "State not properly isolated"
fi

# Restore counts
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
