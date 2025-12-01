#!/bin/bash
# Integration tests: Full test framework workflow

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "IntegrationFullWorkflow" "$(dirname "$0")"

TMPDIR=$(kt_fixture_tmpdir)
INTEGRATION_DIR=$(kt_fixture_tmpdir_create "integration_tests")

# Create a comprehensive test file
kt_test_start "Create integration test file"
cat > "$INTEGRATION_DIR/001_FullIntegration.sh" << 'EOF'
#!/bin/bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/ktests/ktest.sh"
kt_test_init "FullIntegration" "$(dirname "$0")"

tmpdir=$(kt_fixture_tmpdir)
testfile=$(kt_fixture_tmpfile "integration")

kt_assert_file_exists "$testfile" "Temp file exists"
kt_assert_dir_exists "$tmpdir" "Temp dir exists"

initial_count=$TESTS_TOTAL

kt_assert_equals "test" "test" "String equality"
kt_assert_num_equals 42 42 "Numeric equality"
kt_assert_contains "hello world" "world" "String contains"
kt_assert_matches "test123" "[0-9]+" "Regex match"

if (( TESTS_TOTAL > initial_count )); then
    kt_test_pass "Test counters incremented correctly"
else
    kt_test_fail "Test counters did not increment"
fi
EOF
chmod +x "$INTEGRATION_DIR/001_FullIntegration.sh"

if [[ -f "$INTEGRATION_DIR/001_FullIntegration.sh" ]]; then
    kt_test_pass "Integration test file created"
else
    kt_test_fail "Failed to create integration test file"
fi

# Test fixture initialization with custom test name
kt_test_start "Fixture initialization with custom test ID"
test_id="CustomTestID"
kt_fixture_init_tmpdir "$test_id" "$TMPDIR/.tmp2"
if [[ -d "$TMPDIR/.tmp2" ]]; then
    kt_test_pass "Custom fixture directory created"
else
    kt_test_fail "Failed to create custom fixture directory"
fi

# Test counter reset functionality
kt_test_start "Counter reset functionality"
initial_total=$TESTS_TOTAL
kt_test_reset_counts
if (( TESTS_TOTAL == 0 && TESTS_PASSED == 0 && TESTS_FAILED == 0 )); then
    kt_test_pass "Counters reset correctly"
else
    kt_test_fail "Counter reset failed"
fi
kt_config_set "verbosity" "error"

# Test assertion result accumulation
kt_test_start "Multiple assertions accumulate counters"
initial_total=$TESTS_TOTAL
initial_passed=$TESTS_PASSED
success_count=0
for i in {1..5}; do
    if kt_assert_equals "test" "test" "Test $i" > /dev/null 2>&1; then
        ((success_count++))
        kt_test_pass "Assertion $i passed" > /dev/null 2>&1
    else
        kt_test_fail "Assertion $i failed" > /dev/null 2>&1
    fi
done
# Check if assertions incremented counters
# kt_test_start increments TESTS_TOTAL by 1
# kt_test_pass increments TESTS_PASSED by 1 for each successful assertion
# So TESTS_PASSED should increase by 5 (plus 1 for the initial kt_test_start)
if (( TESTS_PASSED >= initial_passed + 5 )); then
    kt_test_pass "Multiple assertions increment counters"
else
    kt_test_fail "Counter increment failed (initial_passed: $initial_passed, current_passed: $TESTS_PASSED, expected: $((initial_passed + 5)))"
fi


