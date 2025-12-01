#!/bin/bash
# Unit tests: Framework information and help functions

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "FrameworkInformation" "$(dirname "$0")"

# Test kt_test_info function exists and works
kt_test_start "kt_test_info function exists"
if declare -f kt_test_info > /dev/null 2>&1; then
    kt_test_pass "kt_test_info function available"
else
    kt_test_fail "kt_test_info function not found"
fi

# Test kt_test_info produces output
kt_test_start "kt_test_info produces output"
info_output=$(kt_test_info 2>&1)
if [[ -n "$info_output" ]]; then
    kt_test_pass "kt_test_info produces output"
else
    kt_test_fail "kt_test_info did not produce output"
fi

# Test kt_test_info contains version information
kt_test_start "kt_test_info contains version information"
if [[ "$info_output" == *"v$KT__FRAMEWORK_VERSION"* || "$info_output" == *"version"* ]]; then
    kt_test_pass "Version information found in output"
else
    kt_test_fail "Version information not found in output"
fi

# Test kt_test_info contains framework directory
kt_test_start "kt_test_info contains framework directory"
if [[ "$info_output" == *"$KT__FRAMEWORK_DIR"* ]]; then
    kt_test_pass "Framework directory found in output"
else
    kt_test_fail "Framework directory not found in output"
fi

# Test kt_test_info contains component versions
kt_test_start "kt_test_info contains component versions"
if [[ "$info_output" == *"v$KT__CORE_VERSION"* && "$info_output" == *"v$KT__ASSERTIONS_VERSION"* && "$info_output" == *"v$KT__FIXTURES_VERSION"* && "$info_output" == *"v$KT__RUNNER_VERSION"* ]]; then
    kt_test_pass "All component versions found in output"
else
    kt_test_fail "Component versions missing from output"
fi

# Test kt_runner_show_help function exists
kt_test_start "kt_runner_show_help function exists"
if declare -f kt_runner_show_help > /dev/null 2>&1; then
    kt_test_pass "kt_runner_show_help function available"
else
    kt_test_fail "kt_runner_show_help function not found"
fi

# Test kt_runner_show_help produces output
kt_test_start "kt_runner_show_help produces output"
help_output=$(kt_runner_show_help 2>&1)
if [[ -n "$help_output" ]]; then
    kt_test_pass "kt_runner_show_help produces output"
else
    kt_test_fail "kt_runner_show_help did not produce output"
fi

# Test kt_runner_show_help contains usage information
kt_test_start "kt_runner_show_help contains usage information"
if [[ "$help_output" == *"usage"* || "$help_output" == *"Usage"* || "$help_output" == *"USAGE"* ]]; then
    kt_test_pass "Usage information found in help output"
else
    kt_test_fail "Usage information not found in help output"
fi

# Test kt_runner_show_help contains options
kt_test_start "kt_runner_show_help contains options"
if [[ "$help_output" == *"--"* || "$help_output" == *"-m"* || "$help_output" == *"-w"* ]]; then
    kt_test_pass "Options found in help output"
else
    kt_test_fail "Options not found in help output"
fi

# Test framework version constants are accessible
kt_test_start "Framework version constants are accessible"
if [[ -n "$KT__FRAMEWORK_VERSION" && -n "$KT__CORE_VERSION" && -n "$KT__ASSERTIONS_VERSION" && -n "$KT__FIXTURES_VERSION" && -n "$KT__RUNNER_VERSION" ]]; then
    kt_test_pass "All version constants are accessible"
else
    kt_test_fail "Some version constants are missing"
fi

# Test framework directory constant is accessible
kt_test_start "Framework directory constant is accessible"
if [[ -n "$KT__FRAMEWORK_DIR" && -d "$KT__FRAMEWORK_DIR" ]]; then
    kt_test_pass "Framework directory constant is accessible and valid"
else
    kt_test_fail "Framework directory constant is invalid"
fi

# Test info output format
kt_test_start "kt_test_info output format validation"
info_lines=$(echo "$info_output" | wc -l)
if (( info_lines >= 4 )); then
    kt_test_pass "Info output has expected number of lines"
else
    kt_test_fail "Info output format unexpected"
fi

# Test help output format
kt_test_start "kt_runner_show_help output format validation"
help_lines=$(echo "$help_output" | wc -l)
if (( help_lines >= 5 )); then
    kt_test_pass "Help output has expected number of lines"
else
    kt_test_fail "Help output format unexpected"
fi

# Test that info can be called multiple times
kt_test_start "Multiple calls to kt_test_info"
info1=$(kt_test_info 2>&1)
info2=$(kt_test_info 2>&1)
if [[ "$info1" == "$info2" ]]; then
    kt_test_pass "Multiple info calls produce consistent output"
else
    kt_test_fail "Multiple info calls produce inconsistent output"
fi

# Test that help can be called multiple times
kt_test_start "Multiple calls to kt_runner_show_help"
help1=$(kt_runner_show_help 2>&1)
help2=$(kt_runner_show_help 2>&1)
if [[ "$help1" == "$help2" ]]; then
    kt_test_pass "Multiple help calls produce consistent output"
else
    kt_test_fail "Multiple help calls produce inconsistent output"
fi

# Test info with different verbosity settings
kt_test_start "kt_test_info with different verbosity"
SAVED_VERBOSITY="$VERBOSITY"
VERBOSITY="info"
info_verbose=$(kt_test_info 2>&1)
VERBOSITY="error"
info_silent=$(kt_test_info 2>&1)
VERBOSITY="$SAVED_VERBOSITY"
# Both should still produce output since these are informational functions
if [[ -n "$info_verbose" && -n "$info_silent" ]]; then
    kt_test_pass "Info function works with different verbosity settings"
else
    kt_test_fail "Info function affected by verbosity settings"
fi

# Test help with different verbosity settings
kt_test_start "kt_runner_show_help with different verbosity"
SAVED_VERBOSITY="$VERBOSITY"
VERBOSITY="info"
help_verbose=$(kt_runner_show_help 2>&1)
VERBOSITY="error"
help_silent=$(kt_runner_show_help 2>&1)
VERBOSITY="$SAVED_VERBOSITY"
# Both should still produce output since these are help functions
if [[ -n "$help_verbose" && -n "$help_silent" ]]; then
    kt_test_pass "Help function works with different verbosity settings"
else
    kt_test_fail "Help function affected by verbosity settings"
fi

# Test that info output is properly formatted
kt_test_start "Info output formatting validation"
if [[ "$info_output" =~ KK.*Testing.*Framework ]]; then
    kt_test_pass "Info output contains expected header format"
else
    kt_test_fail "Info output header format unexpected"
fi

# Test that help output contains common options
kt_test_start "Help output contains expected options"
if [[ "$help_output" == *"verbosity"* || "$help_output" == *"mode"* || "$help_output" == *"workers"* ]]; then
    kt_test_pass "Help output contains expected option descriptions"
else
    kt_test_fail "Help output missing expected option descriptions"
fi

# Test function return values
kt_test_start "Info function returns success"
kt_test_info >/dev/null 2>&1
exit_code=$?
if (( exit_code == 0 )); then
    kt_test_pass "Info function returns success exit code"
else
    kt_test_fail "Info function returned non-zero exit code"
fi

# Test help function return values
kt_test_start "Help function returns success"
kt_runner_show_help >/dev/null 2>&1
exit_code=$?
if (( exit_code == 0 )); then
    kt_test_pass "Help function returns success exit code"
else
    kt_test_fail "Help function returned non-zero exit code"
fi