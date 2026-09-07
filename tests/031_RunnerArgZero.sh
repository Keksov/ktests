#!/bin/bash
# RunnerArgZero (found_in_P4: P4-F2).
#
# The runner starts every test file as `bash -c '... source "$KT_CLEAN_FILE"'`,
# so inside the file `$0` was the literal `bash`. 119 test files derive their
# fixture id from `basename "$0"`, which made every file of a suite share
# `.tmp/bash` — and the runner executes files in PARALLEL (8 workers), so a
# neighbour's teardown deleted the directory mid-run (it ate helper scripts in
# tcustomapplication/019). The runner now passes the file path as $0.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "RunnerArgZero" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
FIX="$TMP/probe_argzero.sh"
cat > "$FIX" <<'FIXEOF'
#!/bin/bash
source "$KTEST_SOURCE_PATH"
kt_test_init "probe" "$(dirname "$0")"
kt_test_start "probe"
printf 'ARGZERO=%s\n' "$(basename "$0")"
kt_test_pass "probe"
FIXEOF

kt_test_start "the runner passes the test file path as \$0 [P4-F2]"
kt_runner_execute_single_test "$FIX" >/dev/null 2>&1
# The function leaves the file's captured output in the global output_content
# and the parsed counts line in counts_line (that is what the runner reads).
out="$output_content"
if [[ "$out" == *"ARGZERO=probe_argzero.sh"* ]]; then
    kt_test_pass "\$0 = probe_argzero.sh"
else
    kt_test_fail "got: $(printf '%s' "$out" | grep ARGZERO || echo "<no ARGZERO line>")"
fi

kt_test_start "the runner still collects the counts line"
if [[ "$counts_line" == "__COUNTS__:1:1:0" ]]; then
    kt_test_pass "counts collected"
else
    kt_test_fail "counts_line=[$counts_line]"
fi

kt_test_log "031_RunnerArgZero.sh completed"
