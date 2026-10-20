# a failing file whose NAME has a space: the runner lists it as
# "[FAIL] 002_a b.sh" — not a failure message (review R9)
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxFailsigSpace" "$KT_TESTS_DIR" "$@"
kt_test_start "sp"; kt_test_fail "a file name with a space"
