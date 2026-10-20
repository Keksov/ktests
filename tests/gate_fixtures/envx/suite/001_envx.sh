# fails after a raw cygwin fork-failure line on EVERY run — ENV after the retry
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxEnvx" "$KT_TESTS_DIR" "$@"
kt_test_start "envx"
echo "      0 [main] bash 4242 dofork: child -1 - CreateProcessW failed for 'C:\bin\bash.exe', errno 11" >&2
kt_test_fail "a subshell returned garbage"
