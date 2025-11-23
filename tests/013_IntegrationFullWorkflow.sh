#!/bin/bash
# Integration tests: Full test framework workflow

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "IntegrationFullWorkflow" "$(dirname "$0")"

TMPDIR=$(kk_fixture_tmpdir)
INTEGRATION_DIR=$(kk_fixture_tmpdir_create "integration_tests")

# Create a comprehensive test file
kk_test_start "Create integration test file"
cat > "$INTEGRATION_DIR/001_FullIntegration.sh" << 'EOF'
#!/bin/bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/kktests/kk-test.sh"
KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "FullIntegration" "$(dirname "$0")"

tmpdir=$(kk_fixture_tmpdir)
testfile=$(kk_fixture_tmpfile "integration")

kk_assert_file_exists "$testfile" "Temp file exists"
kk_assert_dir_exists "$tmpdir" "Temp dir exists"

initial_count=$TESTS_TOTAL

kk_assert_equals "test" "test" "String equality"
kk_assert_num_equals 42 42 "Numeric equality"
kk_assert_contains "hello world" "world" "String contains"
kk_assert_matches "test123" "[0-9]+" "Regex match"

if (( TESTS_TOTAL > initial_count )); then
    kk_test_pass "Test counters incremented correctly"
else
    kk_test_fail "Test counters did not increment"
fi
EOF
chmod +x "$INTEGRATION_DIR/001_FullIntegration.sh"

if [[ -f "$INTEGRATION_DIR/001_FullIntegration.sh" ]]; then
    kk_test_pass "Integration test file created"
else
    kk_test_fail "Failed to create integration test file"
fi

# Test fixture initialization with custom test name
kk_test_start "Fixture initialization with custom test ID"
test_id="CustomTestID"
kk_fixture_init_tmpdir "$test_id" "$TMPDIR/.tmp2"
if [[ -d "$TMPDIR/.tmp2" ]]; then
    kk_test_pass "Custom fixture directory created"
else
    kk_test_fail "Failed to create custom fixture directory"
fi

# Test counter reset functionality
kk_test_start "Counter reset functionality"
initial_total=$TESTS_TOTAL
kk_test_reset_counts
if (( TESTS_TOTAL == 0 && TESTS_PASSED == 0 && TESTS_FAILED == 0 )); then
    kk_test_pass "Counters reset correctly"
else
    kk_test_fail "Counter reset failed"
fi
kk_config_set "verbosity" "error"

# Test assertion result accumulation
kk_test_start "Multiple assertions accumulate counters"
initial_total=$TESTS_TOTAL
initial_passed=$TESTS_PASSED
for i in {1..5}; do
    kk_assert_equals "test" "test" "Test $i" > /dev/null 2>&1
done
# Check if assertions incremented counters
# kk_test_start increments TESTS_TOTAL by 1
# kk_assert_equals increments TESTS_PASSED by 1 for each successful assertion
# So TESTS_PASSED should increase by 5
if (( TESTS_PASSED >= initial_passed + 5 )); then
    kk_test_pass "Multiple assertions increment counters"
else
    kk_test_fail "Counter increment failed (initial_passed: $initial_passed, current_passed: $TESTS_PASSED, expected: $((initial_passed + 5)))"
fi
