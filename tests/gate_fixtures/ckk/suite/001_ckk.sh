# records the cell's KKLASS_CKK_DIR in a file IN that dir: with --warm the
# cells of a segment share one dir (it collects one line per cell), without
# it every cell has its own (one line)
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxCkk" "$KT_TESTS_DIR" "$@"
kt_test_start "ckk dir"
if [[ -n "${KKLASS_CKK_DIR:-}" && -d "$KKLASS_CKK_DIR" ]]; then
    printf '%s %s\n' "$KKLASS_CKK_DIR" "$TMPDIR" >> "$KKLASS_CKK_DIR/cells.log"
    kt_test_pass "ckk dir $KKLASS_CKK_DIR"
else
    kt_test_fail "no KKLASS_CKK_DIR dir: [${KKLASS_CKK_DIR:-}]"
fi
