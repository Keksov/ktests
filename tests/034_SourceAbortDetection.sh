#!/bin/bash
# SourceAbortDetection (ktests fix plan T1 / P0, 2026-10-01).
#
# A test file that dies part-way used to be reported GREEN with a silently
# lower total. Two abort classes exist (PLAN.md §1, measured on 5.2.37 and
# 5.3.9):
#   (B) an aborted top-level command — an arithmetic-expansion error, an empty
#       or negative array subscript: bash prints a diagnostic, drops the rest of
#       that ONE command and goes on with the file; source returns 0.
#   (A) the shell exits or the source stops — exit N, set -u, ${v:?}, set -e,
#       an inline syntax error, a file-scope `return N`: the counts printed by
#       kt_test_init's EXIT trap (or the wrapper) are the ones collected so far.
# The runner now prints a per-file nonce'd END marker after the `source`, and
# folds an abort into the file's counts (+1 total, +1 failed) with a
# `[FAIL] <file>: source aborted (<cause>)` line.
#
# Every abort fixture is: two passing tests, a test whose block { … } holds
# the error, one more passing test. The fixtures run through BOTH
# kt_runner_execute_sequential and kt_runner_execute_threaded; the nested
# runner's output goes to a file (its bash diagnostics must not reach THIS
# file's capture, where they would — correctly — fail this file).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SourceAbortDetection" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
FX="$TMP/fx"
mkdir -p "$FX"

# kt034_abort_fixture NAME BODY — BODY runs inside the third test's block
kt034_abort_fixture() {
    {
        printf '%s\n' \
            'kt_test_init "AbortFx" "$(dirname "$0")"' \
            'kt_test_start "one"; kt_test_pass "one"' \
            'kt_test_start "two"; kt_test_pass "two"' \
            'kt_test_start "three (the error is inside this block)"' \
            '{'
        printf '%s\n' "$2"
        printf '%s\n' \
            '    kt_test_pass "three"' \
            '}' \
            'kt_test_start "four"; kt_test_pass "four"'
    } > "$FX/$1.sh"
}

# class B — the aborted command is the whole { … } block
kt034_abort_fixture b_recursion    '    kt_rec_x=kt_rec_x; echo "$(( kt_rec_x + 1 ))"'
kt034_abort_fixture b_subscript    '    declare -A kt_h=(); kt_k=""; kt_h[$kt_k]=1'
kt034_abort_fixture b_negindex     '    declare -a kt_a=(); kt_a[-1]=x'
kt034_abort_fixture b_div0         '    echo "$(( 1 / 0 ))"'
kt034_abort_fixture b_arith_syntax '    echo "$(( 1 + ))"'
# class A — the shell exits, or the source stops
kt034_abort_fixture a_exit         '    exit 3'
kt034_abort_fixture a_set_u        '    set -u; echo "$kt_034_never_set"'
kt034_abort_fixture a_qmark        '    : "${kt_034_never_set:?}"'
kt034_abort_fixture a_set_e        '    set -e; false'
kt034_abort_fixture a_syntax       '    echo "unbalanced" )'
kt034_abort_fixture a_return       '    return 4'
# a marker-looking line with a foreign nonce does not count as the END marker
kt034_abort_fixture a_fake_end     '    echo "__KT_END_0123456789__:0:9:9:0"; exit 0'

# class B at FILE scope (no open test): only the diagnostic shows it
cat > "$FX/b_filescope_div0.sh" <<'FIXEOF'
kt_test_init "AbortFx" "$(dirname "$0")"
kt_test_start "one"; kt_test_pass "one"
echo "$(( 1 / 0 ))"
kt_test_start "two"; kt_test_pass "two"
kt_test_start "three"; kt_test_pass "three"
FIXEOF

# controls that must NOT be judged aborted
cat > "$FX/ok_lastcmd_rc1.sh" <<'FIXEOF'
kt_test_init "OkFx" "$(dirname "$0")"
kt_test_start "one"; kt_test_pass "one"
kt_test_start "two"; kt_test_pass "two"
[[ -n "" ]] && echo "never printed"
FIXEOF
cat > "$FX/ok_doublepass.sh" <<'FIXEOF'
kt_test_init "OkFx" "$(dirname "$0")"
kt_test_start "one"; kt_test_pass "one: first pass"; kt_test_pass "one: second pass"
FIXEOF
cat > "$FX/ok_plainfail.sh" <<'FIXEOF'
kt_test_init "OkFx" "$(dirname "$0")"
kt_test_start "one"; kt_test_pass "one"
kt_test_start "two"; kt_test_fail "two: an ordinary failing assertion"
FIXEOF

# name|expected runner counts t:p:f|';'-separated substrings of the [FAIL] cause line
KT034_ABORTS=(
    "b_recursion|5:3:1|test aborted mid-block;expression recursion level exceeded"
    "b_subscript|5:3:1|test aborted mid-block;bad array subscript"
    "b_negindex|5:3:1|test aborted mid-block;bad array subscript"
    "b_div0|5:3:1|test aborted mid-block;division by 0"
    "b_arith_syntax|5:3:1|test aborted mid-block;syntax error"
    "b_filescope_div0|4:3:1|division by 0"
    "a_exit|4:2:1|shell exited mid-file (child rc=3)"
    "a_set_u|4:2:1|shell exited mid-file (child rc=;unbound variable"
    "a_qmark|4:2:1|shell exited mid-file (child rc="
    "a_set_e|4:2:1|shell exited mid-file (child rc=1)"
    "a_syntax|4:2:1|source returned rc=2;test aborted mid-block;syntax error"
    "a_return|4:2:1|source returned rc=4;test aborted mid-block"
    "a_fake_end|4:2:1|shell exited mid-file (child rc=0)"
)
KT034_CONTROLS=(
    "ok_lastcmd_rc1|2:2:0|0"
    "ok_doublepass|1:2:0|0"
    "ok_plainfail|2:1:1|1"
)

# kt034_run MODE FILE... — runs the nested runner with THIS file's counters
# saved; leaves R_COUNTS (t:p:f the runner added), R_FILES (sorted failed
# basenames, space-separated) and R_OUT (the runner's output file).
KT034_N=0
kt034_run() {
    local mode="$1"; shift
    local st=$TESTS_TOTAL sp=$TESTS_PASSED sf=$TESTS_FAILED
    TESTS_TOTAL=0; TESTS_PASSED=0; TESTS_FAILED=0; FAILED_TEST_FILES=()
    KT034_N=$(( KT034_N + 1 ))
    R_OUT="$TMP/run.$KT034_N.out"
    # VERBOSITY is saved by hand, not given as a prefix assignment: the threaded
    # runner `export`s it, which makes a prefix value outlive the call.
    local sv="$VERBOSITY"
    VERBOSITY=error
    # mktemp -d of the threaded runner lands in this file's fixture dir
    TMPDIR="$TMP" WORKERS=4 "kt_runner_execute_$mode" "$@" > "$R_OUT" 2>&1
    VERBOSITY="$sv"
    R_COUNTS="$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
    R_FILES=""
    if (( ${#FAILED_TEST_FILES[@]} > 0 )); then
        R_FILES="$(printf '%s\n' "${FAILED_TEST_FILES[@]}" | sort | tr '\n' ' ')"
        R_FILES="${R_FILES% }"
    fi
    TESTS_TOTAL=$st; TESTS_PASSED=$sp; TESTS_FAILED=$sf
}

# kt034_cause_line NAME — the runner's "[FAIL] NAME.sh: source aborted (" line in R_OUT
kt034_cause_line() {
    local line
    CAUSE_LINE=""
    while IFS= read -r line; do
        if [[ "$line" == *"[FAIL] $1.sh: source aborted ("* ]]; then CAUSE_LINE="$line"; return 0; fi
    done < "$R_OUT"
    return 1
}

# ---- every abort fixture, alone, through the sequential runner -------------
for spec in "${KT034_ABORTS[@]}"; do
    IFS='|' read -r name want causes <<< "$spec"
    kt_test_start "sequential: $name is FAILED, counts $want, cause named"
    kt034_run sequential "$FX/$name.sh"
    kt034_cause_line "$name"
    missing=""
    IFS=';' read -r -a parts <<< "$causes"
    for c in "${parts[@]}"; do
        [[ "$CAUSE_LINE" == *"$c"* ]] || missing+="[$c] "
    done
    if [[ "$R_COUNTS" == "$want" && "$R_FILES" == "$name.sh" && -n "$CAUSE_LINE" && -z "$missing" ]]; then
        kt_test_pass "$name: $CAUSE_LINE"
    else
        kt_test_fail "$name: counts=$R_COUNTS (want $want) failed=[$R_FILES] cause=[$CAUSE_LINE] missing=$missing"
    fi
done

# ---- the controls stay as they were ----------------------------------------
for spec in "${KT034_CONTROLS[@]}"; do
    IFS='|' read -r name want failed <<< "$spec"
    kt_test_start "sequential: control $name keeps counts $want and gets no abort verdict"
    kt034_run sequential "$FX/$name.sh"
    want_files=""; (( failed )) && want_files="$name.sh"
    if [[ "$R_COUNTS" == "$want" && "$R_FILES" == "$want_files" ]] && ! kt034_cause_line "$name" \
       && ! grep -q '__KT_END_' "$R_OUT"; then
        kt_test_pass "$name: $R_COUNTS failed=[$R_FILES]"
    else
        kt_test_fail "$name: counts=$R_COUNTS (want $want) failed=[$R_FILES] (want [$want_files]) cause=[$CAUSE_LINE]"
    fi
done

# ---- all fixtures in one run, both execution paths -------------------------
ALL=()
want_t=0 want_p=0 want_f=0
want_files=()
for spec in "${KT034_ABORTS[@]}" "${KT034_CONTROLS[@]}"; do
    IFS='|' read -r name want _ <<< "$spec"
    ALL+=( "$FX/$name.sh" )
    IFS=':' read -r t p f <<< "$want"
    want_t=$(( want_t + t )); want_p=$(( want_p + p )); want_f=$(( want_f + f ))
    (( f > 0 )) && want_files+=( "$name.sh" )
done
WANT_FILES="$(printf '%s\n' "${want_files[@]}" | sort | tr '\n' ' ')"; WANT_FILES="${WANT_FILES% }"
WANT_COUNTS="$want_t:$want_p:$want_f"

for mode in sequential threaded; do
    kt_test_start "$mode: ${#ALL[@]} fixtures -> FAILED_TEST_FILES is exactly the ${#want_files[@]} failing ones, totals $WANT_COUNTS"
    kt034_run "$mode" "${ALL[@]}"
    if [[ "$R_FILES" == "$WANT_FILES" && "$R_COUNTS" == "$WANT_COUNTS" ]]; then
        kt_test_pass "$mode: $R_COUNTS"
    else
        kt_test_fail "$mode: counts=$R_COUNTS (want $WANT_COUNTS) failed=[$R_FILES] want=[$WANT_FILES]"
    fi

    kt_test_start "$mode: every abort is announced with its cause, no END marker leaks into the output"
    missing=""
    for spec in "${KT034_ABORTS[@]}"; do
        IFS='|' read -r name _ _ <<< "$spec"
        kt034_cause_line "$name" || missing+="$name "
    done
    if [[ -z "$missing" ]] && ! grep -q '__KT_END_[A-Za-z0-9]*__:' "$R_OUT"; then
        kt_test_pass "$mode: ${#KT034_ABORTS[@]} cause lines"
    else
        kt_test_fail "$mode: no cause line for: $missing; END lines: $(grep -c '__KT_END_' "$R_OUT")"
    fi

    kt_test_start "$mode: the bash diagnostic of a class-B abort reaches the runner output at error verbosity"
    if grep -q 'division by 0' "$R_OUT" && grep -q 'bad array subscript' "$R_OUT"; then
        kt_test_pass "$mode: diagnostics shown"
    else
        kt_test_fail "$mode: diagnostics hidden"
    fi
done
