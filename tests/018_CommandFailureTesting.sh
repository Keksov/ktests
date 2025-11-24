#!/bin/bash
# Unit tests: Command failure assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "CommandFailureTesting" "$(dirname "$0")"

# Test kk_assert_failure with command that fails
kk_test_start "kk_assert_failure with failed command"
if kk_assert_failure "false" "Failed command"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure fails with successful command
kk_test_start "kk_assert_failure fails with successful command"
if ! kk_assert_failure "true" "Successful command"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_failure with command that exits with specific code
kk_test_start "kk_assert_failure with command that exits with code 1"
if kk_assert_failure "exit 1" "Exit code 1"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with command that exits with code 2
kk_test_start "kk_assert_failure with command that exits with code 2"
if kk_assert_failure "exit 2" "Exit code 2"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with non-existent command
kk_test_start "kk_assert_failure with non-existent command"
if kk_assert_failure "nonexistentcommand123" "Non-existent command"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with command that fails due to permission
kk_test_start "kk_assert_failure with permission denied command"
if kk_assert_failure "cat /root/secret" "Permission denied"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with command that fails due to missing file
kk_test_start "kk_assert_failure with missing file command"
if kk_assert_failure "cat /nonexistent/file.txt" "Missing file"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with command that fails due to invalid syntax
kk_test_start "kk_assert_failure with invalid command syntax"
if kk_assert_failure "if [ missing then" "Invalid syntax"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with command that fails with stderr output
kk_test_start "kk_assert_failure with command that outputs to stderr"
if kk_assert_failure "echo 'error message' >&2; exit 1" "Stderr output"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with complex piped command that fails
kk_test_start "kk_assert_failure with piped command that fails"
if kk_assert_failure "echo 'test' | grep 'notfound' | wc -l" "Failed piped command"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with command that times out
kk_test_start "kk_assert_failure with long-running command"
if kk_assert_failure "sleep 10" "Long-running command"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with command that fails due to invalid option
kk_test_start "kk_assert_failure with invalid command option"
if kk_assert_failure "ls --invalid-option" "Invalid option"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with multiple arguments
kk_test_start "kk_assert_failure with multiple command arguments"
if kk_assert_failure "mkdir /readonly/directory" "Multiple arguments"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with empty command (should fail)
kk_test_start "kk_assert_failure with empty command"
if kk_assert_failure "" "Empty command"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_failure with command that fails due to environment
kk_test_start "kk_assert_failure with environment variable command"
export NONEXISTENT_VAR="value"
if kk_assert_failure "echo \$NONEXISTENT_VAR" "Environment variable"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi