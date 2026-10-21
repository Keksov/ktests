# hangs (fork-free: `read -t` on a pty of its own) far beyond the small
# --timeout the tests give; bounded: 25 s (no /dev/ptmx — FreeBSD: a sleep)
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxHang" "$KT_TESTS_DIR" "$@"
kt_test_start "hang"
if [[ -c /dev/ptmx ]] && exec 3<>/dev/ptmx; then
    read -r -t 25 -u 3 _ || :
else
    sleep 25
fi
kt_test_pass "hang ended by itself"
