# ... and this one is a REAL failure: the cell must be FAIL, never ENV
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxMixReal" "$KT_TESTS_DIR" "$@"
kt_test_start "real"
kt_test_fail "a REAL regression: expected 1 got 2"
