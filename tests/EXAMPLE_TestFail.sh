#!/bin/bash
# Simple test that should fail

source /c/projects/kkbot/lib/kktests/kk-test.sh

kk_test_start "Test 1 - should pass"
kk_test_pass "Test 1"

kk_test_start "Test 2 - should fail"
kk_test_fail "Test 2"

kk_test_start "Test 3 - should pass"
kk_test_pass "Test 3"


