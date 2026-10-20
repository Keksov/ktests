#!/usr/bin/env bash
# Unit tests: Test runner execution

# Only source if framework not already loaded
if [[ -z "$_KTEST_SOURCED" ]]; then
    source "$(dirname "$0")/../ktest_source.sh" || source "$KTEST_SOURCE_PATH" || exit 1
fi

kt_test_init "TestRunnerExecution" "$(dirname "$0")"

INTEGRATION_TMPDIR=$(kt_fixture_tmpdir)

# Create a sample test file
kt_test_start "Create sample test file"
cat > "$INTEGRATION_TMPDIR/001_SampleTest.sh" << 'EOF'
#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/ktests/ktest.sh"
kt_test_init "SampleTest" "$(dirname "$0")"
kt_test_start "Sample test assertion"
kt_assert_equals "test" "test" "Test equality"
EOF
chmod +x "$INTEGRATION_TMPDIR/001_SampleTest.sh"
if [[ -f "$INTEGRATION_TMPDIR/001_SampleTest.sh" ]]; then
    kt_test_pass "Sample test file created"
else
    kt_test_fail "Failed to create sample test file"
fi

# Test test file discovery
kt_test_start "Test file discovery"
found_files=($(kt_runner_find_tests "$INTEGRATION_TMPDIR"))
if (( ${#found_files[@]} >= 1 )); then
    kt_test_pass "Test file discovery works"
else
    kt_test_fail "No test files discovered"
fi
