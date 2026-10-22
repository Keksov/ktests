#!/usr/bin/env bash
# StrayGuard (ktests round 5, P3b; 2026-10-16). A killed test/load run left 8
# fork-storm workers and a whole ktests process tree running for ~5 h. The
# guard: ktests/tools/strays.sh (list/stop the ORPHANED processes of the test
# machinery — marker rule + orphan rule, see its header), the master sweep's
# per-suite check (tests/tests.sh: report, stop, FAIL) and the end-of-run
# check of the ktests run groups (kt_strays_group_settle).
#
# Every process made here carries a nonce ($N) in its command line; the EXIT
# trap (chained before the framework's own) and every case's end kill whatever
# carries it, so nothing outlives this file whatever the verdict. A scan is
# narrowed to the nonce (--match / KT_STRAYS_MATCH): the orphans of a test file
# running beside this one in the threaded runner are never touched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "StrayGuard" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
ROOT="$(cd "$LIB/.." && pwd)"
ST="$LIB/tools/strays.sh"
source "$ST"
N="kt045x$$x$RANDOM$RANDOM"

# OWNER-TIED FIXTURES (review of P3b): every process this file makes on
# purpose runs KT045_LOOP — it lives only while this shell ($$) does and ends
# by itself within 0.3 s of its death, whatever killed it (a SIGKILL skips
# every trap; a second TERM inside the EXIT trap cut it short — the runner's
# group stop re-sent TERM then, and any outside killer may — leaving the
# TERM-ignoring "stubborn" fixture behind). No fork in the loop:
# `read -t` on a pty master of its own (/dev/ptmx: nothing ever writes to the
# slave, so the read times out). Not a shared FIFO: cygwin FIFO opens failed
# or stalled when several fixtures opened one (probe, 2026-10-16). Without a
# pty the loop polls with `sleep 1` (never a busy loop). Owner and loop
# travel in the ENVIRONMENT, never in a command line.
export KT045_OWNER="$$"
# no /dev/ptmx (FreeBSD): the fixtures wait on a FIFO of this file instead,
# never on a `sleep` child (it would be listed with them) — launch L2.1
export KT045_FIFO=""
if [[ ! -c /dev/ptmx ]]; then KT045_FIFO="$TMP/nap.fifo"; mkfifo "$KT045_FIFO" 2>/dev/null || KT045_FIFO=""; fi
export KT045_LOOP='{ [[ -c /dev/ptmx ]] && exec 3<>/dev/ptmx; } 2>/dev/null || { [[ -p "$KT045_FIFO" ]] && exec 3<>"$KT045_FIFO"; } 2>/dev/null || exec 3</dev/null; while kill -0 "$KT045_OWNER" 2>/dev/null; do read -t 0.3 -u 3 _ || (( $? > 128 )) || sleep 1; done'

# kt045_pids TEXT — REPLY = the pids (not this shell) whose command line contains TEXT
# kt045_pid0 NAME — REPLY = the pids whose argv[0] is exactly NAME
# (ktest_proc.sh: /proc where there is one, else ps — launch L2.1)
kt045_pids() { kt_proc_pids "$1"; }
kt045_pid0() { kt_proc_pid0 "$1"; }
# kt045_adopted PID — rc 0 once PID has been ADOPTED: its parent is pid 1, or a
# process of another session (a subreaper — `systemd --user`, a container's
# init — took it over; launch L2.1); FreeBSD's `timeout` too (ktest_proc.sh)
kt045_adopted() { kt_proc_adopted "$1"; }
# kt045_cleanup — KILL everything that carries the nonce (twice: a dying
# parent's last fork)
kt045_cleanup() {
    local r
    for r in 1 2; do
        kt045_pids "$N"
        [[ -n "$REPLY" ]] && kill -KILL $REPLY 2>/dev/null
        [[ -n "$REPLY" && "$r" == 1 ]] && sleep 0.2
    done
    return 0
}
# chain the cleanup in front of the framework's EXIT trap; TERM/INT/HUP exit
# so that it runs (bash 5.2 runs no EXIT trap on a signal by itself). The
# first signal ignores the next ones: a second `exit 143` inside the EXIT trap
# ends the cleanup half-way (seen when the runner's group stop still re-sent
# TERM every 0.1 s; the runner and strays.sh stop now TERM once, but a user
# or another tool may not).
eval "$(trap -p EXIT | sed "s/^trap -- '/trap -- 'trap \"\" TERM INT HUP; kt045_cleanup; /")"
[[ "$(trap -p EXIT)" == *kt045_cleanup* ]] || trap 'trap "" TERM INT HUP; kt045_cleanup' EXIT
trap 'trap "" TERM INT HUP; exit 143' TERM
trap 'trap "" TERM INT HUP; exit 130' INT
trap 'trap "" TERM INT HUP; exit 129' HUP

# kt045_orphan NAME [CHILD] — a process named NAME whose parent exits at once
# (an ORPHAN: ppid 1, the session of this file); with CHILD it also runs a
# child named CHILD. Both run KT045_LOOP. Waits until it is reparented.
kt045_orphan() {
    if [[ -n "${2:-}" ]]; then
        bash -c '(exec -a "$1" bash -c "(exec -a \"\$0\" bash -c \"\$KT045_LOOP\") & $KT045_LOOP" "$2") </dev/null >/dev/null 2>&1 & exit' _ "$1" "$2"
    else
        bash -c '(exec -a "$1" bash -c "$KT045_LOOP") </dev/null >/dev/null 2>&1 & exit' _ "$1"
    fi
    local i p pp
    for (( i = 0; i < 50; i++ )); do
        kt045_pid0 "$1"
        p="${REPLY%% *}"
        if [[ -n "$p" ]]; then
            if kt045_adopted "$p"; then
                # with CHILD: its child must have been exec'd too
                [[ -z "${2:-}" ]] && break
                kt045_pid0 "$2"; [[ -n "$REPLY" ]] && break
            fi
        fi
        sleep 0.1
    done
    REPLY="$p"
}
# kt045_row OUT PID — REPLY = the ORPHAN column of PID's row in a `list` OUT
kt045_row() {
    local l
    local -a f
    REPLY=""
    while IFS= read -r l; do
        read -r -a f <<< "$l"
        [[ "${f[0]:-}" == "$2" ]] && { REPLY="${f[3]}"; return 0; }
    done <<< "$1"
    return 1
}
# alive = signallable and no zombie: a KILLed orphan stays a zombie until init
# reaps it — at once on Windows and most systems, seconds later on a stalled VM
# (busybox init on kb-alpine; launch L2.1)
kt045_alive() { kill -0 "$1" 2>/dev/null || return 1; kt_proc_state "$1"; [[ -n "$REPLY" && "$REPLY" != Z ]]; }

# ---- the marker + orphan rules ----------------------------------------------
kt045_orphan "kt_iso-$N-orph"; P_ORPH="$REPLY"
kt045_orphan "nomark-$N-orph"; P_NOMARK="$REPLY"
kt045_orphan "kt_iso-$N-tree" "child-$N-sub"; P_TREE="$REPLY"
kt045_pid0 "child-$N-sub"; P_SUB="$REPLY"
# a LIVE marker parent (this file's child) with a live marker child
bash -c 'exec -a "kt_iso-$1-live" bash -c "(exec -a \"kt_iso-\$0-livechild\" bash -c \"\$KT045_LOOP\") & $KT045_LOOP" "$1"' _ "$N" </dev/null >/dev/null 2>&1 &
P_LIVE=$!
for (( i = 0; i < 50; i++ )); do kt045_pid0 "kt_iso-$N-livechild"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
P_LIVECHILD="$REPLY"

kt_test_start "the fixtures exist: marker orphan, non-marker orphan, orphan tree, live parent + child"
if [[ -n "$P_ORPH" && -n "$P_NOMARK" && -n "$P_TREE" && -n "$P_SUB" && -n "$P_LIVECHILD" ]] && kt045_alive "$P_LIVE"; then
    kt_test_pass "orph=$P_ORPH nomark=$P_NOMARK tree=$P_TREE sub=$P_SUB live=$P_LIVE livechild=$P_LIVECHILD"
else
    kt_test_fail "orph=$P_ORPH nomark=$P_NOMARK tree=$P_TREE sub=$P_SUB live=$P_LIVE livechild=$P_LIVECHILD"
fi

OUT="$(bash "$ST" list --session self --match "$N" 2>&1)"
kt_test_start "list: an orphan with a marker is listed as ORPHAN=yes"
if kt045_row "$OUT" "$P_ORPH" && [[ "$REPLY" == yes ]]; then
    kt_test_pass "row $P_ORPH: $REPLY"
else
    kt_test_fail "no 'yes' row for $P_ORPH in: $OUT"
fi

kt_test_start "list: a non-marker child of an orphan is listed as ORPHAN=sub (it goes with its parent)"
if kt045_row "$OUT" "$P_TREE" && [[ "$REPLY" == yes ]] && kt045_row "$OUT" "$P_SUB" && [[ "$REPLY" == sub ]]; then
    kt_test_pass "tree $P_TREE yes, child $P_SUB sub"
else
    kt_test_fail "tree $P_TREE / child $P_SUB rows wrong in: $OUT"
fi

kt_test_start "list: a live marker child of a live parent is not an orphan (absent by default, ORPHAN=no with --all)"
OUTALL="$(bash "$ST" list --all --session self --match "$N" 2>&1)"
if ! kt045_row "$OUT" "$P_LIVECHILD" && ! kt045_row "$OUT" "$P_LIVE" \
   && kt045_row "$OUTALL" "$P_LIVECHILD" && [[ "$REPLY" == no ]] \
   && kt045_row "$OUTALL" "$P_LIVE" && [[ "$REPLY" == no ]]; then
    kt_test_pass "absent from list, 'no' in list --all"
else
    kt_test_fail "list: $OUT | list --all: $OUTALL"
fi

kt_test_start "list: a process without a marker is never listed (even an orphan, even with --all)"
if ! kt045_row "$OUT" "$P_NOMARK" && ! kt045_row "$OUTALL" "$P_NOMARK"; then
    kt_test_pass "nomark $P_NOMARK not listed"
else
    kt_test_fail "nomark $P_NOMARK listed: $OUTALL"
fi

kt_test_start "library: kt_strays_scan lists the 3 orphan-tree processes (RESULT, KT_STRAYS, flags)"
kt_strays_scan --session self --match "$N"
got="$RESULT: ${KT_STRAYS[*]} flags ${KT_STRAYS_FLAG[$P_ORPH]:-}/${KT_STRAYS_FLAG[$P_TREE]:-}/${KT_STRAYS_FLAG[$P_SUB]:-}"
if [[ "$RESULT" == 3 && "${KT_STRAYS_FLAG[$P_ORPH]:-}" == yes && "${KT_STRAYS_FLAG[$P_SUB]:-}" == sub ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "$got"
fi

# A run whose OWN tree is detached (started from an intermediate that exited:
# an agent's background job — the gate3 failure, 2026-10-16): the strict
# rule saw the run's live children as orphans. The caller's own tree (same
# root) is never detached now.
kt_test_start "a run inside a detached tree: its own live child is not an orphan to it (same root)"
rm -f "$TMP/dt.out"
bash -c '(exec -a "kt_iso-$1-dtroot" bash -c "(exec -a \"kt_iso-\$0-dtchild\" bash -c \"\$KT045_LOOP\") & sleep 0.5; bash \"\$1\" list --all --session self --match \"\$0-dt\" > \"\$2.tmp\" 2>&1; mv \"\$2.tmp\" \"\$2\"; $KT045_LOOP" "$1" "$2" "$3") </dev/null >/dev/null 2>&1 & exit' _ "$N" "$ST" "$TMP/dt.out"
for (( i = 0; i < 100; i++ )); do [[ -s "$TMP/dt.out" ]] && break; sleep 0.1; done
OUTD="$(cat "$TMP/dt.out" 2>/dev/null)"
kt045_pid0 "kt_iso-$N-dtchild"; P_DTC="${REPLY%% *}"
kt045_pid0 "kt_iso-$N-dtroot"; P_DTR="${REPLY%% *}"
pp=""; [[ -n "$P_DTR" ]] && { kt_proc_ppid "$P_DTR"; pp="$REPLY"; kt045_adopted "$P_DTR" && pp=1; }
if [[ -n "$P_DTC" && "$pp" == 1 ]] && kt045_row "$OUTD" "$P_DTC" && [[ "$REPLY" == no ]] && ! kt045_row "$OUTD" "$P_DTR"; then
    kt_test_pass "detached root $P_DTR (ppid 1): its child $P_DTC is ORPHAN=no, the root (an ancestor) not listed"
else
    kt_test_fail "root=$P_DTR ppid=$pp child=$P_DTC | ${OUTD//$'\n'/ | }"
fi
for p in $P_DTC $P_DTR; do kill -KILL "$p" 2>/dev/null; done

kt_test_start "list --since: an orphan started before EPOCH is not listed, one started after it is"
sleep 0.1
T1="$EPOCHREALTIME"
kt045_orphan "kt_iso-$N-late"; P_LATE="$REPLY"
OUTS="$(bash "$ST" list --session self --since "$T1" --match "$N" 2>&1)"
if kt045_row "$OUTS" "$P_LATE" && ! kt045_row "$OUTS" "$P_ORPH" && ! kt045_row "$OUTS" "$P_TREE"; then
    kt_test_pass "only $P_LATE since $T1"
else
    kt_test_fail "since $T1 (late=$P_LATE): $OUTS"
fi

kt_test_start "stop: the orphans and their descendants are gone, rc 0; nothing else is touched"
OUTSTOP="$(bash "$ST" stop --session self --match "$N" 2>&1)"; rc=$?
for (( i = 0; i < 20; i++ )); do kt045_alive "$P_SUB" || break; sleep 0.1; done
gone=""; kept=""
for p in "$P_ORPH" "$P_TREE" "$P_SUB" "$P_LATE"; do kt045_alive "$p" && kept+="$p " || gone+="$p "; done
other=""
for p in "$P_NOMARK" "$P_LIVE" "$P_LIVECHILD"; do kt045_alive "$p" || other+="$p "; done
if [[ "$rc" == 0 && -z "$kept" && -z "$other" ]]; then
    kt_test_pass "gone: $gone; non-marker and live tree still alive"
else
    kt_test_fail "rc=$rc still alive: [$kept] wrongly gone: [$other] | $OUTSTOP"
fi

kt_test_start "stop: a TERM-ignoring orphan is KILLed after 3 s"
bash -c '(trap "" TERM; exec -a "kt_iso-$1-stubborn" bash -c "trap \"\" TERM; $KT045_LOOP") </dev/null >/dev/null 2>&1 & exit' _ "$N"
for (( i = 0; i < 50; i++ )); do kt045_pid0 "kt_iso-$N-stubborn"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
P_STUB="${REPLY%% *}"
sleep 0.3
t0=$SECONDS
OUTSTOP="$(bash "$ST" stop --session self --match "$N" 2>&1)"; rc=$?
dt=$(( SECONDS - t0 ))
if [[ -n "$P_STUB" && "$rc" == 0 ]] && ! kt045_alive "$P_STUB" && (( dt >= 2 )); then
    kt_test_pass "stubborn $P_STUB gone after ${dt}s"
else
    kt_test_fail "stubborn=$P_STUB rc=$rc after ${dt}s alive=$(kt045_alive "$P_STUB" && echo yes || echo no) | $OUTSTOP"
fi

# the live parent is this shell's job: end and reap it quietly (no "Killed" line)
{ kill -KILL "$P_LIVE"; wait "$P_LIVE"; } 2>/dev/null
kt045_cleanup

# _kt_strays_adopt: a target that forks after the scan (its TERM trap starts a
# child) — the child is no marker process and was not listed; without the
# adoption it would outlive the stop (P3b review round 2, critic M4)
kt_test_start "stop: a child a target forks during the grace is KILLed too (adopted)"
printf '%s\n' 'trap '\''(exec -a "adopted-$1" bash -c "$KT045_LOOP") </dev/null >/dev/null 2>&1 &'\'' TERM' \
    'eval "$KT045_LOOP"' > "$TMP/forker.sh"
bash -c '(exec -a "kt_iso-$1-forker" bash "$2" "$1") </dev/null >/dev/null 2>&1 & exit' _ "$N" "$TMP/forker.sh"
for (( i = 0; i < 50; i++ )); do kt045_pid0 "kt_iso-$N-forker"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
P_FORK="${REPLY%% *}"
sleep 0.3
OUTSTOP="$(bash "$ST" stop --session self --match "$N-forker" 2>&1)"; rc=$?
kt045_pid0 "adopted-$N"; P_ADOPT="$REPLY"
if [[ -n "$P_FORK" && "$rc" == 0 && -z "$P_ADOPT" ]] && ! kt045_alive "$P_FORK"; then
    kt_test_pass "forker $P_FORK and the child it forked on TERM are gone"
else
    kt_test_fail "forker=$P_FORK alive=$(kt045_alive "$P_FORK" && echo yes || echo no) adopted child left=[$P_ADOPT] rc=$rc | ${OUTSTOP//$'\n'/ | }"
fi
kt045_cleanup

# SIGKILL delivery lag (gate G2; seen under full-sweep load on 5.3 in G1: a
# target KILLed 20x over 2 s was still alive -> a false "LEFT"). The KILL
# phase of kt_strays_stop runs by the CLOCK (KT_STRAYS_KILL_MS). Proven
# deterministically through a seam, no OS-level trick (review R7: a suspended
# process would outlive a killed test, invisible to strays.sh): a driver
# sources strays.sh and wraps _kt_strays_signal so that a KILL is "not
# delivered" for LAG ms after the first one — the real function still runs
# (with no signal), so the target is counted alive by the identity checks
# (pid + /proc starttime) — then KILLs for real. A: the target "survives"
# 3 s of KILLs inside a 6 s window -> stopped, rc 0, nothing reported (the
# old 20 rounds gave up after ~2 s). B: never delivered, 4 s window -> LEFT
# with its pid only after >= grace (3 s) + 4 s, rc 1; the target really
# alive then, the cleanup ends it.
printf '%s\n' 'source "$1"' \
    'eval "$(declare -f _kt_strays_signal | sed "1s/^_kt_strays_signal/_kt045_real_signal/")"' \
    'LAG=$3 FIRST="" DROPS=0' \
    '_kt_strays_signal() {' \
    '    if [[ "$1" == KILL ]]; then' \
    '        _kt_strays_ms "$EPOCHREALTIME"; [[ -n "$FIRST" ]] || FIRST=$REPLY' \
    '        if (( REPLY - FIRST < LAG )); then DROPS=$(( DROPS + 1 )); _kt045_real_signal "" "${@:2}"; return 0; fi' \
    '    fi' \
    '    _kt045_real_signal "$@"' \
    '}' \
    '# the Windows-side last step (launch L2.7-G) would end B for real: pinned by 057' \
    'kt_proc_winkill() { REPLY=""; return 1; }' \
    '_kt_strays_ms "$EPOCHREALTIME"; t0=$REPLY' \
    'KT_STRAYS_KILL_MS=$4 kt_strays_stop --session self --match "$2"; rc=$?' \
    '_kt_strays_ms "$EPOCHREALTIME"' \
    'echo "rc=$rc ms=$(( REPLY - t0 )) drops=$DROPS left=[${KT_STRAYS[*]}]"' > "$TMP/lag.sh"
kt045_lagger() {   # NAME -> REPLY = the pid of a TERM-ignoring orphan NAME
    bash -c '(trap "" TERM; exec -a "$1" bash -c "trap \"\" TERM; $KT045_LOOP") </dev/null >/dev/null 2>&1 & exit' _ "$1"
    for (( i = 0; i < 50; i++ )); do kt045_pid0 "$1"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
    REPLY="${REPLY%% *}"
}
kt_test_start "stop: KILL is re-sent by the clock — a target whose KILL takes 3 s to land is stopped inside a 6 s window, nothing reported"
kt045_lagger "kt_iso-$N-lagA"; P_LA="$REPLY"
sleep 0.3
o="$(timeout 60 bash "$TMP/lag.sh" "$ST" "$N-lagA" 3000 6000 2>&1)"
for (( i = 0; i < 20; i++ )); do kt045_alive "$P_LA" || break; sleep 0.1; done
if [[ -n "$P_LA" && "$o" =~ ^rc=0\ ms=([0-9]+)\ drops=([0-9]+)\ left=\[\]$ ]] && (( BASH_REMATCH[1] >= 5900 && BASH_REMATCH[2] >= 5 )) \
      && ! kt045_alive "$P_LA"; then
    kt_test_pass "$o"
else
    kt_test_fail "target $P_LA alive=$(kt045_alive "$P_LA" && echo yes || echo no) | $o"
fi
kt045_cleanup
kt_test_start "stop: a target whose KILL never lands is reported LEFT only after the wall-clock window (KT_STRAYS_KILL_MS), with its pid, rc 1"
kt045_lagger "kt_iso-$N-lagB"; P_LB="$REPLY"
sleep 0.3
o="$(timeout 60 bash "$TMP/lag.sh" "$ST" "$N-lagB" 600000 4000 2>&1)"
aB=no; kt045_alive "$P_LB" && aB=yes
if [[ -n "$P_LB" && "$o" =~ ^rc=1\ ms=([0-9]+)\ drops=([0-9]+)\ left=\[$P_LB\]$ ]] && (( BASH_REMATCH[1] >= 6900 && BASH_REMATCH[1] <= 20000 )) \
      && [[ "$aB" == yes ]]; then
    kt_test_pass "$o (target still alive: the seam held its KILLs)"
else
    kt_test_fail "target $P_LB alive=$aB | $o"
fi
kt045_cleanup

# A parent killed at the WINDOWS level (taskkill /F, Task Manager, an agent's
# stopped background task): cygwin keeps the dead pid as the child's ppid —
# no ppid 1. The root walk treats a parent missing from /proc like ppid 1
# (P3b review round 2, F7).
TKX="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}" 2>/dev/null)/System32/taskkill.exe"
if [[ -x "$TKX" ]]; then
    kt_test_start "a parent killed by taskkill /F (ppid stays the dead pid): its child is an orphan, and stop ends it"
    bash -c '(exec -a "kt_iso-$1-wkchild" bash -c "$KT045_LOOP") </dev/null >/dev/null 2>&1 & wait' _ "$N" </dev/null >/dev/null 2>&1 &
    P_WK=$!
    for (( i = 0; i < 50; i++ )); do kt045_pid0 "kt_iso-$N-wkchild"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
    P_WKC="${REPLY%% *}"
    w=""; { read -r w < "/proc/$P_WK/winpid"; } 2>/dev/null
    [[ -n "$w" ]] && MSYS2_ARG_CONV_EXCL='*' "$TKX" /F /PID "$w" >/dev/null 2>&1
    { wait "$P_WK"; } 2>/dev/null
    for (( i = 0; i < 30; i++ )); do [[ -e "/proc/$P_WK/stat" ]] || break; sleep 0.1; done
    pp=""; [[ -n "$P_WKC" ]] && { read -r pp < "/proc/$P_WKC/ppid"; } 2>/dev/null
    OUTW="$(bash "$ST" list --session self --match "$N-wkchild" 2>&1)"
    f1=""; kt045_row "$OUTW" "$P_WKC" && f1="$REPLY"
    OUTSTOP="$(bash "$ST" stop --session self --match "$N-wkchild" 2>&1)"; rc=$?
    if [[ -n "$w" && -n "$P_WKC" && "$pp" == "$P_WK" && "$f1" == yes && "$rc" == 0 ]] && ! kt045_alive "$P_WKC"; then
        kt_test_pass "parent $P_WK (winpid $w) killed: child $P_WKC keeps ppid $pp, ORPHAN=yes, stopped"
    else
        kt_test_fail "parent $P_WK winpid=$w child=$P_WKC ppid=$pp flag=[$f1] stop rc=$rc | ${OUTW//$'\n'/ | }"
    fi
    kt045_cleanup
fi

# An orphaned ktests run whose test file has a cleanup: `stop` TERMs the
# tree's ROOT once (the orphaned ktests.sh stops its own group) and waits; a
# TERM re-sent every 0.1 s to every process cut the cleanups short (P3b
# review round 2, F9; the critic's rs probe). One file: the run is sequential.
kt_test_start "stop: an orphaned ktests run is TERMed once at its root — the test file's cleanup completes, nothing is left"
mkdir -p "$TMP/rs" "$TMP/rs.tmp"
printf '%s\n' 'source "$KTEST_SOURCE_PATH"' 'kt_test_init R "$KT_TESTS_DIR"' 'kt_test_start r' \
    "trap 'if [[ -c /dev/ptmx ]] && exec {w}<>/dev/ptmx; then read -t 0.8 -u \$w _; else sleep 0.8; fi; echo done >> \"$TMP/rs.clean\"' EXIT; trap 'exit 143' TERM" \
    "echo \$BASHPID > '$TMP/rs.up'" \
    "bash -c 'exec -a rsloop-$N bash -c \"\$KT045_LOOP\"' & wait" 'kt_test_pass r' > "$TMP/rs/001_r.sh"
rm -f "$TMP/rs.clean" "$TMP/rs.up"
TMPDIR="$TMP/rs.tmp" bash -c '(env -u KTESTS_LIB_DIR bash "$1/ktests.sh" "$2" RS "/[0-9][0-9][0-9]_" -m single </dev/null >/dev/null 2>&1 &); exit' _ "$LIB" "$TMP/rs"
for (( i = 0; i < 150; i++ )); do [[ -s "$TMP/rs.up" ]] && break; sleep 0.1; done
# rs.up is written BEFORE the loop is spawned: wait for the loop itself (a
# single look raced it — gate5: loop=[] in 3 of 10 runs)
for (( i = 0; i < 100; i++ )); do kt045_pid0 "rsloop-$N"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
P_RSL="$REPLY"
sleep 0.3
OUTSTOP="$(bash "$ST" stop --session self --match "$TMP/rs" 2>&1)"; rc=$?
sleep 0.5
kt045_pids "$TMP/rs"; l1="$REPLY"; kt045_pid0 "rsloop-$N"; l2="$REPLY"
clean="$(cat "$TMP/rs.clean" 2>/dev/null)"
tmpleft="$(ls -A "$TMP/rs.tmp" 2>/dev/null)"
if [[ -n "$P_RSL" && "$rc" == 0 && "$clean" == done && -z "$l1" && -z "$l2" && -z "$tmpleft" ]]; then
    kt_test_pass "cleanup ran (done), run gone, TMPDIR empty"
else
    kt_test_fail "loop=[$P_RSL] rc=$rc clean=[$clean] left=[$l1|$l2] tmp=[$tmpleft] | ${OUTSTOP//$'\n'/ | }"
fi
kt045_pids "$TMP/rs"; [[ -n "$REPLY" ]] && kill -KILL $REPLY 2>/dev/null
kt045_cleanup

kt_test_start "stop: nothing to stop is rc 0; stop refuses --all"
out1="$(bash "$ST" stop --match "$N-none" 2>&1)"; rc1=$?
out2="$(bash "$ST" stop --all --match "$N" 2>&1)"; rc2=$?
if [[ "$rc1" == 0 && "$out1" == *"none to stop"* && "$rc2" == 2 ]]; then
    kt_test_pass "rc $rc1 / $rc2"
else
    kt_test_fail "rc1=$rc1 [$out1] rc2=$rc2 [$out2]"
fi

# a session leader whose parent is gone (what a program started from Windows
# looks like: ppid 1, sid == pid) is not an orphan — needs setsid (MSYS2 only)
if command -v setsid >/dev/null 2>&1; then
    kt_test_start "orphan rule: a session leader with ppid 1 (sid == pid) is not an orphan"
    # `setsid … &` from a shell without job control: no group leader, so
    # setsid() needs no fork (util-linux and busybox alike: busybox has no -f)
    bash -c 'echo $$ > "$2"; setsid bash -c "exec -a \"kt_iso-$1-leader\" bash -c \"\$KT045_LOOP\"" </dev/null >/dev/null 2>&1 & exit' _ "$N" "$TMP/leader.parent"
    for (( i = 0; i < 50; i++ )); do kt045_pid0 "kt_iso-$N-leader"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
    P_LEAD="${REPLY%% *}"
    sleep 0.3
    OUTL="$(bash "$ST" list --all --match "$N-leader" 2>&1)"
    st=( "" "" "" "" "" "" ); kt_proc_ppid "$P_LEAD"; st[3]="$REPLY"; kt_proc_sid "$P_LEAD"; st[5]="$REPLY"
    # its parent (the shell that started it) is gone: ppid 1 — or, on a system
    # with a subreaper, adopted by it AND that original parent no longer alive
    pl=""; { read -r pl < "$TMP/leader.parent"; } 2>/dev/null
    ad=no
    if [[ "${st[3]:-}" == 1 ]]; then ad=yes
    elif [[ -n "$P_LEAD" && -n "$pl" && "${st[3]:-}" != "$pl" ]] && ! kill -0 "$pl" 2>/dev/null && kt045_adopted "$P_LEAD"; then ad=yes; fi
    if [[ -n "$P_LEAD" ]] && kt045_row "$OUTL" "$P_LEAD" && [[ "$REPLY" == no && "$ad" == yes && "${st[5]:-}" == "$P_LEAD" ]]; then
        kt_test_pass "leader $P_LEAD: ppid 1, sid $P_LEAD, ORPHAN=no"
    else
        kt_test_fail "leader $P_LEAD stat ppid=${st[3]:-} (parent was $pl) sid=${st[5]:-}: $OUTL"
    fi
    kt045_pids "kt_iso-$N-leader"; [[ -n "$REPLY" ]] && kill -KILL $REPLY 2>/dev/null
fi
kt045_cleanup

# ---- the ktests run groups: a test file's background process ---------------
mkdir -p "$TMP/grp"
for n in 001 002; do
    printf '%s\n' "source \"\$KTEST_SOURCE_PATH\"" \
        "kt_test_init \"G$n\" \"\$KT_TESTS_DIR\"" \
        "kt_test_start \"g$n\"" \
        "bash -c 'exec -a kt_iso-$N-grp$n bash -c \"\$KT045_LOOP\"' </dev/null >/dev/null 2>&1 &" \
        "kt_test_pass \"g$n\"" > "$TMP/grp/${n}_g.sh"
done
for mode in single threaded; do
    kt_test_start "$mode: a test file's leaked background process is named in a [WARN] and stopped at the end of the run"
    mkdir -p "$TMP/grp.tmp.$mode"
    out="$(TMPDIR="$TMP/grp.tmp.$mode" timeout 120 env -u KTESTS_LIB_DIR bash "$LIB/ktests.sh" "$TMP/grp" G '/[0-9][0-9][0-9]_' -m "$mode" -w 2 2>&1)"; rc=$?
    sleep 0.2
    kt045_pids "kt_iso-$N-grp"; left="$REPLY"
    warn="$(grep -a '^\[WARN\].*left after the run' <<< "$out")"
    if [[ "$rc" == 0 && -z "$left" && "$warn" == *"kt_iso-$N-grp001"* && "$warn" == *"kt_iso-$N-grp002"* ]]; then
        kt_test_pass "rc 0, nothing left: $warn"
    else
        kt_test_fail "rc=$rc left=[$left] warn=[$warn]"
    fi
    kt045_cleanup
done

kt_test_start "a clean run prints no group [WARN]"
mkdir -p "$TMP/clean"
printf '%s\n' "source \"\$KTEST_SOURCE_PATH\"" "kt_test_init \"C\" \"\$KT_TESTS_DIR\"" \
    "kt_test_start \"c\"" "kt_test_pass \"c\"" > "$TMP/clean/001_c.sh"
out="$(TMPDIR="$TMP/grp.tmp.single" timeout 120 env -u KTESTS_LIB_DIR bash "$LIB/ktests.sh" "$TMP/clean" C '/[0-9][0-9][0-9]_' -m single 2>&1)"; rc=$?
if [[ "$rc" == 0 && "$out" != *"[WARN]"* ]]; then
    kt_test_pass "rc 0, no WARN"
else
    kt_test_fail "rc=$rc out: $out"
fi

# ---- the master sweep: suites that leave an orphan ---------------------------
# A fake kbool root: a copy of the master sweep and of ktests' library, one
# suite whose tests.sh leaves a MARKER orphan, one that leaves a NON-marker
# orphan (a plain leaked process: the sweep's --session + --since needs no
# marker, P3b review round 2, F4), one clean suite.
F="$TMP/root"
mkdir -p "$F/ktests/tools" "$F/tests" "$F/a_leaky/tests" "$F/b_clean/tests" "$F/c_nonmark/tests"
cp "$LIB"/*.sh "$F/ktests/"
cp "$ST" "$LIB/tools/suitejob.sh" "$F/ktests/tools/"   # the master sources both (gate G1)
cp "$ROOT/tests/tests.sh" "$F/tests/tests.sh"
printf '%s\n' '#!/bin/bash' \
    "bash -c '(exec -a kt_iso-$N-leak bash -c \"\$KT045_LOOP\") </dev/null >/dev/null 2>&1 & exit'" \
    'echo "leaky suite done"' 'exit 0' > "$F/a_leaky/tests/tests.sh"
printf '%s\n' '#!/bin/bash' 'echo "clean suite done"' 'exit 0' > "$F/b_clean/tests/tests.sh"
printf '%s\n' '#!/bin/bash' \
    "bash -c '(exec -a nm-$N-leak bash -c \"\$KT045_LOOP\") </dev/null >/dev/null 2>&1 & exit'" \
    'echo "non-marker leaky suite done"' 'exit 0' > "$F/c_nonmark/tests/tests.sh"

kt_test_start "master sweep: each suite's orphan (marker or not) is reported with the suite, stopped, and the sweep FAILS"
out="$(KT_STRAYS_MATCH="$N" timeout 120 env -u KTESTS_LIB_DIR bash "$F/tests/tests.sh" 2>&1)"; rc=$?
sleep 0.2
kt045_pids "$N-leak"; left="$REPLY"
if [[ "$rc" == 1 && -z "$left" \
      && "$out" == *"[WARN] 1 stray process(es) found after "*"/a_leaky/tests/tests.sh:"* \
      && "$out" == *"started during "*"/a_leaky/tests/tests.sh: kt_iso-$N-leak"* \
      && "$out" == *"[WARN] 1 stray process(es) found after "*"/c_nonmark/tests/tests.sh:"* \
      && "$out" == *"started during "*"/c_nonmark/tests/tests.sh: nm-$N-leak"* \
      && "$out" == *"[WARN] 2 stray process(es) left by the sweep:"* \
      && "$out" == *"/a_leaky/tests/tests.sh (left stray processes)"* \
      && "$out" == *"/c_nonmark/tests/tests.sh (left stray processes)"* \
      && "$out" == *"Passed: 1"* && "$out" == *"Failed: 2"* ]]; then
    kt_test_pass "rc 1, both leaky suites named and failed, nothing left"
else
    kt_test_fail "rc=$rc left=[$left] out: ${out//$'\n'/ | }"
fi
kt045_cleanup

kt_test_start "master sweep: without a leak the stray guard is silent and the sweep passes"
rm -rf "$F/a_leaky" "$F/c_nonmark"
# e_trap: the suite sets its own INT trap and reads the sweep's stdin (P3b
# review round 2, N1: a `&` job without job control starts with SIGINT
# IGNORED — untrappable — and stdin /dev/null; kcl/thttpserver 006 failed)
mkdir -p "$F/e_trap/tests"
printf '%s\n' '#!/bin/bash' "trap ': kt045 int' INT; trap -p INT > '$TMP/n1.int'" \
    "IFS= read -r -t 5 l; printf '%s' \"\$l\" > '$TMP/n1.stdin'" 'exit 0' > "$F/e_trap/tests/tests.sh"
rm -f "$TMP/n1.int" "$TMP/n1.stdin"
out="$(printf 'kt045-stdin-line\n' | KT_STRAYS_MATCH="$N" timeout 120 env -u KTESTS_LIB_DIR bash "$F/tests/tests.sh" 2>&1)"; rc=$?
if [[ "$rc" == 0 && "$out" != *"[WARN]"* && "$out" == *"All test suites passed."* ]]; then
    kt_test_pass "rc 0, no stray line"
else
    kt_test_fail "rc=$rc out: ${out//$'\n'/ | }"
fi
kt_test_start "master sweep: a suite keeps its own INT trap (not SIG_IGN) and the sweep's stdin"
i1="$(cat "$TMP/n1.int" 2>/dev/null)"; s1="$(cat "$TMP/n1.stdin" 2>/dev/null)"
if [[ "$i1" == *"': kt045 int'"* && "$s1" == kt045-stdin-line ]]; then
    kt_test_pass "$i1; stdin [$s1]"
else
    kt_test_fail "INT trap [$i1] (want ': kt045 int'), stdin [$s1]"
fi
rm -rf "$F/e_trap"

# the caller and its ancestors are never listed — not even a marker-named
# parent of the CLI (a tool shell whose command line holds the repo path)
kt_test_start "list --all never shows the caller's own parent (a marker process)"
bash -c 'exec -a "kt_iso-$1-caller" bash -c "bash \"\$1\" list --all --match \"\$0\" > \"\$2\" 2>&1; :" "$1" "$2" "$3"' _ "$N" "$ST" "$TMP/caller.out"
oc="$(cat "$TMP/caller.out" 2>/dev/null)"
if [[ "$oc" == "strays: none"* ]]; then
    kt_test_pass "$oc"
else
    kt_test_fail "${oc//$'\n'/ | }"
fi

# S1 (round 6, DT12): a caller whose command line carries a marker (here the
# repo path followed by `/`, as an agent's tool shell running `cd REPO && …`)
# PIPES the CLI's output: the pipeline's other element is a FORK of the caller
# (a compound consumer stays one for its life) — a sibling of strays.sh, not an
# ancestor, with the caller's command line. It was listed as a live row.
# busybox's timeout is no parent of its command: it execs the command and
# leaves a WATCHER process (`timeout 60 bash …strays.sh …` in its command line,
# a marker) beside it — a live non-ancestor the listing rightly shows; the
# shape is GNU/BSD timeout's (launch L2.1)
kt045_bbtmo=0; [[ "$(timeout --help 2>&1)" == *BusyBox* ]] && kt045_bbtmo=1
for shape in while group timeout; do
    kt_test_start "list --all from a marker caller piping its output ($shape) shows no row for the caller's own fork"
    if [[ "$shape" == timeout ]] && (( kt045_bbtmo )); then
        kt_test_pass "skipped: busybox timeout (a watcher beside the command, not its parent)"
        continue
    fi
    rm -f "$TMP/pipe.out"
    case "$shape" in
        while)   c="bash '$ST' list --all --match '$N-pipe' 2>&1 | while IFS= read -r l; do echo \"\$l\"; done > '$TMP/pipe.out'" ;;
        group)   c="bash '$ST' list --all --match '$N-pipe' 2>&1 | { cat; } > '$TMP/pipe.out'" ;;
        timeout) c="timeout 60 bash '$ST' list --all --match '$N-pipe' 2>&1 | while IFS= read -r l; do echo \"\$l\"; done > '$TMP/pipe.out'" ;;
    esac
    bash -c "cd '$ROOT' && $c" </dev/null >/dev/null 2>&1
    op="$(cat "$TMP/pipe.out" 2>/dev/null)"
    if [[ "$c" == *"$ROOT/"* && "$op" == "strays: none"* ]]; then
        kt_test_pass "$op"
    else
        kt_test_fail "${op//$'\n'/ | }"
    fi
done

# ... but the caller's OWN live background jobs carry the same command line and
# are children of the self chain too: they are listed (ORPHAN=no) — a leak made
# in the same call must show (review F4). One `{ …; } &` (stdin /dev/null) and
# one `: | { …; } &` (stdin a pipe, but not the one strays.sh writes into);
# the pipe reader itself (it records its pid) is not listed.
kt_test_start "list --all from a marker caller: its own '{ …; } &' jobs ARE listed (ORPHAN=no), its pipe reader is not"
rm -f "$TMP/own.out" "$TMP/own.pids"
c="{ eval \"\$KT045_LOOP\"; } </dev/null >/dev/null 2>&1 & J1=\$!; : | { eval \"\$KT045_LOOP\"; } >/dev/null 2>&1 & J2=\$!; bash '$ST' list --all --match '$N-own' 2>&1 | { echo \"\$J1 \$J2 \$BASHPID\" > '$TMP/own.pids'; while IFS= read -r l; do echo \"\$l\"; done; } > '$TMP/own.out'; kill -KILL \$J1 \$J2 2>/dev/null"
bash -c "cd '$ROOT' && $c" </dev/null >/dev/null 2>&1
oo="$(cat "$TMP/own.out" 2>/dev/null)"
read -r J1 J2 JR < "$TMP/own.pids" 2>/dev/null
f1=""; f2=""; fr=""
[[ -n "${J1:-}" ]] && kt045_row "$oo" "$J1" && f1="$REPLY"
[[ -n "${J2:-}" ]] && kt045_row "$oo" "$J2" && f2="$REPLY"
[[ -n "${JR:-}" ]] && kt045_row "$oo" "$JR" && fr="$REPLY"
if [[ -n "${JR:-}" && "$f1" == no && "$f2" == no && -z "$fr" ]]; then
    kt_test_pass "job $J1: $f1, job $J2 (piped stdin): $f2, reader $JR not listed"
else
    kt_test_fail "job1=${J1:-} [$f1] job2=${J2:-} [$f2] reader=${JR:-} [$fr] | ${oo//$'\n'/ | }"
fi
kt045_cleanup

# ... and the exclusion never hides a real orphan: one with the SAME command
# line as the live caller (a fork of an earlier run of the same text whose
# parent exited) is still listed, while the caller's own fork is not
kt_test_start "an orphan with the same command line as the live caller is still listed (only the caller's own fork is excluded)"
rm -f "$TMP/same.out"
c=": kt_iso-$N-same; if [[ -n \${KT045_SAME_ORPH:-} ]]; then ( eval \"\$KT045_LOOP\" ) </dev/null >/dev/null 2>&1 & exit 0; fi; bash '$ST' list --all --session self --match '$N-same' 2>&1 | while IFS= read -r l; do echo \"\$l\"; done > '$TMP/same.out'"
KT045_SAME_ORPH=1 bash -c "$c" </dev/null >/dev/null 2>&1
P_SAME=""
for (( i = 0; i < 50; i++ )); do
    kt045_pids "$N-same"
    for p in $REPLY; do
        kt045_adopted "$p" && P_SAME="$p"
    done
    [[ -n "$P_SAME" ]] && break
    sleep 0.1
done
bash -c "$c" </dev/null >/dev/null 2>&1
os="$(cat "$TMP/same.out" 2>/dev/null)"
nrow=0
while IFS= read -r l; do [[ "$l" =~ ^\ *[0-9]+\  ]] && (( ++nrow )); done <<< "$os"
if [[ -n "$P_SAME" && "$nrow" == 1 ]] && kt045_row "$os" "$P_SAME" && [[ "$REPLY" == yes ]]; then
    kt_test_pass "orphan $P_SAME (ppid 1, the caller's command line): ORPHAN=yes, the only row"
else
    kt_test_fail "orphan=[$P_SAME] rows=$nrow | ${os//$'\n'/ | }"
fi
[[ -n "$P_SAME" ]] && kill -KILL "$P_SAME" 2>/dev/null
kt045_cleanup

kt_test_start "the unfiltered age limit defaults to 120 min (longer than a full sweep)"
hlp="$(bash "$ST" --help 2>&1)"
if [[ "${KT_STRAYS_OLDER_DEFAULT:-}" == 120 && "$hlp" == *"120"* ]]; then
    kt_test_pass "KT_STRAYS_OLDER_DEFAULT=120"
else
    kt_test_fail "KT_STRAYS_OLDER_DEFAULT=[${KT_STRAYS_OLDER_DEFAULT:-}]"
fi

# TERM to the sweep or to a suite wrapper (P3b review round 2, F5): the sweep
# runs each suite as a background job under TERM/INT/HUP traps that stop it;
# the wrappers `exec` ktests.sh (the real kkore wrapper is used here), so a
# TERM to the wrapper pid lands on ktests.sh's own trap.
mkdir -p "$F/d_slow/tests"
cp "$ROOT/kkore/tests/tests.sh" "$F/d_slow/tests/tests.sh"
for n in 001 002; do
    printf '%s\n' 'source "$KTEST_SOURCE_PATH"' "kt_test_init D$n \"\$KT_TESTS_DIR\"" 'kt_test_start d' \
        "bash -c 'exec -a slow-$N-$n bash -c \"\$KT045_LOOP\"' & wait" 'kt_test_pass d' > "$F/d_slow/tests/${n}_d.sh"
done
for who in sweep wrapper; do
    kt_test_start "TERM to the $who while a suite runs: nothing of the run is left"
    mkdir -p "$TMP/f5.$who"
    KT_STRAYS_MATCH="$N" TMPDIR="$TMP/f5.$who" env -u KTESTS_LIB_DIR bash "$F/tests/tests.sh" > "$TMP/f5.$who.out" 2>&1 &
    P_M=$!
    for (( i = 0; i < 200; i++ )); do kt045_pids "slow-$N-"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
    sleep 0.5
    tgt="$P_M"
    if [[ "$who" == wrapper ]]; then
        tgt=""
        kt045_pids "$F/d_slow/tests"
        for p in $REPLY; do
            kt_proc_ppid "$p"
            [[ "$REPLY" == "$P_M" ]] && tgt="$p"
        done
    fi
    [[ -n "$tgt" ]] && kill -TERM "$tgt"
    for (( i = 0; i < 300; i++ )); do kill -0 "$P_M" 2>/dev/null || break; sleep 0.1; done
    kill -0 "$P_M" 2>/dev/null && kill -KILL "$P_M" 2>/dev/null
    wait "$P_M" 2>/dev/null; rc=$?
    sleep 0.5
    kt045_pids "slow-$N-"; l1="$REPLY"; kt045_pids "$F/"; l2="$REPLY"
    o="$(cat "$TMP/f5.$who.out" 2>/dev/null)"
    want=1; [[ "$who" == sweep ]] && want=143
    if [[ -n "$tgt" && "$rc" == "$want" && -z "$l1" && -z "$l2" ]] \
       && { [[ "$who" == wrapper ]] || [[ "$o" == *"[WARN] the sweep was interrupted (exit 143)"* ]]; }; then
        kt_test_pass "TERM to $tgt: sweep rc $rc, nothing left"
    else
        kt_test_fail "target=[$tgt] rc=$rc (want $want) left=[$l1|$l2] | ${o//$'\n'/ | }"
    fi
    kt045_pids "$F/"; [[ -n "$REPLY" ]] && kill -KILL $REPLY 2>/dev/null
    kt045_cleanup
done

kt_test_start "an owner-tied fixture ends by itself when its owner is SIGKILLed (no trap runs)"
bash -c 'sleep 30' </dev/null >/dev/null 2>&1 &
P_OWN=$!
KT045_OWNER="$P_OWN" bash -c '(trap "" TERM; exec -a "kt_iso-$1-owned" bash -c "trap \"\" TERM; $KT045_LOOP") </dev/null >/dev/null 2>&1 & exit' _ "$N"
for (( i = 0; i < 50; i++ )); do kt045_pid0 "kt_iso-$N-owned"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
P_OWNED="${REPLY%% *}"
sleep 0.5
a1=no; [[ -n "$P_OWNED" ]] && kt045_alive "$P_OWNED" && a1=yes
{ kill -KILL "$P_OWN"; wait "$P_OWN"; } 2>/dev/null
for (( i = 0; i < 30; i++ )); do kt045_alive "$P_OWNED" || break; sleep 0.1; done
a2=no; kt045_alive "$P_OWNED" && a2=yes
if [[ -n "$P_OWNED" && "$a1" == yes && "$a2" == no ]]; then
    kt_test_pass "fixture $P_OWNED alive with its owner, gone $(( i * 100 )) ms after the owner's SIGKILL"
else
    kt_test_fail "fixture '$P_OWNED' alive before=$a1 after=$a2"
fi

kt045_cleanup

# ---- unfiltered list/stop: age and session leader decide (P3b, review 2) -----
# A NEW session needs a process without a cygwin parent: cmd.exe starts the
# leader bash. leader_live.sh runs `( timeout 60 … ) &` from an intermediate
# that exits (detached, its leader alive) and then stays as
# kt_iso-N-sleader — a MARKER process with ppid 1 and sid == pid, which the
# sid != pid half of the orphan rule must keep ORPHAN=no (critic M1: only
# the setsid case covered it, on 5.3). leader_gone.sh starts a fixture and
# exits (detached, leader dead — an agent's background run once its tool
# shell has exited: unfiltered it is `young` until --older-than).
CMDX="$(cygpath -u "${SYSTEMROOT:-C:\Windows}" 2>/dev/null)/System32/cmd.exe"
WB="$(cygpath -w "$BASH" 2>/dev/null)"
if [[ -x "$CMDX" && -n "$WB" ]]; then
    printf '%s\n' \
        'bash -c '\''( timeout 60 bash -c "exec -a \"kt_iso-$1-bgrun\" bash -c \"\$KT045_LOOP\"" ) </dev/null >/dev/null 2>&1 & exit'\'' _ "$1"' \
        'exec -a "kt_iso-$1-sleader" bash -c "$KT045_LOOP"' > "$TMP/leader_live.sh"
    printf '%s\n' \
        '(exec -a "kt_iso-$1-abandoned" bash -c "$KT045_LOOP") </dev/null >/dev/null 2>&1 &' \
        '(exec timeout -s TERM 8 bash -c '\''trap "" TERM; exec -a "kt_iso-$0-tmochild" bash -c "$KT045_LOOP"'\'' "$1") </dev/null >/dev/null 2>&1 &' \
        'exit 0' > "$TMP/leader_gone.sh"
    MSYS2_ARG_CONV_EXCL='*' "$CMDX" /c "$WB" "$(cygpath -w "$TMP/leader_live.sh")" "$N" </dev/null >/dev/null 2>&1 &
    P_CMD=$!
    MSYS2_ARG_CONV_EXCL='*' "$CMDX" /c "$WB" "$(cygpath -w "$TMP/leader_gone.sh")" "$N" </dev/null >/dev/null 2>&1
    T_GONE=$SECONDS
    P_BG="" P_LEAD="" P_ABAN="" P_TMO="" P_TC="" P_TR=""
    for (( i = 0; i < 100; i++ )); do
        kt045_pid0 "kt_iso-$N-bgrun"; P_BG="${REPLY%% *}"
        kt045_pid0 "kt_iso-$N-sleader"; P_LEAD="${REPLY%% *}"
        kt045_pid0 "kt_iso-$N-abandoned"; P_ABAN="${REPLY%% *}"
        P_TMO=""; [[ -n "$P_BG" ]] && { read -r P_TMO < "/proc/$P_BG/ppid"; } 2>/dev/null
        tp=""; [[ -n "$P_TMO" ]] && { read -r tp < "/proc/$P_TMO/ppid"; } 2>/dev/null
        kt045_pid0 "kt_iso-$N-tmochild"; P_TC="${REPLY%% *}"
        P_TR=""; [[ -n "$P_TC" ]] && { read -r P_TR < "/proc/$P_TC/ppid"; } 2>/dev/null
        [[ -n "$P_BG" && -n "$P_LEAD" && -n "$P_ABAN" && -n "$P_TC" && "$tp" == 1 ]] && break
        sleep 0.1
    done
    OUTU="$(bash "$ST" list --all --match "$N" 2>&1)"
    kt_test_start "unfiltered list: leader alive -> live-session; leader gone but young -> young; the marker session leader itself (ppid 1, sid == pid) -> no"
    f1=""; f2=""; f3=""
    kt045_row "$OUTU" "$P_BG" && f1="$REPLY"
    kt045_row "$OUTU" "$P_ABAN" && f2="$REPLY"
    kt045_row "$OUTU" "$P_LEAD" && f3="$REPLY"
    if [[ -n "$P_LEAD" && "$f1" == live-session && "$f2" == young && "$f3" == no ]]; then
        kt_test_pass "bgrun $P_BG (root timeout $P_TMO): $f1; abandoned $P_ABAN: $f2; leader $P_LEAD: $f3"
    else
        kt_test_fail "leader=$P_LEAD [$f3] bgrun=$P_BG [$f1] abandoned=$P_ABAN [$f2] | ${OUTU//$'\n'/ | }"
    fi
    kt_test_start "unfiltered stop: stops nothing young or live-session"
    OUTU="$(bash "$ST" stop --match "$N" 2>&1)"; rc=$?
    if [[ "$rc" == 0 && "$OUTU" == *"none to stop"* ]] && kt045_alive "$P_ABAN" && kt045_alive "$P_BG" && kt045_alive "$P_LEAD"; then
        kt_test_pass "abandoned, bgrun and leader alive: ${OUTU//$'\n'/ | }"
    else
        kt_test_fail "rc=$rc abandoned alive=$(kt045_alive "$P_ABAN" && echo yes || echo no) bgrun alive=$(kt045_alive "$P_BG" && echo yes || echo no) | ${OUTU//$'\n'/ | }"
    fi
    kt_test_start "unfiltered stop --older-than 0: stops the tree whose leader is gone, never the live-session run or the leader"
    OUTU="$(bash "$ST" stop --older-than 0 --match "$N" 2>&1)"; rc=$?
    for (( i = 0; i < 20; i++ )); do kt045_alive "$P_ABAN" || break; sleep 0.1; done
    if [[ "$rc" == 0 && -n "$P_ABAN" && -n "$P_BG" ]] && ! kt045_alive "$P_ABAN" && kt045_alive "$P_BG" && kt045_alive "$P_TMO" && kt045_alive "$P_LEAD"; then
        kt_test_pass "abandoned $P_ABAN gone; bgrun $P_BG, its timeout and the leader alive"
    else
        kt_test_fail "rc=$rc abandoned $P_ABAN alive=$(kt045_alive "$P_ABAN" && echo yes || echo no) bgrun $P_BG alive=$(kt045_alive "$P_BG" && echo yes || echo no) | ${OUTU//$'\n'/ | }"
    fi
    kt_test_start "stop --session LEADER (the strict rule): the live background run is stopped, the leader is not"
    OUTU="$(bash "$ST" stop --session "$P_LEAD" --match "$N" 2>&1)"; rc=$?
    for (( i = 0; i < 20; i++ )); do kt045_alive "$P_BG" || break; sleep 0.1; done
    if [[ "$rc" == 0 && -n "$P_BG" ]] && ! kt045_alive "$P_BG" && kt045_alive "$P_LEAD"; then
        kt_test_pass "bgrun $P_BG gone; leader $P_LEAD (a marker session leader) untouched"
    else
        kt_test_fail "rc=$rc bgrun $P_BG alive=$(kt045_alive "$P_BG" && echo yes || echo no) leader alive=$(kt045_alive "$P_LEAD" && echo yes || echo no) | ${OUTU//$'\n'/ | }"
    fi
    # a tree rooted at `timeout 8` (its leader gone; the child ignores the TERM
    # timeout sends at 8 s, so the tree lives on): young until 8 s + 10 s have
    # passed even with --older-than 0, then yes (P3b review round 2, N2)
    kt_test_start "unfiltered: a tree rooted at 'timeout 8' is young until 8 s + 10 s have passed, then an orphan that stop ends"
    OUTT="$(bash "$ST" list --all --older-than 0 --match "$N" 2>&1)"
    f1=""; f2=""
    kt045_row "$OUTT" "$P_TR" && f1="$REPLY"
    kt045_row "$OUTT" "$P_TC" && f2="$REPLY"
    a1=$(( SECONDS - T_GONE ))
    f3=""
    for (( i = 0; i < 300; i++ )); do
        OUTT="$(bash "$ST" list --older-than 0 --match "$N" 2>&1)"
        kt045_row "$OUTT" "$P_TC" && { f3="$REPLY"; break; }
        sleep 0.1
    done
    a2=$(( SECONDS - T_GONE ))
    OUTU="$(bash "$ST" stop --older-than 0 --match "$N" 2>&1)"; rc=$?
    for (( i = 0; i < 30; i++ )); do kt045_alive "$P_TC" || break; sleep 0.1; done
    if [[ -n "$P_TC" && "$f1" == young && "$f2" == young && "$a1" -lt 17 && "$f3" == yes && "$a2" -ge 17 && "$rc" == 0 ]] \
       && ! kt045_alive "$P_TC" && ! kt045_alive "$P_TR"; then
        kt_test_pass "timeout root $P_TR + child $P_TC: young at ${a1}s, yes at ${a2}s, stopped"
    else
        kt_test_fail "root=$P_TR [$f1] child=$P_TC [$f2] at ${a1}s; [$f3] at ${a2}s; stop rc=$rc child alive=$(kt045_alive "$P_TC" && echo yes || echo no) | ${OUTU//$'\n'/ | }"
    fi
    # end the leader first: cmd.exe (this shell's job) then exits by itself
    [[ -n "$P_LEAD" ]] && kill -KILL "$P_LEAD" 2>/dev/null
    for (( i = 0; i < 30; i++ )); do kill -0 "$P_CMD" 2>/dev/null || break; sleep 0.1; done
    { kill -KILL "$P_CMD"; wait "$P_CMD"; } 2>/dev/null
    kt045_cleanup
else
    kt_test_start "unfiltered list/stop and the session leader"
    kt_test_pass "skipped: no cmd.exe ($CMDX) or cygpath"
fi

kt045_cleanup
kt_test_start "nothing that carries this file's nonce is left"
kt045_pids "$N"
if [[ -z "$REPLY" ]]; then
    kt_test_pass "none"
else
    kt_test_fail "left: $REPLY"
fi

# no process of ANY 045 run may be left: a row whose nonce names a live 045
# shell other than this one is that run's fixture at work (a concurrent run);
# --all: a fixture of a dead run is a leak whatever its ORPHAN flag
kt_test_start "strays.sh list --all --match kt045 shows nothing of a finished 045 run"
OUTK="$(bash "$ST" list --all --match kt045 2>&1)"
bad=""
while IFS= read -r l; do
    [[ "$l" =~ kt045x([0-9]+)x ]] || continue
    o="${BASH_REMATCH[1]}"
    [[ "$o" != "$$" ]] && kill -0 "$o" 2>/dev/null && continue
    bad+="${l}"$'\n'
done <<< "$OUTK"
if [[ -z "$bad" ]]; then
    kt_test_pass "${OUTK//$'\n'/ | }"
else
    kt_test_fail "left: ${bad//$'\n'/ | }"
fi

kt_test_log "045_StrayGuard.sh completed"
