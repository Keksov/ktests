# never runs: the wrapper dies first
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxCrash" "$KT_TESTS_DIR" "$@"
kt_test_start "never"; kt_test_pass "never"
