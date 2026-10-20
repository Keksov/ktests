# fails on its FIRST run, passes on every later one: the marker lives in the
# fixture's own copy (KT_TESTS_DIR = ROOT/ID/tests, made per test by
# mkroot.sh in the test's private tmp) — never in the cell sandbox, which is
# fresh for every attempt; two tests never share a root
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxFlaky" "$KT_TESTS_DIR" "$@"
kt_test_start "flaky"
if [[ -e "$KT_TESTS_DIR/.gfx_flaky_ran" ]]; then
    kt_test_pass "a later run"
else
    : > "$KT_TESTS_DIR/.gfx_flaky_ran"
    kt_test_fail "gfx flaky: the first run fails"
fi
