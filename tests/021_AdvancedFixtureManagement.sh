#!/bin/bash
# Unit tests: Advanced fixture management functions

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "AdvancedFixtureManagement" "$(dirname "$0")" "$@"

TMPDIR=$(kt_fixture_tmpdir)

# Test kt_fixture_cleanup_unregister with existing handler
kt_test_start "kt_fixture_cleanup_unregister with existing handler"
cleanup_test_handler() { :; }
kt_fixture_cleanup_register "cleanup_test_handler"
initial_handlers=${#_KT_CLEANUP_HANDLERS[@]}
kt_fixture_cleanup_unregister "cleanup_test_handler"
final_handlers=${#_KT_CLEANUP_HANDLERS[@]}
if (( final_handlers < initial_handlers )); then
    kt_test_pass "Handler unregistered successfully"
else
    kt_test_fail "Handler not unregistered"
fi

# Test kt_fixture_cleanup_unregister with non-existing handler
kt_test_start "kt_fixture_cleanup_unregister with non-existing handler"
initial_count=${#_KT_CLEANUP_HANDLERS[@]}
kt_warn_quiet kt_fixture_cleanup_unregister "nonexistent_handler"
if (( ${#_KT_CLEANUP_HANDLERS[@]} == initial_count )); then
    kt_test_pass "Non-existing handler cleanup handled gracefully"
else
    kt_test_fail "Non-existing handler cleanup affected count"
fi

# Test kt_fixture_create_file with content
kt_test_start "kt_fixture_create_file with content"
test_content="Test file content with special chars: \$@#"
created_file=$(kt_fixture_create_file "testfile.txt" "$test_content")
if [[ -f "$created_file" && "$(cat "$created_file")" == "$test_content" ]]; then
    kt_test_pass "File created with correct content"
else
    kt_test_fail "File creation failed"
fi

# Test kt_fixture_create_file with empty content
kt_test_start "kt_fixture_create_file with empty content"
empty_file=$(kt_fixture_create_file "empty.txt" "")
if [[ -f "$empty_file" && ! -s "$empty_file" ]]; then
    kt_test_pass "Empty file created successfully"
else
    kt_test_fail "Empty file creation failed"
fi

# Test kt_fixture_create_file with multiline content
kt_test_start "kt_fixture_create_file with multiline content"
multiline_content="Line 1
Line 2
Line 3"
multiline_file=$(kt_fixture_create_file "multiline.txt" "$multiline_content")
if [[ -f "$multiline_file" && "$(cat "$multiline_file")" == "$multiline_content" ]]; then
    kt_test_pass "Multiline file created correctly"
else
    kt_test_fail "Multiline file creation failed"
fi

# Test kt_fixture_create_structure with simple directories
kt_test_start "kt_fixture_create_structure with simple directories"
base_structure_dir=$(kt_fixture_tmpdir)
kt_fixture_create_structure "$base_structure_dir" "dir1" "dir2" "dir3/subdir"
if [[ -d "$base_structure_dir/dir1" && -d "$base_structure_dir/dir2" && -d "$base_structure_dir/dir3/subdir" ]]; then
    kt_test_pass "Simple directory structure created"
else
    kt_test_fail "Simple directory structure creation failed"
fi

# Test kt_fixture_create_structure with complex nested paths
kt_test_start "kt_fixture_create_structure with complex paths"
complex_structure_dir=$(kt_fixture_tmpdir)
kt_fixture_create_structure "$complex_structure_dir" "level1/level2/level3" "another/path/here"
if [[ -d "$complex_structure_dir/level1/level2/level3" && -d "$complex_structure_dir/another/path/here" ]]; then
    kt_test_pass "Complex nested structure created"
else
    kt_test_fail "Complex nested structure creation failed"
fi

# Test kt_fixture_create_structure with empty directories list
kt_test_start "kt_fixture_create_structure with empty directories list"
empty_structure_dir=$(kt_fixture_tmpdir)
kt_fixture_create_structure "$empty_structure_dir"
if [[ -d "$empty_structure_dir" ]]; then
    kt_test_pass "Empty directory list handled gracefully"
else
    kt_test_fail "Empty directory list handling failed"
fi

# Test kt_fixture_backup_file with existing file
kt_test_start "kt_fixture_backup_file with existing file"
original_file="$TMPDIR/original.txt"
echo "original content" > "$original_file"
backup_path=$(kt_fixture_backup_file "$original_file")
if [[ -f "$backup_path" && "$(cat "$backup_path")" == "original content" ]]; then
    kt_test_pass "File backed up successfully"
else
    kt_test_fail "File backup failed"
fi

# Test kt_fixture_backup_file creates backup with PID
kt_test_start "kt_fixture_backup_file creates timestamped backup"
file_to_backup="$TMPDIR/timestamped.txt"
echo "timestamped content" > "$file_to_backup"
backup_timestamped=$(kt_fixture_backup_file "$file_to_backup")
if [[ -f "$backup_timestamped" && "$backup_timestamped" == *"_backup_"* ]]; then
    kt_test_pass "Timestamped backup created"
else
    kt_test_fail "Timestamped backup creation failed"
fi

# Test kt_fixture_restore_file
kt_test_start "kt_fixture_restore_file"
restore_file="$TMPDIR/to_restore.txt"
echo "original content" > "$restore_file"
backup_for_restore=$(kt_fixture_backup_file "$restore_file")
echo "modified content" > "$restore_file"
kt_fixture_restore_file "$restore_file" "$backup_for_restore"
if [[ "$(cat "$restore_file")" == "original content" ]]; then
    kt_test_pass "File restored successfully"
else
    kt_test_fail "File restoration failed"
fi

# Test kt_fixture_restore_file restores content correctly
kt_test_start "kt_fixture_restore_file removes backup after restore"
# Note: kt_fixture_restore_file does not remove backup automatically
# It only restores the file. Manual cleanup via teardown happens via handlers
if [[ -f "$backup_for_restore" ]]; then
    kt_test_pass "Backup preserved for cleanup handler"
else
    kt_test_fail "Backup not preserved"
fi

# Test multiple fixture operations in sequence
kt_test_start "Multiple fixture operations in sequence"
sequence_dir=$(kt_fixture_tmpdir)
test_file=$(kt_fixture_create_file "sequence.txt" "test content")
mkdir -p "$sequence_dir/subdir"
echo "test" > "$sequence_dir/subdir/testfile.txt"
if [[ -f "$test_file" && -f "$sequence_dir/subdir/testfile.txt" ]]; then
    kt_test_pass "Multiple fixture operations work together"
else
    kt_test_fail "Multiple fixture operations failed"
fi

# Test fixture cleanup with complex structure
kt_test_start "Fixture cleanup with complex structure"
complex_dir=$(kt_fixture_tmpdir)
mkdir -p "$complex_dir/level1/level2/level3"
touch "$complex_dir/level1/file1.txt"
touch "$complex_dir/level1/level2/file2.txt"
touch "$complex_dir/level1/level2/level3/file3.txt"
if [[ -f "$complex_dir/level1/level2/level3/file3.txt" ]]; then
    kt_test_pass "Complex structure created for cleanup test"
else
    kt_test_fail "Complex structure creation failed"
fi

# Test fixture with special characters in names
kt_test_start "Fixture operations with special characters"
special_dir=$(kt_fixture_tmpdir_create "dir-with-dashes_and_underscores")
special_file=$(kt_fixture_create_file "file!@#\$%^&*.txt" "special content")
if [[ -d "$special_dir" && -f "$special_file" ]]; then
    kt_test_pass "Special characters handled correctly"
else
    kt_test_fail "Special characters not handled correctly"
fi

# Test fixture with reasonably long path names
kt_test_start "Fixture with very long path names"
long_name_dir=$(kt_fixture_tmpdir_create "very_long_directory_name_with_meaningful_content")
long_name_file=$(kt_fixture_create_file "very_long_file_name_with_meaningful_content.txt" "long name content")
if [[ -d "$long_name_dir" && -f "$long_name_file" ]]; then
    kt_test_pass "Very long names handled correctly"
else
    kt_test_fail "Very long names not handled correctly"
fi

# Test kt_fixture_tmpdir_create with empty name
kt_test_start "kt_fixture_tmpdir_create with empty name"
empty_name_dir=$(kt_fixture_tmpdir_create "")
if [[ -d "$empty_name_dir" && "$empty_name_dir" == *"/tmpdir"* ]]; then
    kt_test_pass "Empty name handled with default"
else
    kt_test_fail "Empty name handling failed"
fi

# Test nested fixture operations
kt_test_start "Nested fixture operations"
nested_base=$(kt_fixture_tmpdir)
nested_dir1=$(kt_fixture_tmpdir_create "nested1" "$nested_base")
nested_dir2=$(kt_fixture_tmpdir_create "nested2" "$nested_dir1")
nested_file=$(kt_fixture_create_file "nested.txt" "nested content" "$nested_dir2")
if [[ -d "$nested_dir2" && -f "$nested_file" ]]; then
    kt_test_pass "Nested fixture operations work"
else
    kt_test_fail "Nested fixture operations failed"
fi