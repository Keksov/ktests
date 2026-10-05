#!/bin/bash
# Integration tests: Regression scenarios and edge cases

# Only source if framework not already loaded
if [[ -z "$_KTEST_SOURCED" ]]; then
    source "$(dirname "$0")/../ktest_source.sh" || source "$KTEST_SOURCE_PATH" || exit 1
fi

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

# Test framework state isolation. The reset runs in a subshell: resetting THIS
# file's counters would hide every assertion before it from the runner
# (round 4, review R1).
kt_test_start "Framework state isolation"
_kt016_after="$(
    kt_test_reset_counts
    echo "$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
)"
if [[ "$_kt016_after" == "0:0:0" ]]; then
    kt_test_pass "State isolation works"
else
    kt_test_fail "State not properly isolated (after reset: $_kt016_after)"
fi
