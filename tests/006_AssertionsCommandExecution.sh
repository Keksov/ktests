#!/bin/bash
# Unit tests: Command execution assertions

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "AssertionsCommandExecution" "$(dirname "$0")"

# Test kk_assert_success with successful command
kk_test_start "kk_assert_success with successful command"
if kk_assert_success "true" "Successful command" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_success detects successful command"
else
    kk_test_fail "kk_assert_success failed with successful command"
fi

# Test kk_assert_success fails with failed command
kk_test_start "kk_assert_success fails with failed command"
if ! kk_assert_success "false" "Failed command" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_success detects failed command"
else
    kk_test_fail "kk_assert_success should have failed with failed command"
fi
