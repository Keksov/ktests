source "$KTEST_SOURCE_PATH"
kt_test_init "GfxWarn" "$KT_TESTS_DIR" "$@"
kt_test_start "w"; echo "[WARN] gfx: a warning line"; kt_test_pass "w"
