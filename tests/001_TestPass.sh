#!/usr/bin/env bash
# Simple test that should pass

# Only source if framework not already loaded
if [[ -z "$_KTEST_SOURCED" ]]; then
    source "$(dirname "$0")/../ktest_source.sh" || source "$KTEST_SOURCE_PATH" || exit 1
fi

kt_test_init "TestPass" "$(dirname "$0")" "$@"

kt_test_start "Test 1 - should pass"
kt_test_pass "Test 1"

kt_test_start "Test 2 - should pass"
kt_test_pass "Test 2"

kt_test_start "Test 3 - should pass"
kt_test_pass "Test 3"


