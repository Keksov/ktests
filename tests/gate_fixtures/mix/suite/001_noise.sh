# gate fixture "mix" (review round 1, R2): this file fails after a raw cygwin
# fork-failure line (the machine) ...
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxMixNoise" "$KT_TESTS_DIR" "$@"
kt_test_start "noise"
echo "      0 [main] bash 4242 dofork: child -1 - CreateProcessW failed for 'C:\bin\bash.exe', errno 11" >&2
kt_test_fail "a subshell returned garbage"
