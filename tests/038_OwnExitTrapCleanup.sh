#!/bin/bash
# OwnExitTrapCleanup (ktests round 3, T5 / DT5, 2026-10-02).
#
# A test that installs its own `trap … EXIT` REPLACES kt_test_init's trap, so
# kt_fixture_teardown never runs: its registered handlers are skipped and its
# fixture dir tests/.tmp/<Name>.<file> stays behind. Rules now:
#   - the runner, after judging a file, removes a still-present
#     <test dir>/.tmp/*.<file> and prints
#     "[WARN] <file>: fixture dir .tmp/<dir> left behind (own EXIT trap?) …";
#   - a standalone `bash FILE` wipes a stale fixture dir at the next setup
#     (one created earlier by the SAME process is kept);
#   - no `trap` shim: a test registers cleanup with kt_fixture_cleanup_register.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "OwnExitTrapCleanup" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
FX="$TMP/fx"
mkdir -p "$FX"

# kt038_fixture NAME BODY — tests "one" and "two" around BODY
kt038_fixture() {
    {
        printf '%s\n' \
            'kt_test_init "TrapFx" "$(dirname "$0")"' \
            'kt_test_start "one"; kt_test_pass "one"'
        printf '%s\n' "$2"
        printf '%s\n' 'kt_test_start "two"; kt_test_pass "two"'
    } > "$FX/$1.sh"
}

kt038_fixture own_trap      "trap 'echo own-trap-ran' EXIT"
kt038_fixture own_trap_exit "trap 'echo own-trap-ran' EXIT
kt_test_start \"two\"; kt_test_pass \"two\"
exit 0"
kt038_fixture normal        ':'
kt038_fixture registered    'kt038_h() { echo "handler-ran"; }; kt_fixture_cleanup_register kt038_h'

# name|expected counts|warn (0/1)
KT038_CASES=(
    "own_trap|2:2:0|1"
    "own_trap_exit|1:0:1|1"
    "normal|2:2:0|0"
    "registered|2:2:0|0"
)

# kt038_run MODE FILE... — the nested runner with THIS file's counters saved;
# leaves R_COUNTS, R_FILES (sorted failed basenames), R_OUT.
KT038_N=0
kt038_run() {
    local mode="$1"; shift
    local st=$TESTS_TOTAL sp=$TESTS_PASSED sf=$TESTS_FAILED
    TESTS_TOTAL=0; TESTS_PASSED=0; TESTS_FAILED=0; FAILED_TEST_FILES=()
    KT038_N=$(( KT038_N + 1 ))
    R_OUT="$TMP/run.$KT038_N.out"
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

# kt038_left — the entries left in the fixtures' .tmp, space-separated
kt038_left() {
    local e out=""
    for e in "$FX/.tmp/"* "$FX/.tmp/".[!.]*; do
        [[ -e "$e" ]] && out+="${e##*/} "
    done
    printf '%s' "${out% }"
}

kt038_warns() { grep -c '^\[WARN\] .*: fixture dir .* left behind (own EXIT trap?)' "$R_OUT"; }

# ---- each case alone, sequential ---------------------------------------------
for spec in "${KT038_CASES[@]}"; do
    IFS='|' read -r name want warn <<< "$spec"
    kt_test_start "sequential: $name leaves no fixture dir; WARN=$warn; counts $want"
    rm -rf "$FX/.tmp"
    kt038_run sequential "$FX/$name.sh"
    left="$(kt038_left)"
    nw="$(kt038_warns)"
    wline="$(grep -m1 '^\[WARN\]' "$R_OUT")"
    if [[ -z "$left" && "$nw" == "$warn" && "$R_COUNTS" == "$want" ]] \
       && { (( warn == 0 )) || [[ "$wline" == "[WARN] $name.sh: fixture dir .tmp/TrapFx.$name left behind"* ]]; }; then
        kt_test_pass "$name: left=[$left] warns=$nw $R_COUNTS"
    else
        kt_test_fail "$name: left=[$left] warns=$nw (want $warn) counts=$R_COUNTS (want $want) warn=[$wline]"
    fi
done

kt_test_start "single file: a registered cleanup handler runs (the framework EXIT trap was not replaced)"
# the handler prints at teardown, after the END marker; read the raw capture
st=$TESTS_TOTAL sp=$TESTS_PASSED sf=$TESTS_FAILED
kt_runner_execute_single_test "$FX/registered.sh" >/dev/null 2>&1
TESTS_TOTAL=$st; TESTS_PASSED=$sp; TESTS_FAILED=$sf
if [[ "$output_content" == *"handler-ran"* && "$output_content" != *"[WARN]"* ]]; then
    kt_test_pass "handler ran, no WARN"
else
    kt_test_fail "output=[$output_content]"
fi

# ---- all cases in one run, both paths ----------------------------------------
ALL=(); want_t=0 want_p=0 want_f=0 want_w=0
for spec in "${KT038_CASES[@]}"; do
    IFS='|' read -r name want warn <<< "$spec"
    ALL+=( "$FX/$name.sh" )
    IFS=':' read -r t p f <<< "$want"
    want_t=$(( want_t + t )); want_p=$(( want_p + p )); want_f=$(( want_f + f )); want_w=$(( want_w + warn ))
done
for mode in sequential threaded; do
    kt_test_start "$mode: ${#ALL[@]} fixtures leave no fixture dir and print $want_w WARN lines"
    rm -rf "$FX/.tmp"
    kt038_run "$mode" "${ALL[@]}"
    left="$(kt038_left)"
    nw="$(kt038_warns)"
    if [[ -z "$left" && "$nw" == "$want_w" && "$R_COUNTS" == "$want_t:$want_p:$want_f" && "$R_FILES" == "own_trap_exit.sh" ]]; then
        kt_test_pass "$mode: $R_COUNTS warns=$nw"
    else
        kt_test_fail "$mode: left=[$left] warns=$nw (want $want_w) counts=$R_COUNTS (want $want_t:$want_p:$want_f) failed=[$R_FILES]"
    fi
done

# ---- standalone: the stale dir of an earlier run is wiped at the next setup ---
cat > "$FX/standalone.sh" <<'FIXEOF'
source "$KTESTS_LIB_DIR/ktest_source.sh"
kt_test_init "Stale" "$(dirname "$0")"
if [[ -e "$(kt_fixture_tmpdir)/stale.txt" ]]; then echo "STALE-SEEN"; else echo "CLEAN"; fi
echo "mine" > "$(kt_fixture_tmpdir)/mine.txt"
# a second setup with the same id in the SAME process keeps the dir
kt_fixture_setup "Stale.standalone" "$(dirname "$0")"
if [[ -e "$(kt_fixture_tmpdir)/mine.txt" ]]; then echo "KEPT"; else echo "WIPED-OWN"; fi
trap 'echo own-trap' EXIT
FIXEOF

kt_test_start "standalone: an own-trap run leaves its dir; the next run wipes it at setup, a same-process re-setup keeps it"
rm -rf "$FX/.tmp"
mkdir -p "$FX/.tmp/Stale.standalone"
echo stale > "$FX/.tmp/Stale.standalone/stale.txt"
out1="$(cd "$FX" && KK_OUTPUT_COUNTS=0 KTESTS_LIB_DIR="$KTESTS_LIB_DIR" bash "$FX/standalone.sh" 2>&1)"
left1="$(kt038_left)"
echo stale > "$FX/.tmp/Stale.standalone/stale.txt"
out2="$(cd "$FX" && KK_OUTPUT_COUNTS=0 KTESTS_LIB_DIR="$KTESTS_LIB_DIR" bash ./standalone.sh 2>&1)"
out1="${out1//$'\n'/ }"; out2="${out2//$'\n'/ }"
if [[ "$out1" == "CLEAN KEPT own-trap" && "$out2" == "CLEAN KEPT own-trap" && "$left1" == "Stale.standalone" ]]; then
    kt_test_pass "run1=[$out1] run2=[$out2] left after run1=[$left1]"
else
    kt_test_fail "run1=[$out1] run2=[$out2] left after run1=[$left1] (want CLEAN KEPT own-trap, Stale.standalone)"
fi
rm -rf "$FX/.tmp"
