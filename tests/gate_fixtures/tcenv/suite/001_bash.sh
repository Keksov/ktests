# the test file's own bash: the runner starts it with the `bash` on PATH,
# which timing_check put first (the target's dir)
source "$KTEST_SOURCE_PATH"
kt_test_init "TcEnvBash" "$KT_TESTS_DIR" "$@"
printf '%s\n' "${BASH_VERSION%%(*}" > "$KT_TESTS_DIR/.tc_file_bash.$$"
kt_test_start "t1"; kt_test_pass "t1"
