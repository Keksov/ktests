source "$KTEST_SOURCE_PATH"
kt_test_init "GfxFailWorse" "$KT_TESTS_DIR" "$@"
kt_test_start "bad2"; kt_test_fail "gfx bad two: expected a got b"
kt_test_start "bad3"; kt_test_fail "gfx bad three: expected x got y"
