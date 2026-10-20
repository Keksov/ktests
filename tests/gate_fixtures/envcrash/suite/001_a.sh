source "$KTEST_SOURCE_PATH"
kt_test_init "GfxPassA" "$KT_TESTS_DIR" "$@"
kt_test_start "a1"; kt_test_pass "a1"
kt_test_start "a2"; kt_test_pass "a2"
