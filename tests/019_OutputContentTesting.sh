#!/bin/bash
# Unit tests: Output content assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "OutputContentTesting" "$(dirname "$0")"

# Test kt_assert_output_contains with matching content
kt_test_start "kt_assert_output_contains with matching content"
output="Hello world, this is a test"
if kt_assert_output_contains "$output" "world" "Contains test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_output_contains fails with non-matching content
kt_test_start "kt_assert_output_contains fails with non-matching content"
output="Hello world"
if ! kt_assert_quiet kt_assert_output_contains "$output" "xyz" "Non-matching test"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_output_not_contains with non-matching content
kt_test_start "kt_assert_output_not_contains with non-matching content"
output="Hello world"
if kt_assert_output_not_contains "$output" "xyz" "Non-matching test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_output_not_contains fails with matching content
kt_test_start "kt_assert_output_not_contains fails with matching content"
output="Hello world"
if ! kt_assert_quiet kt_assert_output_not_contains "$output" "world" "Matching test"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test kt_assert_output_matches with matching pattern
kt_test_start "kt_assert_output_matches with matching pattern"
output="Test123"
if kt_assert_output_matches "$output" "[0-9]+" "Pattern match"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_output_matches fails with non-matching pattern
kt_test_start "kt_assert_output_matches fails with non-matching pattern"
output="TestABC"
if ! kt_assert_quiet kt_assert_output_matches "$output" "[0-9]+" "Non-matching pattern"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test output from command execution
kt_test_start "kt_assert_output_contains with command output"
command_output=$(echo "This is test output from echo")
if kt_assert_output_contains "$command_output" "test output" "Command output test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test output from grep command
kt_test_start "kt_assert_output_not_contains with grep output"
grep_output=$(echo "line1\nline2\nline3" | grep "line2")
if kt_assert_output_not_contains "$grep_output" "line4" "Grep output test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test with multiline output
kt_test_start "kt_assert_output_contains with multiline output"
multiline_output="line1
line2
line3"
if kt_assert_output_contains "$multiline_output" "line2" "Multiline test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test with empty output
kt_test_start "kt_assert_output_contains with empty output"
empty_output=""
if ! kt_assert_quiet kt_assert_output_contains "$empty_output" "content" "Empty output test"; then
    kt_test_pass "Assertion correctly failed"
else
    kt_test_fail "Assertion should have failed"
fi

# Test with special characters in output
kt_test_start "kt_assert_output_contains with special characters"
special_output="Special chars: \$@#%^&*()"
if kt_assert_output_contains "$special_output" "\$@" "Special chars test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test kt_assert_output_matches with email pattern
kt_test_start "kt_assert_output_matches with email pattern"
email_output="Contact: user@example.com"
if kt_assert_output_matches "$email_output" "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" "Email pattern"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test with very long output
kt_test_start "kt_assert_output_contains with very long output"
long_output=$(printf "Line %d\n" {1..100})
if kt_assert_output_contains "$long_output" "Line 50" "Long output test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test output with unicode characters
kt_test_start "kt_assert_output_contains with unicode characters"
unicode_output="Test with unicode: café, naïve, résumé"
if kt_assert_output_contains "$unicode_output" "café" "Unicode test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test case sensitivity
kt_test_start "kt_assert_output_contains case sensitivity"
case_output="Hello World"
if ! kt_assert_quiet kt_assert_output_contains "$case_output" "hello" "Case sensitive test"; then
    kt_test_pass "Assertion correctly failed (case sensitive)"
else
    kt_test_fail "Assertion should have failed (case sensitive)"
fi

# Test kt_assert_output_not_contains with empty search string
kt_test_start "kt_assert_output_not_contains with empty search string"
output="test content"
if ! kt_assert_quiet kt_assert_output_not_contains "$output" "" "Empty search string"; then
    kt_test_pass "Assertion correctly failed (empty string is always found)"
else
    kt_test_fail "Assertion should have failed"
fi

# Test complex pattern matching
kt_test_start "kt_assert_output_matches with complex pattern"
complex_output="Error: File not found (code: 404)"
if kt_assert_output_matches "$complex_output" "Error: .+ \(code: [0-9]+\)" "Complex pattern"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi

# Test with command substitution output
kt_test_start "kt_assert_output_contains with command substitution"
cmd_output=$(date +"%Y-%m-%d")
if kt_assert_output_contains "$cmd_output" "20" "Command substitution test"; then
    kt_test_pass "Assertion passed"
else
    kt_test_fail "Assertion failed"
fi