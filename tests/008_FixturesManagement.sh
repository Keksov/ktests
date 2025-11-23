#!/bin/bash
# Unit tests: Test fixtures management

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"
kk_test_init "FixturesManagement" "$(dirname "$0")"

# Test fixture temp directory creation
kk_test_start "Fixture temp directory creation"
tmpdir=$(kk_fixture_tmpdir)
if [[ -d "$tmpdir" ]]; then
    kk_test_pass "Temp directory created"
else
    kk_test_fail "Temp directory not created"
fi

# Test fixture temp file creation
kk_test_start "Fixture temp file creation"
tmpfile=$(kk_fixture_tmpfile "testfile")
if [[ -f "$tmpfile" ]]; then
    kk_test_pass "Temp file created"
else
    kk_test_fail "Temp file not created"
fi

echo __COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED
