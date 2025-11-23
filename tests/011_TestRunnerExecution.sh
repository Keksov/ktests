#!/bin/bash
# Unit tests: Test runner execution

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "TestRunnerExecution" "$(dirname "$0")"

INTEGRATION_TMPDIR=$(kk_fixture_tmpdir)

# Create a sample test file
kk_test_start "Create sample test file"
cat > "$INTEGRATION_TMPDIR/001_SampleTest.sh" << 'EOF'
#!/bin/bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/kktests/kk-test.sh"
KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "SampleTest" "$(dirname "$0")"
kk_test_start "Sample test assertion"
kk_assert_equals "test" "test" "Test equality"
EOF
chmod +x "$INTEGRATION_TMPDIR/001_SampleTest.sh"
if [[ -f "$INTEGRATION_TMPDIR/001_SampleTest.sh" ]]; then
    kk_test_pass "Sample test file created"
else
    kk_test_fail "Failed to create sample test file"
fi

# Test test file discovery
kk_test_start "Test file discovery"
found_files=($(kk_runner_find_tests "$INTEGRATION_TMPDIR"))
if (( ${#found_files[@]} >= 1 )); then
    kk_test_pass "Test file discovery works"
else
    kk_test_fail "No test files discovered"
fi
