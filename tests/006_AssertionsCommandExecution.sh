#!/bin/bash
# Unit tests: Command execution assertions

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "AssertionsCommandExecution" "$(dirname "$0")"

# Test kk_assert_success with successful command
kk_test_start "kk_assert_success with successful command"
if kk_assert_success "true" "Successful command"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_success fails with failed command
kk_test_start "kk_assert_success fails with failed command"
if ! kk_assert_success "false" "Failed command"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi


