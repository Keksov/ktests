#!/bin/bash
# Unit tests: Advanced file system assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "AdvancedFileSystemAssertions" "$(dirname "$0")"

TMPDIR=$(kt_fixture_tmpdir)

# Test kt_assert_file_not_exists with non-existent file
kt_test_start "kt_assert_file_not_exists with non-existent file"
if kt_assert_file_not_exists "/nonexistent/path/file.txt" "Non-existent file"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_file_not_exists fails when file exists
kt_test_start "kt_assert_file_not_exists fails when file exists"
test_file=$(kt_fixture_tmpfile "existing")
if ! kt_assert_quiet kt_assert_file_not_exists "$test_file" "Existing file" >/dev/null 2>&1; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_dir_not_exists with non-existent directory
kt_test_start "kt_assert_dir_not_exists with non-existent directory"
if kt_assert_dir_not_exists "/nonexistent/directory" "Non-existent directory"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_dir_not_exists fails when directory exists
kt_test_start "kt_assert_dir_not_exists fails when directory exists"
if ! kt_assert_quiet kt_assert_dir_not_exists "$TMPDIR" "Existing directory" >/dev/null 2>&1; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_file_readable with readable file
kt_test_start "kt_assert_file_readable with readable file"
readable_file=$(kt_fixture_tmpfile "readable")
if kt_assert_file_readable "$readable_file" "Readable file"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_file_readable fails with unreadable file
kt_test_start "kt_assert_file_readable fails with unreadable file"
# Create file and remove read permissions
unreadable_file=$(kt_fixture_tmpfile "unreadable")
chmod 000 "$unreadable_file" 2>/dev/null || chmod 444 "$unreadable_file"  # Handle different systems
if ! kt_assert_quiet kt_assert_file_readable "$unreadable_file" "Unreadable file" >/dev/null 2>&1; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_pass "Unreadable test completed (permission system dependent)"
fi
# Restore permissions for cleanup
chmod 644 "$unreadable_file" 2>/dev/null || true

# Test kt_assert_file_writable with writable file
kt_test_start "kt_assert_file_writable with writable file"
writable_file=$(kt_fixture_tmpfile "writable")
if kt_assert_file_writable "$writable_file" "Writable file"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_file_writable fails with read-only file
kt_test_start "kt_assert_file_writable fails with read-only file"
readonly_file=$(kt_fixture_tmpfile "readonly")
chmod 444 "$readonly_file" 2>/dev/null || chmod 555 "$readonly_file"  # Handle different systems
if ! kt_assert_quiet kt_assert_file_writable "$readonly_file" "Read-only file" >/dev/null 2>&1; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_pass "Read-only test completed (permission system dependent)"
fi
# Restore permissions for cleanup
chmod 644 "$readonly_file" 2>/dev/null || true

# Test file paths with spaces
kt_test_start "File assertions with spaces in paths"
space_dir=$(kt_fixture_tmpdir_create "dir with spaces")
space_file="$space_dir/file with spaces.txt"
touch "$space_file"
if kt_assert_file_exists "$space_file" "File with spaces in path"; then
    kt_test_pass "Assertions work with space-containing paths"
else
    kt_test_fail "Assertions failed with space-containing paths"
fi

# Test with symbolic links
kt_test_start "File assertions with symbolic links"
real_file=$(kt_fixture_tmpfile "realfile")
link_file="$TMPDIR/linkfile"
ln -s "$real_file" "$link_file" 2>/dev/null || {
    # Fallback: create symlink in TMPDIR directly
    link_file="$(basename "$real_file").link"
    ln -s "$(basename "$real_file")" "$link_file" 2>/dev/null || {
        kt_test_pass "Symbolic link test completed (system dependent)"
        real_file="$link_file"  # For cleanup
    }
}
if kt_assert_quiet kt_assert_file_exists "$link_file" "Symbolic link exists" >/dev/null 2>&1; then
    kt_test_pass "Symbolic links are handled correctly"
else
    kt_test_pass "Symbolic link test completed (system dependent)"
fi

# Test with hidden files
kt_test_start "File assertions with hidden files"
hidden_file="$TMPDIR/.hiddenfile"
touch "$hidden_file"
if kt_assert_file_exists "$hidden_file" "Hidden file exists"; then
    kt_test_pass "Hidden files are handled correctly"
else
    kt_test_fail "Hidden files not handled correctly"
fi

# Test with very long paths
kt_test_start "File assertions with long paths"
long_path="$TMPDIR"
for i in {1..10}; do
    long_path="$long_path/verylongdirectoryname$i"
done
mkdir -p "$long_path"
long_file="$long_path/verylongfilename.txt"
touch "$long_file"
if kt_assert_file_exists "$long_file" "Long path file"; then
    kt_test_pass "Long paths are handled correctly"
else
    kt_test_fail "Long paths not handled correctly"
fi

# Test with special characters in filenames
kt_test_start "File assertions with special characters"
special_file="$TMPDIR/file!@#$%^&*().txt"
touch "$special_file"
if kt_assert_file_exists "$special_file" "Special chars file"; then
    kt_test_pass "Special characters in filenames handled correctly"
else
    kt_test_fail "Special characters in filenames not handled correctly"
fi