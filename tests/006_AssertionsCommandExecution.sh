#!/usr/bin/env bash
# Unit tests: Command execution assertions

# Only source if framework not already loaded
if [[ -z "$_KTEST_SOURCED" ]]; then
    source "$(dirname "$0")/../ktest_source.sh" || source "$KTEST_SOURCE_PATH" || exit 1
fi

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
