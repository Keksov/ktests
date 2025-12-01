#!/bin/bash
# Unit tests: Command failure assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "CommandFailureTesting" "$(dirname "$0")"

# Test kt_assert_failure with command that fails
kt_test_start "kt_assert_failure with failed command"
if kt_assert_failure "false" "Failed command"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure fails with successful command
kt_test_start "kt_assert_failure fails with successful command"
if ! kt_assert_quiet kt_assert_failure "true" "Successful command"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_failure with command that exits with specific code
kt_test_start "kt_assert_failure with command that exits with code 1"
if kt_assert_failure "exit 1" "Exit code 1"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with command that exits with code 2
kt_test_start "kt_assert_failure with command that exits with code 2"
if kt_assert_failure "exit 2" "Exit code 2"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with non-existent command
kt_test_start "kt_assert_failure with non-existent command"
if kt_assert_failure "/nonexistent/command/path/123" "Non-existent command"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with command that fails due to permission
kt_test_start "kt_assert_failure with permission denied command"
if kt_assert_failure "cat /root/secret" "Permission denied"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with command that fails due to missing file
kt_test_start "kt_assert_failure with missing file command"
if kt_assert_failure "cat /nonexistent/file.txt" "Missing file"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with command that fails due to invalid syntax
kt_test_start "kt_assert_failure with invalid command syntax"
if kt_assert_failure "bash -c 'if [ missing then'" "Invalid syntax"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with command that fails with stderr output
kt_test_start "kt_assert_failure with command that outputs to stderr"
if kt_assert_failure "echo 'error message' >&2; exit 1" "Stderr output"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with complex piped command that fails
kt_test_start "kt_assert_failure with piped command that fails"
if kt_assert_failure "echo 'test' | grep 'notfound'" "Failed piped command"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with command that fails
kt_test_start "kt_assert_failure with grep not matching"
if kt_assert_failure "grep 'nonexistent_pattern' /dev/null" "Grep no match"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with command that fails due to invalid option
kt_test_start "kt_assert_failure with invalid command option"
if kt_assert_failure "ls --invalid-option" "Invalid option"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with multiple arguments
kt_test_start "kt_assert_failure with multiple command arguments"
if kt_assert_failure "mkdir /readonly/directory" "Multiple arguments"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with false command (should pass)
kt_test_start "kt_assert_failure with false command again"
if kt_assert_failure "false" "False command"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_failure with command that fails due to missing variable
kt_test_start "kt_assert_failure with undefined variable in set -u mode"
if kt_assert_failure "bash -u -c 'echo \$UNDEFINED_VAR'" "Undefined variable"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi