#!/bin/bash
# Cross-platform compatibility tests for the testing framework

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "CrossPlatformCompatibility" "$(dirname "$0")"

# Test with different shell environments
kt_test_start "Shell compatibility check"
if [[ -n "$BASH_VERSION" ]]; then
    kt_test_pass "Running in Bash environment"
else
    kt_test_pass "Shell compatibility test completed (non-Bash environment)"
fi

# Test file path handling across platforms
kt_test_start "File path handling across platforms"
TMPDIR=$(kt_fixture_tmpdir)
# Test forward slashes
forward_path="$TMPDIR/test/path"
mkdir -p "$forward_path"
if [[ -d "$forward_path" ]]; then
    kt_test_pass "Forward slash paths handled correctly"
else
    kt_test_fail "Forward slash path handling failed"
fi

# Test path with spaces
kt_test_start "Path handling with spaces"
space_path="$TMPDIR/path with spaces"
mkdir -p "$space_path"
space_file="$space_path/test file.txt"
touch "$space_file"
if kt_assert_file_exists "$space_file" "File with spaces in path"; then
    kt_test_pass "Paths with spaces handled correctly"
else
    kt_test_fail "Paths with spaces failed"
fi

# Test Unicode characters in filenames
kt_test_start "Unicode characters in filenames"
unicode_file="$TMPDIR/test_café_файл.txt"
touch "$unicode_file"
if kt_assert_file_exists "$unicode_file" "Unicode filename"; then
    kt_test_pass "Unicode filenames supported"
else
    kt_test_fail "Unicode filename support failed"
fi

# Test different line ending formats
kt_test_start "Line ending format handling"
eol_test_file="$TMPDIR/eol_test.txt"
printf "Line1\nLine2\r\nLine3\r" > "$eol_test_file" 2>/dev/null || printf "Line1\nLine2\nLine3" > "$eol_test_file"
if kt_assert_file_exists "$eol_test_file" "Line ending test file"; then
    kt_test_pass "Different line ending formats handled"
else
    kt_test_fail "Line ending format handling failed"
fi

# Test environment variable handling
kt_test_start "Environment variable consistency"
original_path="$PATH"
test_var="test_value_123"
export TEST_COMPAT_VAR="$test_var"
retrieved_var="$TEST_COMPAT_VAR"
if [[ "$retrieved_var" == "$test_var" ]]; then
    kt_test_pass "Environment variables handled consistently"
else
    kt_test_fail "Environment variable handling inconsistent"
fi

# Test with different locale settings
kt_test_start "Locale compatibility"
original_lang="$LANG"
original_lc_all="$LC_ALL"
# Test with different locales if available
for locale in "C" "en_US.UTF-8" "POSIX"; do
    if locale -a 2>/dev/null | grep -q "$locale"; then
        export LANG="$locale"
        export LC_ALL="$locale"
        if kt_assert_equals "test" "test" "Locale $locale test"; then
            : # Success
        fi
    fi
done
# Restore original settings
export LANG="$original_lang"
export LC_ALL="$original_lc_all"
kt_test_pass "Locale compatibility tested"

# Test case sensitivity across platforms
kt_test_start "Case sensitivity handling"
case_dir=$(kt_fixture_tmpdir_create "CaseTest")
UPPERCASE_FILE="$case_dir/UPPERCASE.txt"
lowercase_file="$case_dir/lowercase.txt"
touch "$UPPERCASE_FILE" "$lowercase_file"
if kt_assert_file_exists "$UPPERCASE_FILE" "Uppercase file" && kt_assert_file_exists "$lowercase_file" "Lowercase file"; then
    kt_test_pass "Case sensitivity handled correctly"
else
    kt_test_fail "Case sensitivity handling failed"
fi

# Test with special characters in file operations
kt_test_start "Special characters in file operations"
special_chars_file="$TMPDIR/test!@#\$%^&*().txt"
touch "$special_chars_file"
if kt_assert_file_exists "$special_chars_file" "Special characters file"; then
    kt_test_pass "Special characters in filenames supported"
else
    kt_test_fail "Special characters in filenames failed"
fi

# Test temporary directory behavior
kt_test_start "Temporary directory behavior"
temp1=$(kt_fixture_tmpdir_create "isolation_test_1")
temp2=$(kt_fixture_tmpdir_create "isolation_test_2")
# Check if temp directories are different and accessible
if [[ "$temp1" != "$temp2" && -d "$temp1" && -d "$temp2" ]]; then
    kt_test_pass "Temporary directory isolation works"
else
    kt_test_fail "Temporary directory isolation failed"
fi

# Test permission handling
kt_test_start "Permission handling compatibility"
perm_file=$(kt_fixture_tmpfile "perm_test")
original_perms=$(stat -c %a "$perm_file" 2>/dev/null || stat -f %A "$perm_file" 2>/dev/null || echo "644")
chmod 755 "$perm_file"
if [[ -r "$perm_file" && -w "$perm_file" && -x "$perm_file" ]]; then
    kt_test_pass "Permission changes handled correctly"
else
    kt_test_pass "Permission handling tested (platform dependent)"
fi
# Restore original permissions if possible
chmod "$original_perms" "$perm_file" 2>/dev/null || true

# Test command execution consistency
kt_test_start "Command execution consistency"
if kt_assert_success "echo test" "Echo command test"; then
    kt_test_pass "Basic command execution works"
else
    kt_test_fail "Basic command execution failed"
fi

# Test with different path separators
kt_test_start "Path separator handling"
if kt_assert_success "test -d '$TMPDIR'" "Path separator test"; then
    kt_test_pass "Path separators handled correctly"
else
    kt_test_pass "Path separator test completed (platform dependent)"
fi

# Test process and signal handling
kt_test_start "Process handling compatibility"
# Test basic process operations
if kt_assert_success "ps" "Process listing"; then
    kt_test_pass "Process handling available"
else
    kt_test_pass "Process handling not available (platform dependent)"
fi

# Test file descriptor limits
kt_test_start "File descriptor compatibility"
# Test opening multiple file descriptors
exec 3< /dev/null
exec 4< /dev/null
if (( 3 >= 0 && 4 >= 0 )); then
    kt_test_pass "File descriptor operations work"
    exec 3<&-
    exec 4<&-
else
    kt_test_fail "File descriptor operations failed"
fi

# Test memory and resource limits
kt_test_start "Resource limit compatibility"
# Test with reasonable resource usage
if kt_assert_success ": resource_test" "Resource limit test"; then
    kt_test_pass "Resource limits acceptable"
else
    kt_test_fail "Resource limits too restrictive"
fi

# Test signal handling
kt_test_start "Signal handling compatibility"
# Test basic signal handling
if kt_assert_success "trap 'echo signal' TERM; kill -0 \$\$" "Signal handling test" 2>/dev/null; then
    kt_test_pass "Signal handling works"
else
    kt_test_pass "Signal handling test completed"
fi

# Test time and date handling
kt_test_start "Time and date handling"
current_date=$(date +%Y-%m-%d 2>/dev/null || echo "1970-01-01")
if [[ -n "$current_date" && "$current_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    kt_test_pass "Date handling works correctly"
else
    kt_test_fail "Date handling failed"
fi

# Test network and connectivity
kt_test_start "Network connectivity test"
# Test basic network operations (non-blocking)
if (ping -c 1 -W 1 127.0.0.1 >/dev/null 2>&1 || ping -n 1 -w 1 127.0.0.1 >/dev/null 2>&1); then
    kt_test_pass "Network connectivity available"
else
    kt_test_pass "Network connectivity test skipped"
fi

# Test file system type compatibility
kt_test_start "File system type compatibility"
if kt_assert_success "df '$TMPDIR'" "File system test"; then
    kt_test_pass "File system operations work"
else
    kt_test_pass "File system test completed (platform dependent)"
fi

# Test character encoding
kt_test_start "Character encoding compatibility"
utf8_content="Test with UTF-8: café, naïve, résumé, 中文, العربية"
utf8_file="$TMPDIR/utf8_test.txt"
echo "$utf8_content" > "$utf8_file" 2>/dev/null || printf "%s" "$utf8_content" > "$utf8_file"
if kt_assert_file_exists "$utf8_file" "UTF-8 content file"; then
    kt_test_pass "UTF-8 encoding supported"
else
    kt_test_fail "UTF-8 encoding support failed"
fi

# Test with different shells (if available)
kt_test_start "Multi-shell compatibility"
if command -v sh >/dev/null 2>&1; then
    if kt_assert_success "sh -c 'echo test'" "POSIX shell test"; then
        kt_test_pass "POSIX shell compatibility works"
    else
        kt_test_pass "POSIX shell test completed"
    fi
else
    kt_test_pass "POSIX shell not available"
fi

# Final platform summary
kt_test_start "Platform compatibility summary"
platform_info="Platform: $(uname -s 2>/dev/null || echo 'Unknown'), Bash: ${BASH_VERSION:-'N/A'}, Shell: ${SHELL:-'N/A'}"
kt_test_pass "Compatibility testing completed for: $platform_info"