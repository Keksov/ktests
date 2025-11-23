#!/bin/bash
# Unit tests: Core framework initialization and sourcing

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

# Set file name for error reporting
KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"

kk_test_init "CoreFrameworkInit" "$(dirname "$0")"

# Test framework version is defined
kk_test_start "Framework version constant is set"
if [[ -n "$KK_TEST_FRAMEWORK_VERSION" ]]; then
    kk_test_pass "Framework version defined"
else
    kk_test_fail "Framework version not defined"
fi

# Test core component versions
kk_test_start "Core component versions are defined"
if [[ -n "$KK_TEST_CORE_VERSION" && -n "$KK_TEST_ASSERTIONS_VERSION" && -n "$KK_TEST_RUNNER_VERSION" && -n "$KK_TEST_FIXTURES_VERSION" ]]; then
    kk_test_pass "All component versions defined"
else
    kk_test_fail "Some component versions missing"
fi

# Test framework directory is set
kk_test_start "Framework directory is properly configured"
if [[ -d "$KK_TEST_FRAMEWORK_DIR" ]]; then
    kk_test_pass "Framework directory exists and is accessible"
else
    kk_test_fail "Framework directory not found or not set"
fi

# Test color constants are defined
kk_test_start "Color constants are defined"
if [[ -n "$KK_RED" && -n "$KK_GREEN" && -n "$KK_YELLOW" && -n "$KK_BLUE" && -n "$KK_CYAN" && -n "$KK_NC" ]]; then
    kk_test_pass "All color constants defined"
else
    kk_test_fail "Some color constants missing"
fi

# Test backward compatibility color aliases
kk_test_start "Backward compatibility color aliases are set"
if [[ "$RED" == "$KK_RED" && "$GREEN" == "$KK_GREEN" && "$YELLOW" == "$KK_YELLOW" ]]; then
    kk_test_pass "Color aliases properly aliased"
else
    kk_test_fail "Color alias backward compatibility broken"
fi

# Test counters exist and are numeric
kk_test_start "Test counters exist and are numeric"
if [[ -n "$TESTS_TOTAL" && -n "$TESTS_PASSED" && -n "$TESTS_FAILED" ]]; then
    kk_test_pass "Counters properly initialized as numeric values"
else
    kk_test_fail "Counters not initialized correctly"
fi

# Test default verbosity
kk_test_start "Default verbosity is set to 'error'"
if [[ "$VERBOSITY" == "error" || "$VERBOSITY" == "info" ]]; then
    kk_test_pass "Default verbosity is correct (current: '$VERBOSITY')"
else
    kk_test_fail "Default verbosity is '$VERBOSITY', expected 'error' or 'info'"
fi

echo __COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED
