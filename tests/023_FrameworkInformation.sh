#!/bin/bash
# Unit tests: Framework information and help functions

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "FrameworkInformation" "$(dirname "$0")"

# Test kk_test_info function exists and works
kk_test_start "kk_test_info function exists"
if declare -f kk_test_info > /dev/null 2>&1; then
    kk_test_pass "kk_test_info function available"
else
    kk_test_fail "kk_test_info function not found"
fi

# Test kk_test_info produces output
kk_test_start "kk_test_info produces output"
info_output=$(kk_test_info 2>&1)
if [[ -n "$info_output" ]]; then
    kk_test_pass "kk_test_info produces output"
else
    kk_test_fail "kk_test_info did not produce output"
fi

# Test kk_test_info contains version information
kk_test_start "kk_test_info contains version information"
if [[ "$info_output" == *"v$KK_TEST_FRAMEWORK_VERSION"* || "$info_output" == *"version"* ]]; then
    kk_test_pass "Version information found in output"
else
    kk_test_fail "Version information not found in output"
fi

# Test kk_test_info contains framework directory
kk_test_start "kk_test_info contains framework directory"
if [[ "$info_output" == *"$KK_TEST_FRAMEWORK_DIR"* ]]; then
    kk_test_pass "Framework directory found in output"
else
    kk_test_fail "Framework directory not found in output"
fi

# Test kk_test_info contains component versions
kk_test_start "kk_test_info contains component versions"
if [[ "$info_output" == *"v$KK_TEST_CORE_VERSION"* && "$info_output" == *"v$KK_TEST_ASSERTIONS_VERSION"* && "$info_output" == *"v$KK_TEST_FIXTURES_VERSION"* && "$info_output" == *"v$KK_TEST_RUNNER_VERSION"* ]]; then
    kk_test_pass "All component versions found in output"
else
    kk_test_fail "Component versions missing from output"
fi

# Test kk_runner_show_help function exists
kk_test_start "kk_runner_show_help function exists"
if declare -f kk_runner_show_help > /dev/null 2>&1; then
    kk_test_pass "kk_runner_show_help function available"
else
    kk_test_fail "kk_runner_show_help function not found"
fi

# Test kk_runner_show_help produces output
kk_test_start "kk_runner_show_help produces output"
help_output=$(kk_runner_show_help 2>&1)
if [[ -n "$help_output" ]]; then
    kk_test_pass "kk_runner_show_help produces output"
else
    kk_test_fail "kk_runner_show_help did not produce output"
fi

# Test kk_runner_show_help contains usage information
kk_test_start "kk_runner_show_help contains usage information"
if [[ "$help_output" == *"usage"* || "$help_output" == *"Usage"* || "$help_output" == *"USAGE"* ]]; then
    kk_test_pass "Usage information found in help output"
else
    kk_test_fail "Usage information not found in help output"
fi

# Test kk_runner_show_help contains options
kk_test_start "kk_runner_show_help contains options"
if [[ "$help_output" == *"--"* || "$help_output" == *"-m"* || "$help_output" == *"-w"* ]]; then
    kk_test_pass "Options found in help output"
else
    kk_test_fail "Options not found in help output"
fi

# Test framework version constants are accessible
kk_test_start "Framework version constants are accessible"
if [[ -n "$KK_TEST_FRAMEWORK_VERSION" && -n "$KK_TEST_CORE_VERSION" && -n "$KK_TEST_ASSERTIONS_VERSION" && -n "$KK_TEST_FIXTURES_VERSION" && -n "$KK_TEST_RUNNER_VERSION" ]]; then
    kk_test_pass "All version constants are accessible"
else
    kk_test_fail "Some version constants are missing"
fi

# Test framework directory constant is accessible
kk_test_start "Framework directory constant is accessible"
if [[ -n "$KK_TEST_FRAMEWORK_DIR" && -d "$KK_TEST_FRAMEWORK_DIR" ]]; then
    kk_test_pass "Framework directory constant is accessible and valid"
else
    kk_test_fail "Framework directory constant is invalid"
fi

# Test info output format
kk_test_start "kk_test_info output format validation"
info_lines=$(echo "$info_output" | wc -l)
if (( info_lines >= 4 )); then
    kk_test_pass "Info output has expected number of lines"
else
    kk_test_fail "Info output format unexpected"
fi

# Test help output format
kk_test_start "kk_runner_show_help output format validation"
help_lines=$(echo "$help_output" | wc -l)
if (( help_lines >= 5 )); then
    kk_test_pass "Help output has expected number of lines"
else
    kk_test_fail "Help output format unexpected"
fi

# Test that info can be called multiple times
kk_test_start "Multiple calls to kk_test_info"
info1=$(kk_test_info 2>&1)
info2=$(kk_test_info 2>&1)
if [[ "$info1" == "$info2" ]]; then
    kk_test_pass "Multiple info calls produce consistent output"
else
    kk_test_fail "Multiple info calls produce inconsistent output"
fi

# Test that help can be called multiple times
kk_test_start "Multiple calls to kk_runner_show_help"
help1=$(kk_runner_show_help 2>&1)
help2=$(kk_runner_show_help 2>&1)
if [[ "$help1" == "$help2" ]]; then
    kk_test_pass "Multiple help calls produce consistent output"
else
    kk_test_fail "Multiple help calls produce inconsistent output"
fi

# Test info with different verbosity settings
kk_test_start "kk_test_info with different verbosity"
SAVED_VERBOSITY="$VERBOSITY"
VERBOSITY="info"
info_verbose=$(kk_test_info 2>&1)
VERBOSITY="error"
info_silent=$(kk_test_info 2>&1)
VERBOSITY="$SAVED_VERBOSITY"
# Both should still produce output since these are informational functions
if [[ -n "$info_verbose" && -n "$info_silent" ]]; then
    kk_test_pass "Info function works with different verbosity settings"
else
    kk_test_fail "Info function affected by verbosity settings"
fi

# Test help with different verbosity settings
kk_test_start "kk_runner_show_help with different verbosity"
SAVED_VERBOSITY="$VERBOSITY"
VERBOSITY="info"
help_verbose=$(kk_runner_show_help 2>&1)
VERBOSITY="error"
help_silent=$(kk_runner_show_help 2>&1)
VERBOSITY="$SAVED_VERBOSITY"
# Both should still produce output since these are help functions
if [[ -n "$help_verbose" && -n "$help_silent" ]]; then
    kk_test_pass "Help function works with different verbosity settings"
else
    kk_test_fail "Help function affected by verbosity settings"
fi

# Test that info output is properly formatted
kk_test_start "Info output formatting validation"
if [[ "$info_output" =~ KK.*Testing.*Framework ]]; then
    kk_test_pass "Info output contains expected header format"
else
    kk_test_fail "Info output header format unexpected"
fi

# Test that help output contains common options
kk_test_start "Help output contains expected options"
if [[ "$help_output" == *"verbosity"* || "$help_output" == *"mode"* || "$help_output" == *"workers"* ]]; then
    kk_test_pass "Help output contains expected option descriptions"
else
    kk_test_fail "Help output missing expected option descriptions"
fi

# Test function return values
kk_test_start "Info function returns success"
kk_test_info >/dev/null 2>&1
exit_code=$?
if (( exit_code == 0 )); then
    kk_test_pass "Info function returns success exit code"
else
    kk_test_fail "Info function returned non-zero exit code"
fi

# Test help function return values
kk_test_start "Help function returns success"
kk_runner_show_help >/dev/null 2>&1
exit_code=$?
if (( exit_code == 0 )); then
    kk_test_pass "Help function returns success exit code"
else
    kk_test_fail "Help function returned non-zero exit code"
fi