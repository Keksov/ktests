source "$KTEST_SOURCE_PATH"
kt_test_init "GfxFlakyOk" "$KT_TESTS_DIR" "$@"
kt_test_start "ok1"; kt_test_pass "ok1"
kt_test_start "ok2"; kt_test_pass "ok2"
