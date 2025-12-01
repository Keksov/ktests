#!/bin/bash
# Simple test that should pass

source /c/projects/kkbot/lib/ktests/ktest.sh

kt_test_init "TestPass" "$(dirname "$0")" "$@"

kt_test_start "Test 1 - should pass"
kt_test_pass "Test 1"

kt_test_start "Test 2 - should pass"
kt_test_pass "Test 2"

kt_test_start "Test 3 - should pass"
kt_test_pass "Test 3"


