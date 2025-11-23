#!/bin/bash
# Simple test that should pass

source /c/projects/kkbot/lib/kktests/kk-test.sh

KK_TEST_FILE="$(basename "${BASH_SOURCE[0]}")"

kk_test_start "Test 1 - should pass"
kk_test_pass "Test 1"

kk_test_start "Test 2 - should pass"
kk_test_pass "Test 2"

kk_test_start "Test 3 - should pass"
kk_test_pass "Test 3"

echo __COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED
