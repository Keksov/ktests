#!/bin/bash
# ThreadedRunnerIsolation (ktests round 3, T3/T4/T4b / DT3, 2026-10-02).
#
# T3: kt_runner_execute_threaded used to `export` its worker variables and
# `export -f` its worker functions in the CALLER's shell and to define a
# global `run_test` there. On 5.2.37 a prefix assignment
# (`VERBOSITY=error kt_runner_execute_threaded …`) then outlived the call; on
# both bashes previously non-exported globals came back `declare -x` and the
# functions stayed exported. Now run_test, the exports and the worker spawn
# live in ONE ( … ) subshell: no caller-visible change — values, export
# attributes, functions.
# T4: KT_ERROR_COUNTS is exported to the workers (a missing file's counts line
# was empty in an xargs worker). T4b: the sequential runner folds a missing file
# as 1:0:1 into FAILED_TEST_FILES, as the threaded one does (it skipped it).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ThreadedRunnerIsolation" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
FX="$TMP/fx"
mkdir -p "$FX"

for n in 1 2; do
    printf '%s\n' \
        'kt_test_init "IsoFx" "$(dirname "$0")"' \
        'kt_test_start "one"; kt_test_pass "one"' > "$FX/00${n}_Iso.sh"
done
A="$FX/001_Iso.sh"; B="$FX/002_Iso.sh"; MISSING="$FX/009_Missing.sh"

# kt037_run MODE FILE... — the nested runner with THIS file's counters saved;
# leaves R_COUNTS, R_FILES (sorted failed basenames), R_OUT.
KT037_N=0
kt037_run() {
    local mode="$1"; shift
    local st=$TESTS_TOTAL sp=$TESTS_PASSED sf=$TESTS_FAILED
    TESTS_TOTAL=0; TESTS_PASSED=0; TESTS_FAILED=0; FAILED_TEST_FILES=()
    KT037_N=$(( KT037_N + 1 ))
    R_OUT="$TMP/run.$KT037_N.out"
    TMPDIR="$TMP" WORKERS=4 "kt_runner_execute_$mode" "$@" > "$R_OUT" 2>&1
    R_COUNTS="$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
    R_FILES=""
    if (( ${#FAILED_TEST_FILES[@]} > 0 )); then
        R_FILES="$(printf '%s\n' "${FAILED_TEST_FILES[@]}" | sort | tr '\n' ' ')"
        R_FILES="${R_FILES% }"
    fi
    TESTS_TOTAL=$st; TESTS_PASSED=$sp; TESTS_FAILED=$sf
}

# kt037_attrs NAME — the declare attribute letters of a variable ("" if unset and plain)
kt037_attrs() {
    local d
    d="$(declare -p "$1" 2>/dev/null)" || { printf '%s' "<undeclared>"; return 0; }
    d="${d#declare -}"; d="${d%% *}"
    printf '%s' "$d"
}

# The variables the threaded runner hands to its workers. results_dir is its
# local; the others are framework globals.
KT037_VARS=(VERBOSITY _KT_ASSERT_QUIET_MODE _KTEST_QUIET_MODE KTESTS_LIB_DIR KT_ENV_FORK_FAILURE_RE KT_BASH_FATAL_DIAG_RE results_dir)
KT037_FUNCS=(run_test kt_test_debug kt_runner_execute_single_test kt_test_reset_counts kt_runner_clean_filename kt_runner_parse_counts kt_runner_set_error_counts kt_runner_find_last_counts_line kt_runner_scan_capture kt_runner_judge_capture)

# ---- T3: a prefix assignment does not outlive the call -----------------------
for v in "${KT037_VARS[@]}"; do
    kt_test_start "T3: '$v=… kt_runner_execute_threaded' leaves the caller's $v and its attributes as they were"
    saved="${!v-}"
    saved_attrs="$(kt037_attrs "$v")"
    printf -v "$v" '%s' "caller-$v"
    before_attrs="$(kt037_attrs "$v")"
    st=$TESTS_TOTAL sp=$TESTS_PASSED sf=$TESTS_FAILED
    # the prefix goes on the runner call itself (a wrapper function in between
    # would change what is measured); the bogus value breaks the nested run,
    # whose output is discarded — only the caller's state is checked
    eval "TMPDIR=\"\$TMP\" $v=\"prefix-\$v\" kt_runner_execute_threaded \"\$A\" \"\$B\" > \"\$TMP/prefix.\$v.out\" 2>&1"
    TESTS_TOTAL=$st; TESTS_PASSED=$sp; TESTS_FAILED=$sf; FAILED_TEST_FILES=()
    after="${!v-<unset>}"
    after_attrs="$(kt037_attrs "$v")"
    # restore
    if [[ "$v" == results_dir ]]; then
        unset results_dir
    else
        printf -v "$v" '%s' "$saved"
        if [[ "$saved_attrs" == *x* ]]; then export "$v"; else declare +x "$v"; fi
    fi
    if [[ "$after" == "caller-$v" && "$after_attrs" == "$before_attrs" ]]; then
        kt_test_pass "$v: value and attributes [$after_attrs] kept"
    else
        kt_test_fail "$v: after the call value=[$after] attrs=[$after_attrs] (before [caller-$v] [$before_attrs])"
    fi
done

# ---- T3: a plain call exports nothing in the caller --------------------------
kt_test_start "T3: a plain call leaves previously non-exported globals non-exported"
saved_x=()
for v in "${KT037_VARS[@]}"; do
    [[ "$v" == results_dir ]] && continue
    [[ "$(kt037_attrs "$v")" == *x* ]] && saved_x+=("$v")
    declare +x "$v" 2>/dev/null
done
kt037_run threaded "$A" "$B"
bad=""
for v in "${KT037_VARS[@]}"; do
    a="$(kt037_attrs "$v")"
    if [[ "$v" == results_dir ]]; then
        [[ "$a" == "<undeclared>" ]] || bad+="[results_dir declared: $a] "
    else
        [[ "$a" == *x* ]] && bad+="[$v: -$a] "
    fi
done
for v in "${saved_x[@]}"; do export "$v"; done
if [[ -z "$bad" && "$R_COUNTS" == "2:2:0" ]]; then
    kt_test_pass "no export attribute added (run $R_COUNTS)"
else
    kt_test_fail "exported by the call: $bad (run $R_COUNTS)"
fi

kt_test_start "T3: run_test is not defined in the caller and no worker function is left exported"
# The functions may arrive exported from THIS file's own runner worker: clear first.
for fn in "${KT037_FUNCS[@]}"; do export -nf "$fn" 2>/dev/null; done
unset -f run_test
kt037_run threaded "$A" "$B"
defined=""; declare -F run_test >/dev/null && defined="run_test"
exported="$(bash -c 'for f in "$@"; do declare -F "$f"; done' _ "${KT037_FUNCS[@]}" 2>/dev/null | tr '\n' ' ')"
if [[ -z "$defined" && -z "$exported" && "$R_COUNTS" == "2:2:0" ]]; then
    kt_test_pass "none (run $R_COUNTS)"
else
    kt_test_fail "defined in caller: [$defined] seen exported by a child: [$exported] (run $R_COUNTS)"
fi

# ---- T4: the workers get what they need --------------------------------------
# A shim `xargs` (command -v finds functions too) records what a worker
# environment holds, then runs the real xargs.
KT037_REC="$TMP/worker_env.txt"
xargs() {
    bash -c 'printf "KT_ERROR_COUNTS=%s\n" "${KT_ERROR_COUNTS-<unset>}"
             declare -F run_test kt_runner_execute_single_test kt_runner_judge_capture >/dev/null && echo "functions=ok"
             printf "VERBOSITY=%s\n" "${VERBOSITY-<unset>}"' > "$KT037_REC" 2>&1
    command xargs "$@"
}
kt_test_start "T4: an xargs worker sees KT_ERROR_COUNTS, the worker functions and VERBOSITY"
rm -f "$KT037_REC"
kt037_run threaded "$A" "$B"
rec="$(cat "$KT037_REC" 2>/dev/null)"
if [[ "$rec" == *"KT_ERROR_COUNTS=__COUNTS__:1:0:1"* && "$rec" == *"functions=ok"* && "$rec" == *"VERBOSITY=$VERBOSITY"* && "$R_COUNTS" == "2:2:0" ]]; then
    kt_test_pass "worker env ok"
else
    kt_test_fail "worker env: [$rec] run $R_COUNTS"
fi
unset -f xargs

# ---- T4/T4b: a missing file, same verdict on both paths ----------------------
for mode in sequential threaded; do
    kt_test_start "T4b: $mode counts a missing test file as 1:0:1 and lists it as FAILED"
    kt037_run "$mode" "$A" "$MISSING"
    if [[ "$R_COUNTS" == "2:1:1" && "$R_FILES" == "009_Missing.sh" ]]; then
        kt_test_pass "$mode: $R_COUNTS [$R_FILES]"
    else
        kt_test_fail "$mode: counts=$R_COUNTS (want 2:1:1) failed=[$R_FILES] (want [009_Missing.sh])"
    fi
done

# ---- the manual-background path (no xargs) behaves the same ------------------
# `command -v xargs` is the runner's switch; a shim makes it report no xargs.
command() {
    if [[ "$1" == "-v" && "$2" == "xargs" ]]; then return 1; fi
    builtin command "$@"
}
kt_test_start "manual-background path: same counts, missing file FAILED, no run_test or export left in the caller"
for fn in "${KT037_FUNCS[@]}"; do export -nf "$fn" 2>/dev/null; done
unset -f run_test
declare +x VERBOSITY
kt037_run threaded "$A" "$B" "$MISSING"
unset -f command
defined=""; declare -F run_test >/dev/null && defined="run_test"
vattrs="$(kt037_attrs VERBOSITY)"
export VERBOSITY
if [[ "$R_COUNTS" == "3:2:1" && "$R_FILES" == "009_Missing.sh" && -z "$defined" && "$vattrs" != *x* ]]; then
    kt_test_pass "manual: $R_COUNTS [$R_FILES]"
else
    kt_test_fail "manual: counts=$R_COUNTS (want 3:2:1) failed=[$R_FILES] run_test=[$defined] VERBOSITY attrs=[$vattrs]"
fi
