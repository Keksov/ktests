#!/bin/bash
# Unit tests: File system assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "AssertionsFileSystemChecks" "$(dirname "$0")"

TMPDIR=$(kk_fixture_tmpdir)

# Test kk_assert_file_exists with existing file
kk_test_start "kk_assert_file_exists with existing file"
test_file=$(kk_fixture_tmpfile "test")
if kk_assert_file_exists "$test_file" "File exists" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_file_exists detects existing file"
else
    kk_test_fail "kk_assert_file_exists failed with existing file"
fi

# Test kk_assert_file_exists fails with missing file
kk_test_start "kk_assert_file_exists fails with missing file"
if ! kk_assert_file_exists "/nonexistent/path/file.txt" "Missing file" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_file_exists detects missing file"
else
    kk_test_fail "kk_assert_file_exists should have failed with missing file"
fi

# Test kk_assert_dir_exists with existing directory
kk_test_start "kk_assert_dir_exists with existing directory"
if kk_assert_dir_exists "$TMPDIR" "Directory exists" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_dir_exists detects existing directory"
else
    kk_test_fail "kk_assert_dir_exists failed with existing directory"
fi

# Test kk_assert_dir_exists fails with missing directory
kk_test_start "kk_assert_dir_exists fails with missing directory"
if ! kk_assert_dir_exists "/nonexistent/path" "Missing directory" >/dev/null 2>&1; then
    kk_test_pass "kk_assert_dir_exists detects missing directory"
else
    kk_test_fail "kk_assert_dir_exists should have failed with missing directory"
fi
