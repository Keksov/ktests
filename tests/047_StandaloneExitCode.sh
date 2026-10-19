#!/bin/bash
# StandaloneExitCode (ktests round 6, S3; owner decision 2026-10-18). A test
# file run standalone (`bash tests/X.sh`) exited 0 even with a [FAIL] — only
# the runner judged it (critic r6 info). Now its exit status reflects the
# verdict: 1 when any test failed and the file would have exited 0; a
# non-zero status of its own is kept. The runner keeps judging by its counts
# line. Each case compares the standalone rc with the runner's verdict.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "StandaloneExitCode" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
FX="$TMP/fx"
mkdir -p "$FX/tests"
printf 'source %q\n' "$LIB/ktest.sh" > "$FX/ktest_source.sh"

# kt047_file NAME BODY — a test file NAME.sh with BODY after kt_test_init
kt047_file() {
    printf '%s\n' 'source "$(dirname "$0")/../ktest_source.sh"' \
        'kt_test_init "Ec" "$(dirname "$0")"' "$2" > "$FX/tests/$1.sh"
}
kt047_file allpass   'kt_test_start a; kt_test_pass a
kt_test_start b; kt_test_pass b'
kt047_file failfirst 'kt_test_start a; kt_test_fail a
kt_test_start b; kt_test_pass b'
kt047_file faillast  'kt_test_start a; kt_test_pass a
kt_test_start b; kt_test_fail b'
kt047_file failexit0 'kt_test_start a; kt_test_fail a
exit 0'
kt047_file ownexit3  'kt_test_start a; kt_test_pass a
exit 3'

# name | want standalone rc | want runner verdict (pass/fail)
CASES=( "allpass|0|pass" "failfirst|1|fail" "faillast|1|fail" "failexit0|1|fail" "ownexit3|3|fail" )
for spec in "${CASES[@]}"; do
    IFS='|' read -r name wrc wv <<< "$spec"
    kt_test_start "standalone rc and runner verdict agree: $name (rc $wrc, $wv) [S3]"
    ( cd "$FX" && env -u KK_OUTPUT_COUNTS -u KT_TESTS_DIR -u KTEST_SOURCE_PATH -u VERBOSITY -u _KTEST_QUIET_MODE -u _KT_ASSERT_QUIET_MODE bash "tests/$name.sh" ) > "$TMP/$name.out" 2>&1
    rc=$?
    st=$TESTS_TOTAL sp=$TESTS_PASSED sf=$TESTS_FAILED
    kt_runner_execute_single_test "$FX/tests/$name.sh" >/dev/null 2>&1
    rcounts="$count_total:$count_passed:$count_failed"
    TESTS_TOTAL=$st; TESTS_PASSED=$sp; TESTS_FAILED=$sf
    v=pass; [[ "$count_failed" =~ ^[0-9]+$ ]] && (( count_failed > 0 )) && v=fail
    if [[ "$rc" == "$wrc" && "$v" == "$wv" ]]; then
        kt_test_pass "standalone rc $rc, runner $v ($rcounts)"
    else
        kt_test_fail "standalone rc $rc (want $wrc), runner $v (want $wv, $rcounts) | $(tr '\n' ' ' < "$TMP/$name.out")"
    fi
done

kt_test_log "047_StandaloneExitCode.sh completed"
