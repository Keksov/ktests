# waits for its test (051, the host-suspend case): writes TMPDIR/gfx-nap.ready,
# then naps until TMPDIR/gfx-nap.go exists (fork-free: `read -t` on a pty of
# its own; no /dev/ptmx — FreeBSD: a sleep); bounded: 60 s, then it fails
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxNap" "$KT_TESTS_DIR" "$@"
kt_test_start "nap until the test says go"
__gfx_t="${TMPDIR:-/tmp}"
: > "$__gfx_t/gfx-nap.ready"
__gfx_fd=""
[[ -c /dev/ptmx ]] && exec 3<>/dev/ptmx && __gfx_fd=3
for (( __gfx_i = 0; __gfx_i < 300; __gfx_i++ )); do
    [[ -e "$__gfx_t/gfx-nap.go" ]] && break
    if [[ -n "$__gfx_fd" ]]; then read -r -t 0.2 -u 3 _ || :; else sleep 0.2; fi
done
if [[ -e "$__gfx_t/gfx-nap.go" ]]; then kt_test_pass "go after ~$(( __gfx_i / 5 ))s"; else kt_test_fail "no go in 60 s"; fi
