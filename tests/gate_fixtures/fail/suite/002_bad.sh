source "$KTEST_SOURCE_PATH"
kt_test_init "GfxFailBad" "$KT_TESTS_DIR" "$@"
kt_test_start "good"; kt_test_pass "good"
kt_test_start "bad1"; kt_test_fail "gfx bad one: expected 1 got 2"
