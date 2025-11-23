#!/bin/bash
# Unit tests: File system assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "AssertionsFileSystemChecks" "$(dirname "$0")"

TMPDIR=$(kk_fixture_tmpdir)

# Test kk_assert_file_exists with existing file
kk_test_start "kk_assert_file_exists with existing file"
test_file=$(kk_fixture_tmpfile "test")
if kk_assert_file_exists "$test_file" "File exists"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_file_exists fails with missing file
kk_test_start "kk_assert_file_exists fails with missing file"
if ! kk_assert_file_exists "/nonexistent/path/file.txt" "Missing file"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_dir_exists with existing directory
kk_test_start "kk_assert_dir_exists with existing directory"
if kk_assert_dir_exists "$TMPDIR" "Directory exists"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_dir_exists fails with missing directory
kk_test_start "kk_assert_dir_exists fails with missing directory"
if ! kk_assert_dir_exists "/nonexistent/path" "Missing directory"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi


