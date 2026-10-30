#!/usr/bin/env bash
# SummaryFile (gate G1, GATE_PLAN §4.3). `KT_SUMMARY_FILE=PATH ktests.sh …`
# writes a machine summary of the run, so a tool (ktests/tools/gate.sh) needs
# no parsing of the human output: line 1 `TOTAL PASSED FAILED RC`, then one
# `file NAME` line per failed test file; a run that did not reach its normal
# end writes `0 0 0 RC` + `error REASON` (usage, no-test-files, interrupted,
# no-results, exit) — a missing file can only mean the runner died. The
# variable is read once and unset before any test file or worker runs: a
# nested ktests run started by a test file neither sees nor overwrites it.
# Written atomically (temp + mv in the same dir). Unset: no file, no change.
#
# Every fixture process carries the nonce $N; the EXIT trap kills whatever
# still carries it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SummaryFile" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
N="kt048x$$x$RANDOM$RANDOM"

# kt048_pids TEXT — REPLY = the pids (not this shell) whose command line contains TEXT
kt048_pids() { kt_proc_pids "$1"; }   # ktest_proc.sh: /proc or ps (launch L2.1)
kt048_cleanup() {
    kt048_pids "$N"
    [[ -n "$REPLY" ]] && kill -KILL $REPLY 2>/dev/null
    return 0
}
eval "$(trap -p EXIT | sed "s/^trap -- '/trap -- 'trap \"\" TERM INT HUP; kt048_cleanup; /")"
[[ "$(trap -p EXIT)" == *kt048_cleanup* ]] || trap 'trap "" TERM INT HUP; kt048_cleanup' EXIT
trap 'trap "" TERM INT HUP; exit 143' TERM
trap 'trap "" TERM INT HUP; exit 130' INT
trap 'trap "" TERM INT HUP; exit 129' HUP

# kt048_file SUITE NAME BODY — a test file SUITE/NAME.sh running BODY
kt048_file() {
    mkdir -p "$TMP/$1"
    printf '%s\n' "source '$LIB/ktest.sh'" 'kt_test_init "Sf" "$(dirname "$0")"' "$3" > "$TMP/$1/$2.sh"
}
kt048_file ok 001_a 'kt_test_start a; kt_test_pass a'
kt048_file ok 002_b 'kt_test_start b; kt_test_pass b
kt_test_start c; kt_test_pass c'
kt048_file bad 001_a 'kt_test_start a; kt_test_fail a'
kt048_file bad 002_b 'kt_test_start b; kt_test_pass b'
kt048_file bad 003_c 'kt_test_start c; kt_test_fail c
kt_test_start d; kt_test_pass d'
mkdir -p "$TMP/empty"
# nested: a test file that records what it sees of KT_SUMMARY_FILE and runs a
# nested ktests.sh (the ok suite) without setting it
kt048_file nest 001_n "printf '%s\n' \"\${KT_SUMMARY_FILE-<unset>}\" > \"\$KT048_SEEN.\$BASHPID\"
out=\"\$(env -u KTESTS_LIB_DIR bash '$LIB/ktests.sh' '$TMP/ok' Inner 2>&1)\"
kt_test_start nested
[[ \"\$out\" == *'Total tests: 3'* ]] && kt_test_pass nested || kt_test_fail \"\$out\""
kt048_file nest 002_m 'kt_test_start m; kt_test_pass m'
# envy (gate G2 review R4): 002 dies of a (simulated) fork failure — cygwin's
# raw line, then the shell is gone without its END marker and counts (KILL:
# no EXIT trap) — so the runner's retry rule gives up on it: `env 002_die.sh`;
# 003 runs to its end and FAILs with a message that only TALKS about a fork
# failure: a failure of the test, no `env` line
kt048_file envy 001_ok 'kt_test_start ok; kt_test_pass ok'
kt048_file envy 002_die 'kt_test_start d
echo "      0 [main] bash 4242 dofork: child -1 - CreateProcessW failed for bash.exe, errno 11" >&2
kill -KILL $$'
kt048_file envy 003_msg 'kt_test_start m; kt_test_fail "expected the message: bash: fork: retry: Resource temporarily unavailable"'
# slow: a test file that blocks until it is stopped (owner-tied: it ends when
# this file's shell is gone)
kt048_file slow 001_s "kt_test_start s
: > \"\$KT048_STARTED\"
bash -c 'exec -a kt048-$N-slow bash -c \"while kill -0 $$ 2>/dev/null; do read -t 0.3 -u 3 _ 2>/dev/null 3<>/dev/ptmx || sleep 1; done\"' &
wait
kt_test_pass s"

# kt048_run TAG SUITE [ARGS…] — run SUITE with KT_SUMMARY_FILE=$TMP/sum.TAG;
# OUT, RC, SUM (the file's lines joined with '|', "<none>" without a file)
kt048_run() {
    local tag="$1" suite="$2"
    shift 2
    mkdir -p "$TMP/tmp.$tag"
    OUT="$(KT_SUMMARY_FILE="$TMP/sum.$tag" TMPDIR="$TMP/tmp.$tag" "$KT_TIMEOUT" 120 env -u KTESTS_LIB_DIR bash "$LIB/ktests.sh" "$TMP/$suite" "S-$tag" "$@" 2>&1)"; RC=$?
    kt048_sum "$TMP/sum.$tag"
}
kt048_sum() {
    local -a l=()
    SUM="<none>"
    [[ -f "$1" ]] || return 0
    mapfile -t l < "$1"
    local IFS='|'
    SUM="${l[*]}"
}
# kt048_clean_dir — the summary dir holds no temp file of the atomic write
kt048_no_tmp() {
    local f
    for f in "$TMP"/sum.*; do [[ "$f" == *.tmp.* ]] && return 1; done
    return 0
}

for mode in single threaded; do
    kt_test_start "passing suite ($mode): '3 3 0 0' and nothing else"
    if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
    else
    kt048_run "ok.$mode" ok -m "$mode"
    if [[ "$RC" == 0 && "$SUM" == "3 3 0 0" ]] && kt048_no_tmp; then
        kt_test_pass "$SUM"
    else
        kt_test_fail "rc=$RC sum=[$SUM] | ${OUT//$'\n'/ | }"
    fi
    fi   # kt_need_timeout
    kt_test_start "failing suite ($mode): counts, rc 1 and both failed files by name"
    if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
    else
    kt048_run "bad.$mode" bad -m "$mode"
    if [[ "$RC" == 1 && "$SUM" == "4 2 2 1|file 001_a.sh|file 003_c.sh" && "$OUT" == *"[FAIL]"*"001_a.sh"* ]]; then
        kt_test_pass "$SUM"
    else
        kt_test_fail "rc=$RC sum=[$SUM] | ${OUT//$'\n'/ | }"
    fi
    fi   # kt_need_timeout
    kt_test_start "fork-failure death ($mode): 'env NAME' for the file the retry rule gave up on, none for a [FAIL] message about forks"
    if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
    else
    kt048_run "envy.$mode" envy -m "$mode"
    if [[ "$RC" == 1 && "$SUM" == "3 1 2 1|file 002_die.sh|file 003_msg.sh|env 002_die.sh" ]]; then
        kt_test_pass "$SUM"
    else
        kt_test_fail "rc=$RC sum=[$SUM] | ${OUT//$'\n'/ | }"
    fi
    fi   # kt_need_timeout
done

kt_test_start "no test files: '0 0 0 1' + 'error no-test-files'"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt048_run empty empty
if [[ "$RC" == 1 && "$SUM" == "0 0 0 1|error no-test-files" ]]; then
    kt_test_pass "$SUM"
else
    kt_test_fail "rc=$RC sum=[$SUM] | ${OUT//$'\n'/ | }"
fi
fi   # kt_need_timeout

kt_test_start "the option parser exits (bad option): '0 0 0 1' + 'error usage'"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt048_run usage ok -m bogus
if [[ "$RC" == 1 && "$SUM" == "0 0 0 1|error usage" ]]; then
    kt_test_pass "$SUM"
else
    kt_test_fail "rc=$RC sum=[$SUM] | ${OUT//$'\n'/ | }"
fi
fi   # kt_need_timeout

for mode in single threaded; do
    kt_test_start "nested run inside a test file ($mode): the test file and its nested ktests.sh never see the variable, the file is the outer run's"
    if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
    else
    rm -f "$TMP/seen".*
    export KT048_SEEN="$TMP/seen"
    kt048_run "nest.$mode" nest -m "$mode"
    unset KT048_SEEN
    seen=""
    for f in "$TMP/seen".*; do [[ -f "$f" ]] && seen+="$(< "$f");"; done
    if [[ "$RC" == 0 && "$SUM" == "2 2 0 0" && "$seen" == "<unset>;" ]] && kt048_no_tmp; then
        kt_test_pass "$SUM, test file saw [$seen]"
    else
        kt_test_fail "rc=$RC sum=[$SUM] seen=[$seen] | ${OUT//$'\n'/ | }"
    fi
    fi   # kt_need_timeout
done

for mode in single threaded; do
    kt_test_start "TERM mid-run ($mode): rc 143, '0 0 0 143' + 'error interrupted', nothing left"
    rm -f "$TMP/started" "$TMP/sum.term.$mode"
    mkdir -p "$TMP/tmp.term.$mode"
    KT048_STARTED="$TMP/started" KT_SUMMARY_FILE="$TMP/sum.term.$mode" TMPDIR="$TMP/tmp.term.$mode" \
        env -u KTESTS_LIB_DIR bash "$LIB/ktests.sh" "$TMP/slow" S-term -m "$mode" > "$TMP/term.$mode.out" 2>&1 &
    P=$!
    for (( i = 0; i < 300; i++ )); do [[ -f "$TMP/started" ]] && break; sleep 0.1; done
    sleep 0.3
    kill -TERM "$P" 2>/dev/null
    for (( i = 0; i < 200; i++ )); do kill -0 "$P" 2>/dev/null || break; sleep 0.1; done
    kill -0 "$P" 2>/dev/null && kill -KILL "$P" 2>/dev/null
    wait "$P"; RC=$?
    sleep 0.3
    kt048_pids "kt048-$N-slow"; left="$REPLY"
    kt048_sum "$TMP/sum.term.$mode"
    if [[ -f "$TMP/started" && "$RC" == 143 && "$SUM" == "0 0 0 143|error interrupted" && -z "$left" ]] && kt048_no_tmp; then
        kt_test_pass "$SUM"
    else
        kt_test_fail "started=$([[ -f "$TMP/started" ]] && echo y) rc=$RC sum=[$SUM] left=[$left] | $(tr '\n' ' ' < "$TMP/term.$mode.out")"
    fi
    kt048_cleanup
done

kt_test_start "unset or empty: no file is written and the output and rc are those of a run with it"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
mkdir -p "$TMP/tmp.plain" "$TMP/plain"
o1="$(cd "$TMP/plain" && TMPDIR="$TMP/tmp.plain" "$KT_TIMEOUT" 120 env -u KTESTS_LIB_DIR -u KT_SUMMARY_FILE bash "$LIB/ktests.sh" "$TMP/bad" S-plain -m single 2>&1)"; r1=$?
o2="$(cd "$TMP/plain" && KT_SUMMARY_FILE= TMPDIR="$TMP/tmp.plain" "$KT_TIMEOUT" 120 env -u KTESTS_LIB_DIR bash "$LIB/ktests.sh" "$TMP/bad" S-plain -m single 2>&1)"; r2=$?
o3="$(cd "$TMP/plain" && KT_SUMMARY_FILE="$TMP/plain/x.sum" TMPDIR="$TMP/tmp.plain" "$KT_TIMEOUT" 120 env -u KTESTS_LIB_DIR bash "$LIB/ktests.sh" "$TMP/bad" S-plain -m single 2>&1)"; r3=$?
rm -f "$TMP/plain/x.sum"
shopt -s nullglob dotglob; left=( "$TMP/plain"/* ); shopt -u nullglob dotglob
if [[ "$r1" == 1 && "$r2" == 1 && "$r3" == 1 && "$o1" == "$o2" && "$o1" == "$o3" && ${#left[@]} == 0 ]]; then
    kt_test_pass "rc 1 x3, identical output, nothing written"
else
    kt_test_fail "rc $r1/$r2/$r3 same12=$([[ "$o1" == "$o2" ]] && echo y) same13=$([[ "$o1" == "$o3" ]] && echo y) files=[${left[*]}]"
fi
fi   # kt_need_timeout

kt_test_start "a relative KT_SUMMARY_FILE names a file in the caller's cwd"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
rm -f "$TMP/plain/rel.sum"
( cd "$TMP/plain" && KT_SUMMARY_FILE=rel.sum TMPDIR="$TMP/tmp.plain" "$KT_TIMEOUT" 120 env -u KTESTS_LIB_DIR bash "$LIB/ktests.sh" "$TMP/ok" S-rel -m single >/dev/null 2>&1 )
kt048_sum "$TMP/plain/rel.sum"
if [[ "$SUM" == "3 3 0 0" ]]; then
    kt_test_pass "$SUM"
else
    kt_test_fail "sum=[$SUM]"
fi
fi   # kt_need_timeout

kt048_cleanup
kt_test_log "048_SummaryFile.sh completed"
