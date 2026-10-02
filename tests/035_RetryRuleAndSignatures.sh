#!/bin/bash
# RetryRuleAndSignatures (ktests fix plan T1 / P0, 2026-10-01).
#
# The runner re-runs a test file ONLY when it left no END marker, no counts
# line, AND its capture is empty or shows a cygwin fork failure (the ENV
# signatures) — a transient worker death. A file that printed something and
# then died without counts is deterministic: it is FAILED at once, not run
# three times. The fork-failure signatures are ONE definition, shared by the
# runner and tools/timing_check.sh. The END marker never reaches the printed
# output, and a bash fatal diagnostic always does.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "RetryRuleAndSignatures" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
FX="$TMP/fx"
mkdir -p "$FX"

# kt035_fixture NAME BODY — the fixture appends one byte to NAME.cnt per attempt
kt035_fixture() {
    {
        printf 'printf x >> %q\n' "$FX/$1.cnt"
        printf '%s\n' "$2"
    } > "$FX/$1.sh"
}

kt035_fixture empty_nocounts  'exit 1'
kt035_fixture output_nocounts 'echo "some output, then death without counts"; exit 1'
kt035_fixture envsig_nocounts 'echo "      0 [main] bash 4242 dofork: child -1 - CreateProcessW failed, errno 11"; exit 1'
kt035_fixture counts_noend    'kt_test_init "RetryFx" "$(dirname "$0")"
kt_test_start "one"; kt_test_pass "one"
exit 0'
# dies silently on its first attempt only — the transient death the retry is for
kt035_fixture transient       's="$(< "${BASH_SOURCE[0]%.sh}.cnt")"
(( ${#s} < 2 )) && exit 1
kt_test_init "RetryFx" "$(dirname "$0")"
kt_test_start "one"; kt_test_pass "one"'

# name|attempts|expected counts_line|aborted (0/1)
KT035_CASES=(
    "empty_nocounts|3|__COUNTS__:1:0:1|1"
    "output_nocounts|1|__COUNTS__:1:0:1|1"
    "envsig_nocounts|3|__COUNTS__:1:0:1|1"
    "counts_noend|1|__COUNTS__:2:1:1|1"
    "transient|2|__COUNTS__:1:1:0|0"
)

for spec in "${KT035_CASES[@]}"; do
    IFS='|' read -r name attempts want aborted <<< "$spec"
    kt_test_start "retry rule: $name runs $attempts time(s), counts $want"
    rm -f "$FX/$name.cnt"
    kt_runner_execute_single_test "$FX/$name.sh" >/dev/null 2>&1
    got_attempts="$(< "$FX/$name.cnt")"; got_attempts=${#got_attempts}
    has_cause=0
    [[ "$output_content" == *"[FAIL] $name.sh: source aborted ("* ]] && has_cause=1
    if [[ "$got_attempts" == "$attempts" && "$counts_line" == "$want" && "$has_cause" == "$aborted" ]]; then
        kt_test_pass "$name: $got_attempts attempt(s), $counts_line"
    else
        kt_test_fail "$name: attempts=$got_attempts (want $attempts) counts=[$counts_line] (want $want) cause-line=$has_cause (want $aborted)"
    fi
done

# ---- one shared ENV signature definition -------------------------------------
kt_test_start "KT_ENV_FORK_FAILURE_RE is defined and matches every documented fork-failure signature"
sigs=( "dofork: child -1" "child_copy: cygheap read copy failed" "cygheap read copy failed"
       "status 0xC000012D" "0xC0000142" "fork: Resource temporarily unavailable" "fork: retry: No child processes" )
bad=""
if [[ -n "${KT_ENV_FORK_FAILURE_RE:-}" ]]; then
    for s in "${sigs[@]}"; do [[ "$s" =~ $KT_ENV_FORK_FAILURE_RE ]] || bad+="[$s] "; done
    for s in "[FAIL] some test" "__COUNTS__:1:1:0" "fork() is fine"; do
        [[ "$s" =~ $KT_ENV_FORK_FAILURE_RE ]] && bad+="(false hit: $s) "
    done
else
    bad="undefined"
fi
[[ -z "$bad" ]] && kt_test_pass "all ${#sigs[@]} signatures" || kt_test_fail "$bad"

kt_test_start "the signature list has ONE definition: no other ktests script carries the regex literal"
holders=()
for f in "$KTESTS_LIB_DIR"/*.sh "$KTESTS_LIB_DIR"/tools/*.sh; do
    # a non-comment line holding two of the signatures is a definition
    if grep -v '^[[:space:]]*#' "$f" | grep -q 'dofork:.*child_copy:'; then holders+=( "${f##*/}" ); fi
done
if [[ "${holders[*]}" == "ktest_env_signatures.sh" ]] \
   && grep -q 'ktest_env_signatures\.sh' "$KTESTS_LIB_DIR/tools/timing_check.sh" \
   && grep -q 'ktest_env_signatures\.sh' "$KTESTS_LIB_DIR/ktest_runner.sh"; then
    kt_test_pass "defined in ${holders[*]}, used by ktest_runner.sh and tools/timing_check.sh"
else
    kt_test_fail "definitions in: [${holders[*]}]"
fi

# ---- output: END markers hidden, bash diagnostics shown ----------------------
kt_test_start "kt_runner_print_output_without_counts drops END markers, also one glued to a line without newline"
out="$(kt_runner_print_output_without_counts $'line one\n__KT_END_abc123__:0:1:1:0:0\ntail-without-newline__KT_END_abc123__:0:1:1:0:x\n__COUNTS__:1:1:0')"
if [[ "$out" == $'line one\ntail-without-newline' ]]; then
    kt_test_pass "markers dropped"
else
    kt_test_fail "got [$out]"
fi

kt_test_start "kt_runner_filter_output at error verbosity keeps a bash fatal diagnostic, hides noise and END markers"
diag='/x/y/001_Foo.sh: line 7: 1/0: division by 0 (error token is "0")'
out="$(VERBOSITY=error kt_runner_filter_output $'noise\n'"$diag"$'\n__KT_END_abc123__:0:1:1:0:1\n__COUNTS__:1:1:0' "__COUNTS__:1:1:0" 0)"
if [[ "$out" == "$diag" ]]; then
    kt_test_pass "only the diagnostic"
else
    kt_test_fail "got [$out]"
fi

kt_test_start "a file whose last output has no newline is still judged complete (END marker found mid-line)"
cat > "$FX/glued.sh" <<'FIXEOF'
kt_test_init "RetryFx" "$(dirname "$0")"
kt_test_start "one"; kt_test_pass "one"
printf 'no newline at the end'
FIXEOF
kt_runner_execute_single_test "$FX/glued.sh" >/dev/null 2>&1
if [[ "$counts_line" == "__COUNTS__:1:1:0" && "$output_content" != *"source aborted"* ]]; then
    kt_test_pass "$counts_line"
else
    kt_test_fail "counts=[$counts_line] output=[$output_content]"
fi
