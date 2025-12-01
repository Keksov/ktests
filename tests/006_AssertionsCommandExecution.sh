#!/bin/bash
# Unit tests: Command execution assertions

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "AssertionsCommandExecution" "$(dirname "$0")"

# Test kt_assert_success with successful command
kt_test_start "kt_assert_success with successful command"
if kt_assert_success "true" "Successful command"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_success fails with failed command
kt_test_start "kt_assert_success fails with failed command"
if ! kt_assert_quiet kt_assert_success "false" "Failed command"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi


