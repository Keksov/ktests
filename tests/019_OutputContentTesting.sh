#!/bin/bash
# Unit tests: Output content assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "OutputContentTesting" "$(dirname "$0")"

# Test kk_assert_output_contains with matching content
kk_test_start "kk_assert_output_contains with matching content"
output="Hello world, this is a test"
if kk_assert_output_contains "$output" "world" "Contains test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_output_contains fails with non-matching content
kk_test_start "kk_assert_output_contains fails with non-matching content"
output="Hello world"
if ! kk_assert_output_contains "$output" "xyz" "Non-matching test"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_output_not_contains with non-matching content
kk_test_start "kk_assert_output_not_contains with non-matching content"
output="Hello world"
if kk_assert_output_not_contains "$output" "xyz" "Non-matching test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_output_not_contains fails with matching content
kk_test_start "kk_assert_output_not_contains fails with matching content"
output="Hello world"
if ! kk_assert_output_not_contains "$output" "world" "Matching test"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_output_matches with matching pattern
kk_test_start "kk_assert_output_matches with matching pattern"
output="Test123"
if kk_assert_output_matches "$output" "[0-9]+" "Pattern match"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_output_matches fails with non-matching pattern
kk_test_start "kk_assert_output_matches fails with non-matching pattern"
output="TestABC"
if ! kk_assert_output_matches "$output" "[0-9]+" "Non-matching pattern"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test output from command execution
kk_test_start "kk_assert_output_contains with command output"
command_output=$(echo "This is test output from echo")
if kk_assert_output_contains "$command_output" "test output" "Command output test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test output from grep command
kk_test_start "kk_assert_output_not_contains with grep output"
grep_output=$(echo "line1\nline2\nline3" | grep "line2")
if kk_assert_output_not_contains "$grep_output" "line4" "Grep output test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test with multiline output
kk_test_start "kk_assert_output_contains with multiline output"
multiline_output="line1
line2
line3"
if kk_assert_output_contains "$multiline_output" "line2" "Multiline test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test with empty output
kk_test_start "kk_assert_output_contains with empty output"
empty_output=""
if ! kk_assert_output_contains "$empty_output" "content" "Empty output test"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test with special characters in output
kk_test_start "kk_assert_output_contains with special characters"
special_output="Special chars: \$@#%^&*()"
if kk_assert_output_contains "$special_output" "\$@" "Special chars test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_output_matches with email pattern
kk_test_start "kk_assert_output_matches with email pattern"
email_output="Contact: user@example.com"
if kk_assert_output_matches "$email_output" "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" "Email pattern"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test with very long output
kk_test_start "kk_assert_output_contains with very long output"
long_output=$(printf "Line %d\n" {1..100})
if kk_assert_output_contains "$long_output" "Line 50" "Long output test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test output with unicode characters
kk_test_start "kk_assert_output_contains with unicode characters"
unicode_output="Test with unicode: café, naïve, résumé"
if kk_assert_output_contains "$unicode_output" "café" "Unicode test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test case sensitivity
kk_test_start "kk_assert_output_contains case sensitivity"
case_output="Hello World"
if ! kk_assert_output_contains "$case_output" "hello" "Case sensitive test"; then
    kk_test_pass "Assertion correctly failed (case sensitive)"
else
    kk_test_fail "Assertion should have failed (case sensitive)"
fi

# Test kk_assert_output_not_contains with empty search string
kk_test_start "kk_assert_output_not_contains with empty search string"
output="test content"
if kk_assert_output_not_contains "$output" "" "Empty search string"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test complex pattern matching
kk_test_start "kk_assert_output_matches with complex pattern"
complex_output="Error: File not found (code: 404)"
if kk_assert_output_matches "$complex_output" "Error: .+ \(code: [0-9]+\)" "Complex pattern"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test with command substitution output
kk_test_start "kk_assert_output_contains with command substitution"
cmd_output=$(date +"%Y-%m-%d")
if kk_assert_output_contains "$cmd_output" "20" "Command substitution test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi