#!/bin/bash
# Unit tests: Test fixtures management

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "FixturesManagement" "$(dirname "$0")"

# Test fixture temp directory creation
kt_test_start "Fixture temp directory creation"
tmpdir=$(kt_fixture_tmpdir)
if [[ -d "$tmpdir" ]]; then
    kt_test_pass "Temp directory created"
else
    kt_test_fail "Temp directory not created"
fi

# Test fixture temp file creation
kt_test_start "Fixture temp file creation"
tmpfile=$(kt_fixture_tmpfile "testfile")
if [[ -f "$tmpfile" ]]; then
    kt_test_pass "Temp file created"
else
    kt_test_fail "Temp file not created"
fi


