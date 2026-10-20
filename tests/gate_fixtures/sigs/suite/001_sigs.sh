# a cell's processes keep INT and QUIT trappable (default on entry): a `&`
# start without job control would hand them SIG_IGN, which no trap can undo
# (kcl/thttpserver 006 needs its INT trap) — the gate's segment start must
# not do that, in its own runtime or across
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxSigs" "$KT_TESTS_DIR" "$@"
for s in INT QUIT; do
    kt_test_start "$s is trappable in a cell"
    trap ": gfx-$s" "$s"
    t="$(trap -p "$s")"
    if [[ "$t" == *": gfx-$s"* ]]; then kt_test_pass "$t"; else kt_test_fail "trap -p $s = [$t] (ignored on entry?)"; fi
    trap - "$s"
done
