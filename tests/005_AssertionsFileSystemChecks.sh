#!/bin/bash
# Unit tests: File system assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "AssertionsFileSystemChecks" "$(dirname "$0")"

TMPDIR=$(kt_fixture_tmpdir)

# Test kt_assert_file_exists with existing file
kt_test_start "kt_assert_file_exists with existing file"
test_file=$(kt_fixture_tmpfile "test")
if kt_assert_file_exists "$test_file" "File exists"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_file_exists fails with missing file
kt_test_start "kt_assert_file_exists fails with missing file"
if ! kt_assert_quiet kt_assert_file_exists "/nonexistent/path/file.txt" "Missing file"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_dir_exists with existing directory
kt_test_start "kt_assert_dir_exists with existing directory"
if kt_assert_dir_exists "$TMPDIR" "Directory exists"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_dir_exists fails with missing directory
kt_test_start "kt_assert_dir_exists fails with missing directory"
if ! kt_assert_quiet kt_assert_dir_exists "/nonexistent/path" "Missing directory"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi


