#!/bin/bash
# Unit tests: Core framework initialization and sourcing

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "CoreFrameworkInit" "$(dirname "$0")"

# Test framework version is defined
kt_test_start "Framework version constant is set"
if [[ -n "$KT__FRAMEWORK_VERSION" ]]; then
    kt_test_pass "Framework version defined"
else
    kt_test_fail "Framework version not defined"
fi

# Test core component versions
kt_test_start "Core component versions are defined"
if [[ -n "$KT__CORE_VERSION" && -n "$KT__ASSERTIONS_VERSION" && -n "$KT__RUNNER_VERSION" && -n "$KT__FIXTURES_VERSION" ]]; then
    kt_test_pass "All component versions defined"
else
    kt_test_fail "Some component versions missing"
fi

# Test framework directory is set
kt_test_start "Framework directory is properly configured"
if [[ -d "$KT__FRAMEWORK_DIR" ]]; then
    kt_test_pass "Framework directory exists and is accessible"
else
    kt_test_fail "Framework directory not found or not set"
fi

# Test color constants are defined
kt_test_start "Color constants are defined"
if [[ -n "$KT_RED" && -n "$KT_GREEN" && -n "$KT_YELLOW" && -n "$KT_BLUE" && -n "$KT_CYAN" && -n "$KT_NC" ]]; then
    kt_test_pass "All color constants defined"
else
    kt_test_fail "Some color constants missing"
fi

# Test counters exist and are numeric
kt_test_start "Test counters exist and are numeric"
if [[ -n "$TESTS_TOTAL" && -n "$TESTS_PASSED" && -n "$TESTS_FAILED" ]]; then
    kt_test_pass "Counters properly initialized as numeric values"
else
    kt_test_fail "Counters not initialized correctly"
fi

# Test default verbosity
kt_test_start "Default verbosity is set to 'error'"
if [[ "$VERBOSITY" == "error" || "$VERBOSITY" == "info" ]]; then
    kt_test_pass "Default verbosity is correct (current: '$VERBOSITY')"
else
    kt_test_fail "Default verbosity is '$VERBOSITY', expected 'error' or 'info'"
fi


