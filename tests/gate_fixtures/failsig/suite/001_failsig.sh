# a real, deterministic failure whose MESSAGE mentions a fork failure (ktests
# 035 has such messages): a FAIL of the test, never ENV
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxFailsig" "$KT_TESTS_DIR" "$@"
kt_test_start "msg"; kt_test_fail "the retry rule must see: bash: fork: retry: Resource temporarily unavailable"
kt_test_start "ml"; kt_test_fail "a multi-line message, line 1
line 2 of it
line 3 of it"
