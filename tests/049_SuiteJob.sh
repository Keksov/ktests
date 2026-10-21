#!/usr/bin/env bash
# SuiteJob (gate G1, DG5). ktests/tools/suitejob.sh holds the master sweep's
# suite-job machinery, shared by tests/tests.sh and ktests/tools/gate.sh:
# kt_suitejob_discover (the master's process_dir walk), kt_suitejob_run (a
# background job of its own group under `set -m`, TTOU/TTIN ignored, INT
# default, the caller's stdin, `wait` loop), kt_suitejob_break (a caller's
# trap — G2's USR1 — breaks the wait), kt_suitejob_signal (TERM+CONT the
# group, grace, KILL), kt_suitejob_strays (the narrowed stray check with the
# label that was running). The master's own behaviour is pinned by 045.
#
# The jobs run in a DRIVER bash of their own (traps, `set -m`); every process
# made here carries a nonce ($N, or $M for the one that must NOT match) and
# runs an owner-tied loop (it ends when this file's shell is gone); the EXIT
# trap kills whatever still carries a nonce.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SuiteJob" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
SJ="$LIB/tools/suitejob.sh"
N="kt049x$$x$RANDOM$RANDOM"
M="kt049y$$y$RANDOM$RANDOM"

export KT049_OWNER="$$"
# no /dev/ptmx (FreeBSD): the fixtures wait on a FIFO of this file instead,
# never on a `sleep` child (it would be listed with them) — launch L2.1
export KT049_FIFO=""
if [[ ! -c /dev/ptmx ]]; then KT049_FIFO="$TMP/nap.fifo"; mkfifo "$KT049_FIFO" 2>/dev/null || KT049_FIFO=""; fi
export KT049_LOOP='{ [[ -c /dev/ptmx ]] && exec 3<>/dev/ptmx; } 2>/dev/null || { [[ -p "$KT049_FIFO" ]] && exec 3<>"$KT049_FIFO"; } 2>/dev/null || exec 3</dev/null; while kill -0 "$KT049_OWNER" 2>/dev/null; do read -t 0.3 -u 3 _ || (( $? > 128 )) || sleep 1; done'

# kt049_pids TEXT — REPLY = the pids (not this shell) whose command line contains TEXT
kt049_pids() { kt_proc_pids "$1"; }   # ktest_proc.sh (launch L2.1)
kt049_cleanup() {
    local t
    for t in "$N" "$M"; do
        kt049_pids "$t"
        [[ -n "$REPLY" ]] && kill -KILL $REPLY 2>/dev/null
    done
    return 0
}
eval "$(trap -p EXIT | sed "s/^trap -- '/trap -- 'trap \"\" TERM INT HUP; kt049_cleanup; /")"
[[ "$(trap -p EXIT)" == *kt049_cleanup* ]] || trap 'trap "" TERM INT HUP; kt049_cleanup' EXIT
trap 'trap "" TERM INT HUP; exit 143' TERM
trap 'trap "" TERM INT HUP; exit 130' INT
trap 'trap "" TERM INT HUP; exit 129' HUP

# ---- discovery ---------------------------------------------------------------
# the master's process_dir before G1, verbatim (tests/tests.sh at kbool d926100)
kt049_old_discover() (
    KBOOL_DIR="$1"
    test_scripts=()
    process_dir() {
        local base_dir="$1"
        if [[ -f "$base_dir/tests/tests.sh" && "$base_dir" != "$KBOOL_DIR" ]]; then
            test_scripts+=("$base_dir/tests/tests.sh")
        fi
        for entry in "$base_dir"/*; do
            if [[ -d "$entry" && ! "$(basename "$entry")" =~ ^\. ]]; then
                process_dir "$entry"
            fi
        done
    }
    process_dir "$KBOOL_DIR"
    printf '%s\n' "${test_scripts[@]}"
)
T="$TMP/tree"
for d in tests a a/sub a/tests/inner B b .hidden b/.h2 "c d" f/g zz/.x/y; do
    mkdir -p "$T/$d/tests"
    printf '#!/bin/bash\nexit 0\n' > "$T/$d/tests/tests.sh"
done
mkdir -p "$T/f/empty" "$T/.git/tests"
: > "$T/e"
printf '#!/bin/bash\n' > "$T/.git/tests/tests.sh"

kt_test_start "discover: same suites in the same order as the old process_dir walk (root's own tests/ and hidden dirs skipped)"
old="$(kt049_old_discover "$T")"
new="$(source "$SJ"; kt_suitejob_discover "$T"; kt_suitejob_discover "$T"; printf '%s\n' "${KT_SUITEJOB_SUITES[@]}"; echo "n=$RESULT")"
want_n="n=$(grep -c . <<< "$old")"
if [[ -n "$old" && "${new%$'\n'n=*}" == "$old" && "${new##*$'\n'}" == "$want_n" \
      && "$old" != *"/.hidden/"* && "$old" != *"/.h2/"* && "$old" != *"/.x/"* && "$old" != *"/.git/"* \
      && "$old" != "$T/tests/tests.sh"* && "$old" == *"$T/a/tests/inner/tests/tests.sh"* && "$old" == *"$T/c d/tests/tests.sh"* ]]; then
    kt_test_pass "${want_n}: ${old//$'\n'/ }"
else
    kt_test_fail "old: ${old//$'\n'/ | } || new: ${new//$'\n'/ | }"
fi

# ---- the job -----------------------------------------------------------------
# the driver: sources suitejob.sh, runs one scenario, reports KEY=VALUE lines
cat > "$TMP/drv.sh" <<'EOF'
PROC="${1%/*}/../ktest_proc.sh"   # the process table (launch L2.1)
source "$1"; shift
scen="$1" out="$2" N="$3" M="$4"
# drv_orphan NAME — a process NAME whose parent exits at once (this session);
# waits until it is adopted: ppid 1, or a subreaper of another session or
# a `timeout` (FreeBSD's is a reaper; kt_proc_adopted)
drv_orphan() {
    bash -c '(exec -a "$1" bash -c "$KT049_LOOP") </dev/null >/dev/null 2>&1 & exit' _ "$1"
    local i p
    for (( i = 0; i < 50; i++ )); do
        kt_proc_pid0 "$1"
        for p in $REPLY; do
            kt_proc_adopted "$p" && return 0
        done
        sleep 0.1
    done
    return 1
}
case "$scen" in
    run)
        kt_suitejob_init "$EPOCHREALTIME" "$N"
        kt_suitejob_run L1 bash -c 'source "$2"; kt_proc_pgid $$; pg="$REPLY"; echo "$$ $pg" > "$1.grp"; trap -p TTOU > "$1.ttou"; trap -p INT > "$1.int"; IFS= read -r l; printf "%s" "$l" > "$1.stdin"; exit 3' _ "$out" "$PROC"
        echo "rc=$? jobrc=$KT_SUITEJOB_RC pid=[$KT_SUITEJOB_PID] cur=$KT_SUITEJOB_CUR names=${KT_SUITEJOB_NAMES[*]} t0=${#KT_SUITEJOB_T0[@]} mon=[${-//[!m]/}]"
        ;;
    break)
        KT_SUITEJOB_GRACE=30
        kt_suitejob_init "$EPOCHREALTIME" "$N"
        trap 'kt_suitejob_break' USR1
        t0=$SECONDS
        kt_suitejob_run L2 bash -c 'echo $$ > "$1.pid"; (trap "" TERM; exec -a "kt049-$2-child" bash -c "trap \"\" TERM; $KT049_LOOP") & sleep 0.5; kill -USR1 $PPID; wait' _ "$out" "$N"
        r=$? pg="$KT_SUITEJOB_PID" a=n
        [[ -n "$pg" ]] && kill -0 "$pg" 2>/dev/null && a=y
        echo "rc=$r waited=$(( SECONDS - t0 )) pid=[$pg] alive=$a"
        kt_suitejob_signal 143
        # KILLed members leave the group within moments (kill -0 sees a group
        # until its last member is gone): up to 2 s
        g=alive
        for (( i = 0; i < 40; i++ )); do kill -0 -- "-$pg" 2>/dev/null || { g=empty; break; }; sleep 0.05; done
        echo "after=[$KT_SUITEJOB_PID] sigrc=$KT_SUITEJOB_SIGNAL_RC group=$g"
        ;;
    strays)
        drv_orphan "kt049-$N-c0"; sleep 0.5; (( KT_PROC_START_RES_MS >= 1000 )) && sleep 1          # before the window: never listed
        kt_suitejob_init "$EPOCHREALTIME" "$N"
        drv_orphan "kt049-$N-a0"; sleep 0.5; (( KT_PROC_START_RES_MS >= 1000 )) && sleep 1          # in the window, before the first job
        # (ps: start times to the second — a gap of more than 1 s, launch L2.1)
        drv_orphan "kt049-$M-b"                      # in the window, not matching
        kt_suitejob_run sX bash -c "source '$PROC'; $(declare -f drv_orphan); drv_orphan kt049-$N-a1; exit 0"
        kt_suitejob_strays "after sX"; echo "s1=$?"
        printf 'row=%s\n' "${KT_SUITEJOB_STRAY_ROWS[@]}"
        echo "labels=${!KT_SUITEJOB_STRAY_LABELS[*]}"
        kt_suitejob_strays "again"; echo "s2=$?"
        ;;
esac
EOF

kt_test_start "run: the job's status, its own process group, TTOU ignored, INT default, the caller's stdin; set -m restored"
o="$(printf 'kt049-in\n' | timeout 60 bash "$TMP/drv.sh" "$SJ" run "$TMP/run" "$N" "$M" 2>&1)"
read -r jp jg < "$TMP/run.grp" 2>/dev/null
tt="$(cat "$TMP/run.ttou" 2>/dev/null)"; ti="$(cat "$TMP/run.int" 2>/dev/null)"; si="$(cat "$TMP/run.stdin" 2>/dev/null)"
if [[ "$o" == "rc=0 jobrc=3 pid=[] cur=L1 names=L1 t0=1 mon=[]" && -n "${jp:-}" && "$jp" == "${jg:-}" \
      && "$tt" == *"''"*TTOU* && -z "$ti" && "$si" == kt049-in ]]; then
    kt_test_pass "$o; job $jp leads group $jg; [$tt]"
else
    kt_test_fail "out [$o] job/grp [${jp:-}/${jg:-}] ttou [$tt] int [$ti] stdin [$si]"
fi

kt_test_start "break: a USR1 trap calling kt_suitejob_break ends the wait at once; kt_suitejob_signal empties the group (KILL for a TERM-ignoring member)"
o="$(timeout 60 bash "$TMP/drv.sh" "$SJ" break "$TMP/brk" "$N" "$M" 2>&1)"
sleep 0.3
kt049_pids "kt049-$N-child"; left="$REPLY"
jp="$(cat "$TMP/brk.pid" 2>/dev/null)"
if [[ "$o" == "rc=1 waited="[0-4]" pid=[$jp] alive=y"$'\n'"after=[] sigrc=143 group=empty" && -n "$jp" && -z "$left" ]]; then
    kt_test_pass "${o//$'\n'/; }"
else
    kt_test_fail "out [${o//$'\n'/ | }] job [$jp] left [$left]"
fi
kt049_cleanup

kt_test_start "strays: only the window's matching orphans, each with the label running when it started; stopped; the others untouched"
# c0 and b are left alive on purpose: FreeBSD's timeout would wait for them
# (KT_TMO_BOUND, ktest_proc.sh — launch L2.1)
o="$(timeout "${KT_TMO_BOUND[@]}" 90 bash "$TMP/drv.sh" "$SJ" strays "$TMP/str" "$N" "$M" 2>&1)"
kt049_pids "kt049-$N-a"; la="$REPLY"
kt049_pids "kt049-$N-c0"; lc="$REPLY"
kt049_pids "kt049-$M-b"; lb="$REPLY"
if [[ "$o" == *"[WARN] 2 stray process(es) found after after sX:"* \
      && "$o" == *"started during (before the first suite): kt049-$N-a0"* \
      && "$o" == *"started during sX: kt049-$N-a1"* \
      && "$o" == *"[WARN] stopped them, none left"* \
      && "$o" == *"s1=1"* && "$o" == *"s2=0"* && "$o" != *"-c0"* && "$o" != *"$M"* \
      && "$o" == *"row=pid "*" (yes) started during sX: kt049-$N-a1"* \
      && -z "$la" && -n "$lc" && -n "$lb" ]]; then
    kt_test_pass "a0/a1 reported and stopped; c0 (before the window) and the non-matching one left alone"
else
    kt_test_fail "a-left [$la] c0 [$lc] b [$lb] | ${o//$'\n'/ | }"
fi
kt049_cleanup

kt_test_log "049_SuiteJob.sh completed"
