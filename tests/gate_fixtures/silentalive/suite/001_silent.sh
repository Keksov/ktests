# waits 18 s without a word (fork-free: `read -t` on a pty of its own; no
# /dev/ptmx — FreeBSD: a sleep), then passes
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxSilentAlive" "$KT_TESTS_DIR" "$@"
kt_test_start "silent but alive"
if [[ -c /dev/ptmx ]] && exec 3<>/dev/ptmx; then
    read -r -t 18 -u 3 _ || :
else
    sleep 18
fi
kt_test_pass "silent but alive"
