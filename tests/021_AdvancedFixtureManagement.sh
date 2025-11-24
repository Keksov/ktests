#!/bin/bash
# Unit tests: Advanced fixture management functions

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "AdvancedFixtureManagement" "$(dirname "$0")"

TMPDIR=$(kk_fixture_tmpdir)

# Test kk_fixture_cleanup_unregister with existing handler
kk_test_start "kk_fixture_cleanup_unregister with existing handler"
cleanup_test_handler() { :; }
declare -a _KK_CLEANUP_HANDLERS=("cleanup_test_handler")
kk_fixture_cleanup_register "cleanup_test_handler"
kk_fixture_cleanup_unregister "cleanup_test_handler"
if [[ ! " ${_KK_CLEANUP_HANDLERS[@]} " =~ " cleanup_test_handler " ]]; then
    kk_test_pass "Handler unregistered successfully"
else
    kk_test_fail "Handler not unregistered"
fi

# Test kk_fixture_cleanup_unregister with non-existing handler
kk_test_start "kk_fixture_cleanup_unregister with non-existing handler"
initial_count=${#_KK_CLEANUP_HANDLERS[@]}
kk_fixture_cleanup_unregister "nonexistent_handler"
if (( ${#_KK_CLEANUP_HANDLERS[@]} == initial_count )); then
    kk_test_pass "Non-existing handler cleanup handled gracefully"
else
    kk_test_fail "Non-existing handler cleanup affected count"
fi

# Test kk_fixture_create_file with content
kk_test_start "kk_fixture_create_file with content"
test_content="Test file content with special chars: \$@#"
created_file=$(kk_fixture_create_file "testfile.txt" "$test_content")
if [[ -f "$created_file" && "$(cat "$created_file")" == "$test_content" ]]; then
    kk_test_pass "File created with correct content"
else
    kk_test_fail "File creation failed"
fi

# Test kk_fixture_create_file with empty content
kk_test_start "kk_fixture_create_file with empty content"
empty_file=$(kk_fixture_create_file "empty.txt" "")
if [[ -f "$empty_file" && ! -s "$empty_file" ]]; then
    kk_test_pass "Empty file created successfully"
else
    kk_test_fail "Empty file creation failed"
fi

# Test kk_fixture_create_file with multiline content
kk_test_start "kk_fixture_create_file with multiline content"
multiline_content="Line 1
Line 2
Line 3"
multiline_file=$(kk_fixture_create_file "multiline.txt" "$multiline_content")
if [[ -f "$multiline_file" && "$(cat "$multiline_file")" == "$multiline_content" ]]; then
    kk_test_pass "Multiline file created correctly"
else
    kk_test_fail "Multiline file creation failed"
fi

# Test kk_fixture_create_structure with simple directories
kk_test_start "kk_fixture_create_structure with simple directories"
base_structure_dir=$(kk_fixture_tmpdir)
kk_fixture_create_structure "$base_structure_dir" "dir1" "dir2" "dir3/subdir"
if [[ -d "$base_structure_dir/dir1" && -d "$base_structure_dir/dir2" && -d "$base_structure_dir/dir3/subdir" ]]; then
    kk_test_pass "Simple directory structure created"
else
    kk_test_fail "Simple directory structure creation failed"
fi

# Test kk_fixture_create_structure with complex nested paths
kk_test_start "kk_fixture_create_structure with complex paths"
complex_structure_dir=$(kk_fixture_tmpdir)
kk_fixture_create_structure "$complex_structure_dir" "level1/level2/level3" "another/path/here"
if [[ -d "$complex_structure_dir/level1/level2/level3" && -d "$complex_structure_dir/another/path/here" ]]; then
    kk_test_pass "Complex nested structure created"
else
    kk_test_fail "Complex nested structure creation failed"
fi

# Test kk_fixture_create_structure with empty directories list
kk_test_start "kk_fixture_create_structure with empty directories list"
empty_structure_dir=$(kk_fixture_tmpdir)
kk_fixture_create_structure "$empty_structure_dir"
if [[ -d "$empty_structure_dir" ]]; then
    kk_test_pass "Empty directory list handled gracefully"
else
    kk_test_fail "Empty directory list handling failed"
fi

# Test kk_fixture_backup_file with existing file
kk_test_start "kk_fixture_backup_file with existing file"
original_file="$TMPDIR/original.txt"
echo "original content" > "$original_file"
backup_path=$(kk_fixture_backup_file "$original_file")
if [[ -f "$backup_path" && "$(cat "$backup_path")" == "original content" ]]; then
    kk_test_pass "File backed up successfully"
else
    kk_test_fail "File backup failed"
fi

# Test kk_fixture_backup_file creates backup with timestamp
kk_test_start "kk_fixture_backup_file creates timestamped backup"
file_to_backup="$TMPDIR/timestamped.txt"
echo "timestamped content" > "$file_to_backup"
backup_timestamped=$(kk_fixture_backup_file "$file_to_backup")
if [[ -f "$backup_timestamped" && "$backup_timestamped" == *".backup."* ]]; then
    kk_test_pass "Timestamped backup created"
else
    kk_test_fail "Timestamped backup creation failed"
fi

# Test kk_fixture_restore_file
kk_test_start "kk_fixture_restore_file"
restore_file="$TMPDIR/to_restore.txt"
echo "original content" > "$restore_file"
backup_for_restore=$(kk_fixture_backup_file "$restore_file")
echo "modified content" > "$restore_file"
kk_fixture_restore_file "$restore_file" "$backup_for_restore"
if [[ "$(cat "$restore_file")" == "original content" ]]; then
    kk_test_pass "File restored successfully"
else
    kk_test_fail "File restoration failed"
fi

# Test kk_fixture_restore_file removes backup after restore
kk_test_start "kk_fixture_restore_file removes backup after restore"
if [[ ! -f "$backup_for_restore" ]]; then
    kk_test_pass "Backup removed after restoration"
else
    kk_test_fail "Backup not removed after restoration"
fi

# Test multiple fixture operations in sequence
kk_test_start "Multiple fixture operations in sequence"
sequence_dir=$(kk_fixture_tmpdir)
test_file=$(kk_fixture_create_file "sequence.txt" "test content")
mkdir -p "$sequence_dir/subdir"
echo "test" > "$sequence_dir/subdir/testfile.txt"
if [[ -f "$test_file" && -f "$sequence_dir/subdir/testfile.txt" ]]; then
    kk_test_pass "Multiple fixture operations work together"
else
    kk_test_fail "Multiple fixture operations failed"
fi

# Test fixture cleanup with complex structure
kk_test_start "Fixture cleanup with complex structure"
complex_dir=$(kk_fixture_tmpdir)
mkdir -p "$complex_dir/level1/level2/level3"
touch "$complex_dir/level1/file1.txt"
touch "$complex_dir/level1/level2/file2.txt"
touch "$complex_dir/level1/level2/level3/file3.txt"
if [[ -f "$complex_dir/level1/level2/level3/file3.txt" ]]; then
    kk_test_pass "Complex structure created for cleanup test"
else
    kk_test_fail "Complex structure creation failed"
fi

# Test fixture with special characters in names
kk_test_start "Fixture operations with special characters"
special_dir=$(kk_fixture_tmpdir_create "dir-with-dashes_and_underscores")
special_file=$(kk_fixture_create_file "file!@#\$%^&*.txt" "special content")
if [[ -d "$special_dir" && -f "$special_file" ]]; then
    kk_test_pass "Special characters handled correctly"
else
    kk_test_fail "Special characters not handled correctly"
fi

# Test fixture with very long path names
kk_test_start "Fixture with very long path names"
long_name_dir=$(kk_fixture_tmpdir_create $(printf "very_long_directory_name_%s" {1..20}))
long_name_file=$(kk_fixture_create_file $(printf "very_long_file_name_%s.txt" {1..20}) "long name content")
if [[ -d "$long_name_dir" && -f "$long_name_file" ]]; then
    kk_test_pass "Very long names handled correctly"
else
    kk_test_fail "Very long names not handled correctly"
fi

# Test kk_fixture_tmpdir_create with empty name
kk_test_start "kk_fixture_tmpdir_create with empty name"
empty_name_dir=$(kk_fixture_tmpdir_create "")
if [[ -d "$empty_name_dir" && "$empty_name_dir" == *"/tmpdir"* ]]; then
    kk_test_pass "Empty name handled with default"
else
    kk_test_fail "Empty name handling failed"
fi

# Test nested fixture operations
kk_test_start "Nested fixture operations"
nested_base=$(kk_fixture_tmpdir)
nested_dir1=$(kk_fixture_tmpdir_create "nested1" "$nested_base")
nested_dir2=$(kk_fixture_tmpdir_create "nested2" "$nested_dir1")
nested_file=$(kk_fixture_create_file "nested.txt" "nested content" "$nested_dir2")
if [[ -d "$nested_dir2" && -f "$nested_file" ]]; then
    kk_test_pass "Nested fixture operations work"
else
    kk_test_fail "Nested fixture operations failed"
fi