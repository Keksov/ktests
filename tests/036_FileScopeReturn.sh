#!/bin/bash
# FileScopeReturn (ktests round 3, T2 / DT2, 2026-10-02).
#
# A file-scope `return 1` BETWEEN tests ends the file early with source rc 1 —
# the same rc a file whose last command is false-y legitimately gives — and no
# test is open, so P0 reported it green with a lower total (P0 deviation D1).
# The wrapper now sets a RETURN trap around `source FILE` that records `$?` at
# trap entry when it fires for the OUTER source (${#BASH_SOURCE[@]} == 0;
# nested sources fire at depth 1). A file that falls off its end gives trap
# status == source rc; a `return N` gives the status of the command before it.
# Verdict "file-scope return" iff the trap fired at depth 0, source rc < 2
# (rc >= 2 is already a verdict) and trap status != source rc.
#
# Documented residual (no verdict, pinned below): `cmd || return N` whose
# prior status is N, a bare `return`, and a file that installs its own RETURN
# trap (it replaces the runner's, which is then blind).
#
# Every fixture runs through kt_runner_execute_sequential AND
# kt_runner_execute_threaded; the nested runner's output goes to a file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "FileScopeReturn" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
FX="$TMP/fx"
mkdir -p "$FX"

# kt036_fixture NAME BODY — test "one", BODY at file scope, test "two"
kt036_fixture() {
    {
        printf '%s\n' \
            'kt_test_init "RetFx" "$(dirname "$0")"' \
            'kt_test_start "one"; kt_test_pass "one"'
        printf '%s\n' "$2"
        printf '%s\n' 'kt_test_start "two"; kt_test_pass "two"'
    } > "$FX/$1.sh"
}

# kt036_fixture_tail NAME BODY — tests "one" and "two", then BODY as the LAST command(s)
kt036_fixture_tail() {
    {
        printf '%s\n' \
            'kt_test_init "RetFx" "$(dirname "$0")"' \
            'kt_test_start "one"; kt_test_pass "one"' \
            'kt_test_start "two"; kt_test_pass "two"'
        printf '%s\n' "$2"
    } > "$FX/$1.sh"
}

# libraries a fixture sources: an include guard that returns, and one that returns 1
cat > "$FX/lib_guard.sh" <<'FIXEOF'
if [[ -n "${_KT036_LIBG:-}" ]]; then
    return
fi
_KT036_LIBG=1
FIXEOF
cat > "$FX/lib_ret1.sh" <<'FIXEOF'
return 1
FIXEOF

# ---- T2: a file-scope return between tests is FAILED -------------------------
kt036_fixture r_return1       'return 1'
kt036_fixture r_if_return1    'if [[ ! -e /nonexistent_kt036 ]]; then return 1; fi'
kt036_fixture r_or_return0    '[[ -e /nonexistent_kt036 ]] || return 0'
kt036_fixture r_eval_return1  'eval "return 1"'
kt036_fixture r_setT_return1  'kt036_f() { :; }; set -T; kt036_f; kt036_f; return 1'

# ---- controls: legitimate endings, no verdict -------------------------------
kt036_fixture_tail g_lastcmd_rc1   'kt036_g() { return 1; }; kt036_g'
kt036_fixture_tail g_and_end       '[[ -n "" ]] && echo "never printed"'
kt036_fixture      g_nested_lib    'source "$(dirname "$0")/lib_guard.sh"; source "$(dirname "$0")/lib_guard.sh"; source "$(dirname "$0")/lib_ret1.sh"'
kt036_fixture_tail g_nested_last   'source "$(dirname "$0")/lib_ret1.sh"'
kt036_fixture_tail g_set_u         'set -u; kt036_h() { [[ -n "" ]]; }; kt036_h'
# the test's own RETURN trap replaces the runner's and still fires for its own source
kt036_fixture g_own_rtrap 'kt036_seen=0; trap '"'"'kt036_seen=$((kt036_seen + 1))'"'"' RETURN; source "$(dirname "$0")/lib_guard.sh"
kt_test_start "own trap"; [[ $kt036_seen -ge 1 ]] && kt_test_pass "own RETURN trap fired" || kt_test_fail "own RETURN trap did not fire ($kt036_seen)"'
# thttpserver-style set -T DEBUG canary: the runner's RETURN trap must not make
# the canary see a subshell, and the canary's control run must still see one
kt036_fixture g_setT_canary 'kt_test_start "canary"
CANARY="$(dirname "$0")/canary.$$"; rm -f "$CANARY"
kt036_c() { local x=1; return 0; }
set -T; trap '"'"'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi'"'"' DEBUG
kt036_c; kt036_c; kt036_c
trap - DEBUG; set +T
seen=0; [[ -e "$CANARY" ]] && seen=1; rm -f "$CANARY"
set -T; trap '"'"'if (( BASH_SUBSHELL > 0 )); then : > "$CANARY"; fi'"'"' DEBUG
ctl="$(printf x)"
trap - DEBUG; set +T
ctlseen=0; [[ -e "$CANARY" ]] && ctlseen=1; rm -f "$CANARY"
if [[ $seen -eq 0 && $ctlseen -eq 1 ]]; then kt_test_pass "canary"; else kt_test_fail "seen=$seen control=$ctlseen"; fi'

# ---- documented residual: undetectable, no verdict ---------------------------
kt036_fixture res_or_return1   '[[ -e /nonexistent_kt036 ]] || return 1'
kt036_fixture res_bare_return  'false; return'
kt036_fixture res_own_rtrap    'trap ":" RETURN; return 1'

# name|expected runner counts t:p:f
KT036_ABORTS=(
    "r_return1|2:1:1"
    "r_if_return1|2:1:1"
    "r_or_return0|2:1:1"
    "r_eval_return1|2:1:1"
    "r_setT_return1|2:1:1"
)
KT036_CONTROLS=(
    "g_lastcmd_rc1|2:2:0"
    "g_and_end|2:2:0"
    "g_nested_lib|2:2:0"
    "g_nested_last|2:2:0"
    "g_set_u|2:2:0"
    "g_own_rtrap|3:3:0"
    "g_setT_canary|3:3:0"
)
KT036_RESIDUAL=(
    "res_or_return1|1:1:0"
    "res_bare_return|1:1:0"
    "res_own_rtrap|1:1:0"
)

# kt036_run MODE FILE... — runs the nested runner with THIS file's counters
# saved; leaves R_COUNTS (t:p:f the runner added), R_FILES (sorted failed
# basenames) and R_OUT (the runner's output file).
KT036_N=0
kt036_run() {
    local mode="$1"; shift
    local st=$TESTS_TOTAL sp=$TESTS_PASSED sf=$TESTS_FAILED
    TESTS_TOTAL=0; TESTS_PASSED=0; TESTS_FAILED=0; FAILED_TEST_FILES=()
    KT036_N=$(( KT036_N + 1 ))
    R_OUT="$TMP/run.$KT036_N.out"
    local sv="$VERBOSITY"
    VERBOSITY=error
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

# kt036_cause_line NAME — the runner's "[FAIL] NAME.sh: source aborted (" line in R_OUT
kt036_cause_line() {
    local line
    CAUSE_LINE=""
    while IFS= read -r line; do
        if [[ "$line" == *"[FAIL] $1.sh: source aborted ("* ]]; then CAUSE_LINE="$line"; return 0; fi
    done < "$R_OUT"
    return 1
}

# ---- each case alone, sequential ---------------------------------------------
for spec in "${KT036_ABORTS[@]}"; do
    IFS='|' read -r name want <<< "$spec"
    kt_test_start "sequential: $name is FAILED as a file-scope return, counts $want"
    kt036_run sequential "$FX/$name.sh"
    kt036_cause_line "$name"
    if [[ "$R_COUNTS" == "$want" && "$R_FILES" == "$name.sh" && "$CAUSE_LINE" == *"file-scope return"* ]]; then
        kt_test_pass "$name: $CAUSE_LINE"
    else
        kt_test_fail "$name: counts=$R_COUNTS (want $want) failed=[$R_FILES] cause=[$CAUSE_LINE]"
    fi
done

for spec in "${KT036_CONTROLS[@]}" "${KT036_RESIDUAL[@]}"; do
    IFS='|' read -r name want <<< "$spec"
    kt_test_start "sequential: $name keeps counts $want and gets no verdict"
    kt036_run sequential "$FX/$name.sh"
    if [[ "$R_COUNTS" == "$want" && -z "$R_FILES" ]] && ! kt036_cause_line "$name" \
       && ! grep -q '__KT_END_' "$R_OUT"; then
        kt_test_pass "$name: $R_COUNTS"
    else
        kt_test_fail "$name: counts=$R_COUNTS (want $want) failed=[$R_FILES] cause=[$CAUSE_LINE] out=[$(head -c 400 "$R_OUT")]"
    fi
done

# ---- all fixtures in one run, both execution paths ---------------------------
ALL=()
want_t=0 want_p=0 want_f=0
want_files=()
for spec in "${KT036_ABORTS[@]}" "${KT036_CONTROLS[@]}" "${KT036_RESIDUAL[@]}"; do
    IFS='|' read -r name want <<< "$spec"
    ALL+=( "$FX/$name.sh" )
    IFS=':' read -r t p f <<< "$want"
    want_t=$(( want_t + t )); want_p=$(( want_p + p )); want_f=$(( want_f + f ))
    (( f > 0 )) && want_files+=( "$name.sh" )
done
WANT_FILES="$(printf '%s\n' "${want_files[@]}" | sort | tr '\n' ' ')"; WANT_FILES="${WANT_FILES% }"
WANT_COUNTS="$want_t:$want_p:$want_f"

for mode in sequential threaded; do
    kt_test_start "$mode: ${#ALL[@]} fixtures -> FAILED_TEST_FILES is exactly the ${#want_files[@]} file-scope returns, totals $WANT_COUNTS"
    kt036_run "$mode" "${ALL[@]}"
    missing=""
    for spec in "${KT036_ABORTS[@]}"; do
        IFS='|' read -r name _ <<< "$spec"
        kt036_cause_line "$name" && [[ "$CAUSE_LINE" == *"file-scope return"* ]] || missing+="$name "
    done
    if [[ "$R_FILES" == "$WANT_FILES" && "$R_COUNTS" == "$WANT_COUNTS" && -z "$missing" ]] \
       && ! grep -q '__KT_END_' "$R_OUT"; then
        kt_test_pass "$mode: $R_COUNTS"
    else
        kt_test_fail "$mode: counts=$R_COUNTS (want $WANT_COUNTS) failed=[$R_FILES] want=[$WANT_FILES] no cause: $missing"
    fi
done
