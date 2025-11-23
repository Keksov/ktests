#!/bin/bash
# Unit tests: Core logging functions

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "CoreLoggingFunctions" "$(dirname "$0")"

# Test logging function exists
kk_test_start "kk_test_log function exists"
if declare -f kk_test_log > /dev/null 2>&1; then
    kk_test_pass "kk_test_log function available"
else
    kk_test_fail "kk_test_log function not found"
fi

# Test debug function exists
kk_test_start "kk_test_debug function exists"
if declare -f kk_test_debug > /dev/null 2>&1; then
    kk_test_pass "kk_test_debug function available"
else
    kk_test_fail "kk_test_debug function not found"
fi

# Test error function exists
kk_test_start "kk_test_error function exists"
if declare -f kk_test_error > /dev/null 2>&1; then
    kk_test_pass "kk_test_error function available"
else
    kk_test_fail "kk_test_error function not found"
fi

# Test warning function exists
kk_test_start "kk_test_warning function exists"
if declare -f kk_test_warning > /dev/null 2>&1; then
    kk_test_pass "kk_test_warning function available"
else
    kk_test_fail "kk_test_warning function not found"
fi

# Test section function exists
kk_test_start "kk_test_section function exists"
if declare -f kk_test_section > /dev/null 2>&1; then
    kk_test_pass "kk_test_section function available"
else
    kk_test_fail "kk_test_section function not found"
fi
