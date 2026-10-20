# hangs (fork-free: `read -t` on a pty of its own) far beyond the small
# --timeout the tests give; bounded: 25 s
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxHang" "$KT_TESTS_DIR" "$@"
kt_test_start "hang"
exec 3<>/dev/ptmx 2>/dev/null || exec 3</dev/null
read -r -t 25 -u 3 _ || :
kt_test_pass "hang ended by itself"
