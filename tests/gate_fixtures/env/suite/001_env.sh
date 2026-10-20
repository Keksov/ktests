# the FIRST run (no marker next to this file) fails after a raw cygwin
# fork-failure line on stderr (as cygwin prints it, not in a test message):
# verdict ENV, re-run once by the gate; the second run passes. The marker
# lives in the fixture root (a per-test copy).
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxEnv" "$KT_TESTS_DIR" "$@"
kt_test_start "env"
if [[ -e "$KT_TESTS_DIR/.gfx_env_attempted" ]]; then
    kt_test_pass "second attempt"
else
    : > "$KT_TESTS_DIR/.gfx_env_attempted"
    echo "      0 [main] bash 4242 dofork: child -1 - CreateProcessW failed for 'C:\bin\bash.exe', errno 11" >&2
    kt_test_fail "a subshell returned garbage"
fi
kt_test_start "env ok"; kt_test_pass "env ok"
