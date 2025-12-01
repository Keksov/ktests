#!/bin/bash
# Unit tests: Core logging functions

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "CoreLoggingFunctions" "$(dirname "$0")"

# Test logging function exists
kt_test_start "kt_test_log function exists"
if declare -f kt_test_log > /dev/null 2>&1; then
    kt_test_pass "kt_test_log function available"
else
    kt_test_fail "kt_test_log function not found"
fi

# Test debug function exists
kt_test_start "kt_test_debug function exists"
if declare -f kt_test_debug > /dev/null 2>&1; then
    kt_test_pass "kt_test_debug function available"
else
    kt_test_fail "kt_test_debug function not found"
fi

# Test error function exists
kt_test_start "kt_test_error function exists"
if declare -f kt_test_error > /dev/null 2>&1; then
    kt_test_pass "kt_test_error function available"
else
    kt_test_fail "kt_test_error function not found"
fi

# Test warning function exists
kt_test_start "kt_test_warning function exists"
if declare -f kt_test_warning > /dev/null 2>&1; then
    kt_test_pass "kt_test_warning function available"
else
    kt_test_fail "kt_test_warning function not found"
fi

# Test section function exists
kt_test_start "kt_test_section function exists"
if declare -f kt_test_section > /dev/null 2>&1; then
    kt_test_pass "kt_test_section function available"
else
    kt_test_fail "kt_test_section function not found"
fi


