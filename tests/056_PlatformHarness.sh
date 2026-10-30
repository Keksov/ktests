#!/usr/bin/env bash
# PlatformHarness (launch L2.1, PORTING.md H1-H8). The ktests harness on
# Windows (cygwin), Linux and FreeBSD alike:
#   H1/H2 the process table (ktest_proc.sh): the backend this platform must
#         have, this shell and a child in it (ppid, pgid, session, command
#         line, a start time that is never earlier than the real start and
#         never in the future — Linux counts clock ticks, not ms), a comm with
#         ") (" in it (Linux); the ps backend forced on Linux agrees with /proc
#   H1    a DELIBERATE stray — an orphan with a marker — is listed by
#         strays.sh (ORPHAN=yes) and stopped, also from under a `timeout`
#         (FreeBSD's is the reaper of all below it, in the caller's session);
#         with no process table at all strays.sh says UNKNOWN (rc 3), never
#         "none"
#   H7    the group stop's KILL deadline under a decimal-comma locale (bash
#         prints EPOCHREALTIME with the locale's decimal point: the old
#         `${EPOCHREALTIME/./}` left the comma in, `$(( ))` read it as the
#         comma operator and the deadline was never reached)
#   H6    the runner's output filter drops a trailing CR, not a trailing r
#   H5    gate.sh rewrites a cell result without `sed -i`
#   H4    every segment start mode of gate.sh (GNU env, perl, `set -m`) keeps
#         INT/QUIT trappable in a cell and gives the segment a session of
#         its own where it can; started from a caller that ignores SIGPIPE
#         (a CI runner), PIPE is trappable in a cell too (L5.4-10)
# Every process made on purpose carries the nonce $N and is owner-tied (it
# ends by itself once this file's shell is gone); the EXIT trap KILLs what
# carries the nonce.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "PlatformHarness" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
ST="$LIB/tools/strays.sh"
G="$LIB/tools/gate.sh"
MK="$LIB/tests/gate_fixtures/mkroot.sh"
unset KT_GATE_BASHES KT_GATE_SPAWN
N="kt056x$$x$RANDOM$RANDOM"

# owner-tied fixture loop (as 045): fork-free waits on a pty, else on a FIFO of
# this file (FreeBSD has no /dev/ptmx), never on a `sleep` child
export KT056_OWNER="$$"
export KT056_FIFO=""
if [[ ! -c /dev/ptmx ]]; then KT056_FIFO="$TMP/nap.fifo"; mkfifo "$KT056_FIFO" 2>/dev/null || KT056_FIFO=""; fi
export KT056_LOOP='{ [[ -c /dev/ptmx ]] && exec 3<>/dev/ptmx; } 2>/dev/null || { [[ -p "$KT056_FIFO" ]] && exec 3<>"$KT056_FIFO"; } 2>/dev/null || exec 3</dev/null; while kill -0 "$KT056_OWNER" 2>/dev/null; do read -t 0.3 -u 3 _ || (( $? > 128 )) || sleep 1; done'

kt056_cleanup() {
    local r
    for r in 1 2; do
        kt_proc_pids "$N"
        [[ -n "$REPLY" ]] && kill -KILL $REPLY 2>/dev/null
    done
    return 0
}
eval "$(trap -p EXIT | sed "s/^trap -- '/trap -- 'trap \"\" TERM INT HUP; kt056_cleanup; /")"
[[ "$(trap -p EXIT)" == *kt056_cleanup* ]] || trap 'trap "" TERM INT HUP; kt056_cleanup' EXIT
trap 'trap "" TERM INT HUP; exit 143' TERM
trap 'trap "" TERM INT HUP; exit 130' INT
trap 'trap "" TERM INT HUP; exit 129' HUP

# kt056_wait0 NAME — REPLY = the first pid whose argv[0] is NAME (<= 10 s)
kt056_wait0() {
    local i
    for (( i = 0; i < 100; i++ )); do
        kt_proc_pid0 "$1"; REPLY="${REPLY%% *}"
        [[ -n "$REPLY" ]] && return 0
        sleep 0.1
    done
    return 1
}
# kt056_orphan NAME — REPLY = the pid of a marker-free fixture NAME whose parent
# exited at once, once it is adopted (kt_proc_adopted)
kt056_orphan() {
    local i p
    bash -c '(exec -a "$1" bash -c "$KT056_LOOP") </dev/null >/dev/null 2>&1 & exit' _ "$1"
    for (( i = 0; i < 100; i++ )); do
        kt_proc_pid0 "$1"; p="${REPLY%% *}"
        [[ -n "$p" ]] && kt_proc_adopted "$p" && { REPLY="$p"; return 0; }
        sleep 0.1
    done
    REPLY=""
    return 1
}
# kt056_alive PID — signallable and no zombie (an orphan KILLed is a zombie until
# init reaps it: seconds on a stalled VM)
kt056_alive() { kill -0 "$1" 2>/dev/null || return 1; kt_proc_state "$1"; [[ -n "$REPLY" && "$REPLY" != Z ]]; }
# kt056_row OUT PID — REPLY = the ORPHAN column of PID's row in a strays.sh listing
kt056_row() {
    local l
    local -a f
    REPLY=""
    while IFS= read -r l; do
        read -r -a f <<< "$l"
        [[ "${f[0]:-}" == "$2" ]] && { REPLY="${f[3]}"; return 0; }
    done <<< "$1"
    return 1
}

# ---- H1/H2: the process table --------------------------------------------------
kt_test_start "the process table: the backend of this platform (cygwin with cygpath, linux on Linux, else ps) [H1]"
kt_proc_init; be="$KT_PROC_BACKEND"
want=ps
if command -v cygpath >/dev/null 2>&1; then want=cygwin; elif [[ "$OSTYPE" == linux* ]]; then want=linux; fi
if [[ "$be" == "$want" ]]; then
    kt_test_pass "$be: session column $KT_PROC_HAS_SID, state $KT_PROC_HAS_STATE, start times to ${KT_PROC_START_RES_MS} ms ($OSTYPE)"
else
    kt_test_fail "backend [$be] want [$want] (${KT_PROC_WHY:-no reason}) $OSTYPE"
fi

kt_test_start "this shell and a child in the table: ppid, process group, session, command line; a start time never earlier than the real start by more than KT_PROC_START_EARLY_MS, never in the future [H1, H2]"
source "$ST"
T1="$EPOCHREALTIME"
bash -c 'exec -a "kt056-$1-child" bash -c "$KT056_LOOP"' _ "$N" </dev/null >/dev/null 2>&1 &
CP=$!
kt056_wait0 "kt056-$N-child"
kt_proc_snapshot --cmd
_kt_strays_init; _kt_strays_table; _kt_strays_stat "$CP"
kt_proc_ms "$T1"; t1=$REPLY
kt_proc_ms "$EPOCHREALTIME"; now=$REPLY
kt_proc_ppid "$CP"; pp="$REPLY"; kt_proc_sid "$$"; sd="$REPLY"
bad=""
[[ "${KT_PROC_PP[$CP]:-}" == "$$" && "$pp" == "$$" ]] || bad+="[ppid ${KT_PROC_PP[$CP]:-}/$pp, want $$] "
[[ -n "${KT_PROC_PG[$CP]:-}" && "${KT_PROC_PG[$CP]}" == "${KT_PROC_PG[$$]:-}" ]] || bad+="[pgid ${KT_PROC_PG[$CP]:-} vs mine ${KT_PROC_PG[$$]:-}] "
[[ -n "$sd" && "${KT_PROC_SID[$CP]:-}" == "$sd" && "${KT_PROC_SID[$$]:-}" == "$sd" ]] || bad+="[session ${KT_PROC_SID[$CP]:-}/${KT_PROC_SID[$$]:-}, want $sd] "
[[ "${KT_PROC_CMD[$CP]:-}" == "kt056-$N-child -c "* ]] || bad+="[cmd '${KT_PROC_CMD[$CP]:0:60}'] "
st="${_KTS_ST[$CP]:-0}"
(( st >= t1 - KT_PROC_START_EARLY_MS && st <= now + 20 )) || bad+="[start $st not in [$t1-$KT_PROC_START_EARLY_MS, $now+20] (age $(( (now - st) / 1000 )) s)] "
if [[ -z "$bad" ]]; then
    kt_test_pass "child $CP: ppid $$, pgid ${KT_PROC_PG[$CP]}, session $sd, started $(( st - t1 )) ms after T1 (resolution ${KT_PROC_START_RES_MS} ms, early ${KT_PROC_START_EARLY_MS} ms)"
else
    kt_test_fail "$bad"
fi
{ kill -KILL "$CP"; wait "$CP"; } 2>/dev/null

kt_test_start "Linux /proc/PID/stat: a comm with ') (' and spaces in it is parsed from the LAST ') ' [H1]"
if [[ "$be" == linux ]]; then
    cp "$BASH" "$TMP/k) (x y" 2>/dev/null
    "$TMP/k) (x y" -c "$KT056_LOOP" </dev/null >/dev/null 2>&1 &
    WP=$!
    for (( i = 0; i < 50; i++ )); do kt_proc_snapshot; [[ "${KT_PROC_PP[$WP]:-}" == "$$" ]] && break; sleep 0.1; done
    l=""; { IFS= read -r l < "/proc/$WP/stat"; } 2>/dev/null
    if [[ "$l" == *"(k) (x y) "* && "${KT_PROC_PP[$WP]:-}" == "$$" && "${KT_PROC_STATE[$WP]:-}" == [RSD] && "${KT_PROC_SID[$WP]:-}" == "${KT_PROC_SID[$$]}" ]]; then
        kt_test_pass "${l:0:40}... -> ppid ${KT_PROC_PP[$WP]}, state ${KT_PROC_STATE[$WP]}"
    else
        kt_test_fail "stat [${l:0:80}] ppid [${KT_PROC_PP[$WP]:-}] state [${KT_PROC_STATE[$WP]:-}]"
    fi
    { kill -KILL "$WP"; wait "$WP"; } 2>/dev/null
else
    kt_test_pass "skipped: backend $be (no /proc/PID/stat)"
fi

kt_test_start "the ps backend forced on Linux (KT_PROC_BACKEND=ps) agrees with /proc: ppid, process group, session, start second [H1]"
if [[ "$be" == linux ]] && ps -o sid= -p $$ >/dev/null 2>&1; then
    o="$(KT_PROC_BACKEND=ps bash -c '
        source "$1"
        kt_proc_init || { echo "init failed: $KT_PROC_WHY"; exit 1; }
        kt_proc_snapshot
        a=( ${KT_PROC_PP[$$]} ${KT_PROC_PG[$$]} ${KT_PROC_SID[$$]} ${KT_PROC_ST[$$]} $KT_PROC_NOW_MS )
        l=""; IFS= read -r l < /proc/$$/stat; b=( ${l##*) } )
        printf "%s %s\n" "$KT_PROC_BACKEND" "${a[*]} | ${b[1]} ${b[2]} ${b[3]}"' _ "$LIB/ktest_proc.sh" 2>&1)"
    read -r obe opp opg osd ost onow _ p1 p2 p3 <<< "$o"
    if [[ "$obe" == ps && "$opp" == "$p1" && "$opg" == "$p2" && "$osd" == "$p3" && "$ost" -le "$onow" ]]; then
        kt_test_pass "$o"
    else
        kt_test_fail "[$o]"
    fi
else
    kt_test_pass "skipped: backend $be$( [[ "$be" == linux ]] && printf ' (ps has no sid)')"
fi

# ---- H1: a deliberate stray ------------------------------------------------------
kt_test_start "a DELIBERATE stray (an orphan with a marker) is listed by strays.sh — ORPHAN=yes, its command line — then stopped, and none is left [H1]"
kt056_orphan "kt_iso-$N-stray"; SP="$REPLY"
L1="$(bash "$ST" list --session self --match "$N" 2>&1)"
L2="$(bash "$ST" stop --session self --match "$N" 2>&1)"; rc2=$?
for (( i = 0; i < 30; i++ )); do kt056_alive "$SP" || break; sleep 0.1; done
L3="$(bash "$ST" list --all --match "$N" 2>&1)"
f1=""; [[ -n "$SP" ]] && kt056_row "$L1" "$SP" && f1="$REPLY"
if [[ -n "$SP" && "$f1" == yes && "$L1" == *"kt_iso-$N-stray"* && "$L1" == *"strays: 1 process(es)"* \
      && "$rc2" == 0 && "$L2" == *"stopped, none left"* && "$L3" == "strays: none"* ]] && ! kt056_alive "$SP"; then
    kt_test_pass "listed on $be: ${L1//$'\n'/ | } || stop: ${L2##*$'\n'} || after: $L3"
else
    kt_test_fail "pid=[$SP] flag=[$f1] rc=$rc2 | list: ${L1//$'\n'/ | } | stop: ${L2//$'\n'/ | } | after: $L3"
fi
kt056_cleanup

kt_test_start "a stray made under a \`timeout\` is seen by a check under it too (FreeBSD's timeout is the REAPER of all below it, in the caller's own session) and stopped [H1/H3]"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
T2="$EPOCHREALTIME"
o="$("$KT_TIMEOUT" -k 5 60 bash -c '
    bash -c "(exec -a \"\$0\" bash -c \"\$KT056_LOOP\") </dev/null >/dev/null 2>&1 & exit" "kt_iso-$1-reaped"
    sleep 0.5
    p="$(bash -c "source \"\$1\"; kt_proc_pid0 \"\$2\"; printf %s \"\${REPLY%% *}\"" _ "$4" "kt_iso-$1-reaped")"
    pp="$(bash -c "source \"\$1\"; kt_proc_ppid \"\$2\"; printf %s \"\$REPLY\"" _ "$4" "$p")"
    echo "pid=$p ppid=$pp"
    bash "$2" stop --session self --since "$3" --match "$1-reaped"
' _ "$N" "$ST" "$T2" "$LIB/ktest_proc.sh" 2>&1)"; rc=$?
rp="${o#pid=}"; rp="${rp%% *}"
f1=""; [[ -n "$rp" ]] && kt056_row "$o" "$rp" && f1="$REPLY"
if [[ "$rc" == 0 && -n "$rp" && "$f1" == yes && "$o" == *"stopped, none left"* ]] && ! kt056_alive "$rp"; then
    kt_test_pass "${o//$'\n'/ | }"
else
    kt_test_fail "rc=$rc (124 = timeout waited for it) pid=[$rp] flag=[$f1] | ${o//$'\n'/ | }"
fi
fi   # kt_need_timeout
kt056_cleanup

kt_test_start "no process table (KT_PROC_BACKEND=none): strays.sh says UNKNOWN with the reason and exits 3 — never a blind 'none'; the library and the suite-job stray check report n/a [H1]"
o1="$(KT_PROC_BACKEND=none bash "$ST" list --all 2>&1)"; r1=$?
o2="$(KT_PROC_BACKEND=none bash "$ST" stop 2>&1)"; r2=$?
o3="$(KT_PROC_BACKEND=none bash -c 'source "$1"; kt_suitejob_init "$EPOCHREALTIME"; kt_strays_scan --session self; echo "scan=$RESULT [$KT_STRAYS_UNKNOWN]"; kt_suitejob_strays "a job"; echo "rc=$?"' _ "$LIB/tools/suitejob.sh" 2>&1)"
if [[ "$r1" == 3 && "$o1" == "strays: UNKNOWN (no process table: forced (KT_PROC_BACKEND=none); bash "* && "$r2" == 3 && "$o2" == "strays: UNKNOWN"* \
      && "$o3" == *"scan=0 [no process table: forced"* && "$o3" == *"[WARN] stray check after a job: n/a (no process table"* && "$o3" == *"rc=0" ]]; then
    kt_test_pass "$o1 | ${o3//$'\n'/ | }"
else
    kt_test_fail "rc $r1/$r2 | $o1 | $o2 | ${o3//$'\n'/ | }"
fi

kt_test_start "the first process-table call of a fresh shell for a GONE pid: kt_runner_proc_start / kt_proc_cwd / kt_proc_ppid return \"\" (the Linux init must not leak its uptime into REPLY) [L2.1 review]"
gp="$(bash -c 'echo $$')"
o="$(bash -c 'source "$1/ktest.sh"; kt_runner_proc_start "$2"; a="$REPLY"; printf "start=[%s] " "$a"' _ "$LIB" "$gp" 2>&1)"
o+="$(bash -c 'source "$1/ktest_proc.sh"; kt_proc_cwd "$2"; printf "cwd=[%s] " "$REPLY"' _ "$LIB" "$gp" 2>&1)"
o+="$(bash -c 'source "$1/ktest_proc.sh"; REPLY=keep; kt_proc_init; printf "init-keeps=[%s] " "$REPLY"; kt_proc_ppid "$2"; printf "ppid=[%s]" "$REPLY"' _ "$LIB" "$gp" 2>&1)"
if [[ "$o" == "start=[] cwd=[] init-keeps=[keep] ppid=[]" ]]; then
    kt_test_pass "gone pid $gp: $o"
else
    kt_test_fail "gone pid $gp: $o"
fi

# a detached process like busybox's timeout WATCHER: argv `timeout …`, its
# parent gone, it lives LIFE seconds (fork-free wait) unless it is ended
printf '%s\n' '{ [[ -c /dev/ptmx ]] && exec 3<>/dev/ptmx; } 2>/dev/null || { [[ -p "$KT056_FIFO" ]] && exec 3<>"$KT056_FIFO"; } 2>/dev/null || exec 3</dev/null' \
    'read -t "$1" -u 3 _ || (( $? > 128 )) || sleep "$1"' > "$TMP/wloop.sh"
printf '%s\n' '(exec -a timeout bash "$1" "$2" "$3") </dev/null >/dev/null 2>&1 & exit' > "$TMP/watcher.sh"
# the same watcher named `gtimeout` (macOS brew coreutils' name; launch L5.4-9):
# the watcher rule matches it as it matches `timeout`
printf '%s\n' '(exec -a gtimeout bash "$1" "$2" "$3") </dev/null >/dev/null 2>&1 & exit' > "$TMP/watcher_g.sh"
kt_test_start "the strict stray check where timeout is busybox's: a lingering timeout WATCHER (gone within 3 s) is no STRAY, one that stays is; elsewhere it is a stray at once; a watcher named gtimeout is matched the same way [L2.1 review, L5.4-9]"
# no clock races the check (L2.8-b): every watcher lives 120 s; the one that
# is "gone in time" is ended at the first busybox look-again nap (0.5 s) by
# the wrapper below — a fixed LIFE (1.6 s, 6 s) lost to the check's own scans
# under the threaded suite (~0.25 s each, 8 of them). And the --match scan
# needs the command line after the exec: cygwin shows a process mid-exec as
# the bare program path (no nonce), missed in 2-7 % of scans — wait for it.
o="$(bash -c '
    source "$1/tools/suitejob.sh"
    ws="$2" wl="$3" nn="$4" wg="$5" kw=""
    f="$(declare -f _kt_strays_nap)"; eval "_kt056_nap ${f#_kt_strays_nap }"
    _kt_strays_nap() {
        if [[ "$1" == 0.5 && -n "$kw" ]]; then
            kill -KILL "$kw" 2>/dev/null
            for (( k = 0; k < 100; k++ )); do _kt_suitejob_alive "$kw" || break; _kt056_nap 0.1; done
            kw=""
        fi
        _kt056_nap "$1"
    }
    for c in "1 ends" "1 stays" "0 ends" "1 ends g"; do
        set -- $c; _KTP_BBTMO=$1
        w="$ws"; [[ "${3:-}" == g ]] && w="$wg"
        kt_suitejob_init "$EPOCHREALTIME" "$nn"
        bash "$w" "$wl" 120 "kt056-$nn-watcher"
        for (( i = 0; i < 50; i++ )); do kt_proc_pids "timeout $wl 120 kt056-$nn-watcher"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
        kw=""; [[ "$2" == ends ]] && kw="${REPLY%% *}"
        kt_suitejob_strays "w$1/$2" >/dev/null 2>&1; printf "bb=%s %s%s rc=%s; " "$1" "$2" "${3:+ $3}" "$?"
        [[ -n "$kw" ]] && kill -KILL "$kw" 2>/dev/null; kw=""
    done' _ "$LIB" "$TMP/watcher.sh" "$TMP/wloop.sh" "$N" "$TMP/watcher_g.sh" 2>&1)"
if [[ "$o" == "bb=1 ends rc=0; bb=1 stays rc=1; bb=0 ends rc=1; bb=1 ends g rc=0; " ]]; then
    kt_test_pass "$o"
else
    kt_test_fail "[$o] (want: busybox + gone in time -> 0; busybox + stays -> 1; not busybox -> 1; busybox + a gtimeout watcher gone in time -> 0)"
fi
kt056_cleanup

# ---- H7: the group stop's deadline under a decimal-comma locale ---------------------
kt_test_start "kt_runner_group_stop under a decimal-comma locale (LC_ALL=ru_RU.UTF-8): a TERM-ignoring member is KILLed by the deadline, the stop returns [H7, L0.7]"
ep="$(LC_ALL=ru_RU.UTF-8 bash -c 'printf %s "$EPOCHREALTIME"' 2>/dev/null)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
elif [[ "$ep" != *,* ]]; then
    kt_test_pass "skipped: no decimal-comma locale here (EPOCHREALTIME under ru_RU.UTF-8: '$ep'; musl has none)"
else
    # ktest.sh pins LC_ALL=C.UTF-8 (the locale contract): the comma locale is
    # set after it — the runner as a library under another locale
    o="$("$KT_TIMEOUT" -k 5 40 bash -c '
        source "$1/ktest.sh"
        export LC_ALL=ru_RU.UTF-8
        set -m
        ( trap "" TERM; exec -a "kt056-$2-ignorer" bash -c "trap \"\" TERM; $KT056_LOOP" ) </dev/null >/dev/null 2>&1 &
        g=$!
        set +m
        for (( i = 0; i < 100; i++ )); do kt_runner_group_members "$g"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
        t0="$EPOCHREALTIME"
        kt_runner_group_stop "$g" 10
        t1="$EPOCHREALTIME"
        alive=no; kill -0 -- "-$g" 2>/dev/null && alive=yes
        kill -KILL -- "-$g" 2>/dev/null
        printf "t0=%s t1=%s alive=%s stats=[%s]\n" "$t0" "$t1" "$alive" "$KT_GROUP_END_STATS"
    ' _ "$LIB" "$N" 2>&1)"; rc=$?
    t0="" t1="" re='t0=([0-9.,]+) t1=([0-9.,]+)'
    [[ "$o" =~ $re ]] && { t0="${BASH_REMATCH[1]}"; t1="${BASH_REMATCH[2]}"; }
    kt_proc_ms "$t0"; m0=$REPLY; kt_proc_ms "$t1"; m1=$REPLY
    if [[ "$rc" == 0 && "$t0" == *,* && "$o" == *" alive=no "* && "$o" =~ kill_rounds=[1-9] ]] && (( m1 - m0 >= 900 && m1 - m0 <= 8000 )); then
        kt_test_pass "stopped in $(( m1 - m0 )) ms (grace 1 s): ${o//$'\n'/ | }"
    else
        kt_test_fail "rc=$rc (124: the stop never reached its KILL deadline) $(( m1 - m0 )) ms | ${o//$'\n'/ | }"
    fi
fi
kt056_cleanup

# ---- H6, H5 --------------------------------------------------------------------
kt_test_start "the runner's output filter drops a trailing CR (CRLF output) and keeps a trailing letter r [H6]"
o="$(VERBOSITY=error kt_runner_filter_output $'[WARN] a crlf line\r\n[WARN] a word ending in r\n__COUNTS__:1:1:0' "" 0)"
if [[ "$o" == $'[WARN] a crlf line\n[WARN] a word ending in r' ]]; then
    kt_test_pass "${o//$'\n'/ | }"
else
    kt_test_fail "[$(printf '%q' "$o")]"
fi

kt_test_start "gate.sh rewrites a cell result's verdict/reason in place (order kept, no sed -i) [H5]"
o="$( source "$G" || exit 9
      printf '%s\n' idx=1 verdict=PASS rc=0 'reason=' 'x=a|b' > "$TMP/kv"
      _kt_gate_setkv "$TMP/kv" "verdict=STRAY" 'reason=r|&\ 1'
      cat "$TMP/kv" )"
if [[ "$o" == $'idx=1\nverdict=STRAY\nrc=0\nreason=r|&\\ 1\nx=a|b' ]]; then
    kt_test_pass "${o//$'\n'/ | }"
else
    kt_test_fail "[${o//$'\n'/ | }]"
fi

# ---- H4: the segment start modes ---------------------------------------------------
RS="$TMP/rootS"; bash "$MK" "$RS" sigs
for m in env perl jobctl; do
    kt_test_start "gate.sh segment start mode '$m' (KT_GATE_SPAWN): INT and QUIT trappable in the cell; a session of its own where the platform can [H4]"
    if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"; continue; fi
    case "$m" in
        env) have=""; for e in env genv; do command -v "$e" >/dev/null 2>&1 && "$e" --default-signal=INT -i "PATH=$PATH" true </dev/null >/dev/null 2>&1 && have=1; done ;;
        perl) have=""; command -v perl >/dev/null 2>&1 && perl -MPOSIX -e 1 </dev/null >/dev/null 2>&1 && have=1 ;;
        jobctl) have=1 ;;
    esac
    if [[ -z "$have" ]]; then
        kt_test_pass "skipped: no $([[ $m == env ]] && echo 'GNU env (--default-signal)' || echo 'perl with POSIX') here"
        continue
    fi
    # a session of its own: env with setsid(1) or perl; perl; jobctl with setsid(1)
    sess=no
    case "$m" in
        env) { command -v setsid || command -v perl; } >/dev/null 2>&1 && sess=yes ;;
        perl) sess=yes ;;
        jobctl) command -v setsid >/dev/null 2>&1 && sess=yes ;;
    esac
    # no session of its own: the segment's stray check (strict, since its
    # start) would see the CALLER's session — here the whole threaded ktests
    # run — and stop other files' fixtures; the launcher gets a session of its
    # own first (perl), or the case is skipped
    iso=()
    if [[ "$sess" == no ]]; then
        if command -v perl >/dev/null 2>&1 && perl -MPOSIX -e 1 </dev/null >/dev/null 2>&1; then
            iso=( perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 127' )
        else
            kt_test_pass "skipped: mode $m has no session of its own here and no perl isolates the launcher"
            continue
        fi
    fi
    o="$(KT_GATE_SPAWN="$m" "$KT_TIMEOUT" -k 10 150 "${iso[@]}" bash "$G" --root "$RS" --out "$TMP/outS.$m" --bash "$BASH" all 2>&1 < /dev/null)"; rc=$?
    sp="" ssid=""; { read -r sp _ ssid _ < "$TMP/outS.$m/seg-1.pid"; } 2>/dev/null
    bad=""
    # the cell's own counts: both INT and QUIT traps set
    ct="" cp="" cv=""
    while IFS='=' read -r k v; do
        case "$k" in total) ct="$v" ;; passed) cp="$v" ;; verdict) cv="$v" ;; esac
    done < "$TMP/outS.$m/cells/001/result" 2>/dev/null
    [[ "$ct/$cp" == 2/2 ]] || bad+="[cell $cv $cp/$ct, want 2/2] "
    [[ "$rc" == 0 && "$o" == *$'\n'"__GATE__:PASS:1:1:0:0:0:0:0:2:2" ]] || bad+="[rc=$rc, not PASS 2/2] "
    [[ "$o" == *$'\n'"gate: segment start = $m (forced by KT_GATE_SPAWN=$m)"$'\n'* ]] || bad+="[no 'segment start = $m' header] "
    if [[ "$sess" == yes ]]; then
        [[ -n "$sp" && "$ssid" == "$sp" ]] || bad+="[segment $sp: session '$ssid', want its own] "
        [[ "$o" != *"[WARN] no setsid/perl"* ]] || bad+="[a no-setsid WARN] "
    else
        [[ "$o" == *"[WARN] no setsid/perl"* ]] || bad+="[no 'no setsid/perl' WARN] "
    fi
    if [[ -z "$bad" ]]; then
        kt_test_pass "segment $sp session $ssid (own: $sess): ${o##*$'\n'}"
    else
        kt_test_fail "$bad | ${o//$'\n'/ | }"
    fi
done

kt_test_start "gate.sh unforced: the header names the platform's start mode (env where a GNU env works, else perl, else jobctl); on cygwin a GNU env that fails its probe is an ERROR (rc 2), never a silent switch [H4]"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
want=jobctl
for e in env genv; do command -v "$e" >/dev/null 2>&1 && "$e" --default-signal=INT -i "PATH=$PATH" true </dev/null >/dev/null 2>&1 && { want=env; break; }; done
[[ "$want" == jobctl ]] && command -v perl >/dev/null 2>&1 && perl -MPOSIX -e 1 </dev/null >/dev/null 2>&1 && want=perl
o="$("$KT_TIMEOUT" -k 10 150 bash "$G" --root "$RS" --out "$TMP/outS.default" --bash "$BASH" all 2>&1 < /dev/null)"; rc=$?
# a fake `env` first on PATH that rejects --default-signal (and passes every
# other call on to the real one)
renv="$(type -P env)"; mkdir -p "$TMP/fakeenv"
printf '%s\n' '#!/bin/sh' 'case "$1" in --default-signal*) exit 125 ;; esac' "exec '$renv' \"\$@\"" > "$TMP/fakeenv/env"
chmod +x "$TMP/fakeenv/env"
o2="$(PATH="$TMP/fakeenv:$PATH" "$KT_TIMEOUT" -k 10 150 bash "$G" --root "$RS" --out "$TMP/outS.fake" --bash "$BASH" all 2>&1 < /dev/null)"; rc2=$?
bad=""
[[ "$rc" == 0 && "$o" == *$'\n'"gate: segment start = $want"$'\n'* ]] || bad+="[unforced: rc=$rc, want 'segment start = $want'] "
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    [[ "$rc2" == 2 && "$o2" == *"env --default-signal=INT,QUIT does not work in this cygwin runtime"* && ! -e "$TMP/outS.fake/.kt_gate" ]] || bad+="[cygwin, failing env: rc=$rc2, want the error] "
else
    # off cygwin the fake hides `env` only; genv (FreeBSD coreutils) may still win
    [[ "$rc2" == 0 && "$o2" == *$'\n'"gate: segment start = "* ]] || bad+="[failing env: rc=$rc2] "
fi
if [[ -z "$bad" ]]; then
    kt_test_pass "unforced: $(grep -a '^gate: segment start' <<< "$o") | failing env: $(grep -a 'segment start\|does not work' <<< "$o2" | head -1)"
else
    kt_test_fail "$bad | ${o//$'\n'/ | } || ${o2//$'\n'/ | }"
fi
fi   # kt_need_timeout

# ---- L5.4-10 (OG12 a): the gate's caller ignores SIGPIPE (a CI runner) ------------
# a signal ignored when a non-interactive bash starts can never be trapped by it
# or its children: the gate resets PIPE for its cells as it does INT/QUIT
kt_test_start "gate.sh started from a parent with SIGPIPE ignored: a cell's trap on PIPE (and INT, QUIT) takes; where neither a GNU env nor perl can reset it, a [WARN] names SIGPIPE [L5.4-10]"
want=jobctl
for e in env genv; do command -v "$e" >/dev/null 2>&1 && "$e" --default-signal=INT,QUIT,PIPE -i "PATH=$PATH" true </dev/null >/dev/null 2>&1 && { want=env; break; }; done
[[ "$want" == jobctl ]] && command -v perl >/dev/null 2>&1 && perl -MPOSIX -e 1 </dev/null >/dev/null 2>&1 && want=perl
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
elif [[ "$want" == jobctl ]] && ! command -v setsid >/dev/null 2>&1; then
    kt_test_pass "skipped: start mode jobctl without setsid (no session of its own, see H4)"
else
    RP="$TMP/rootP"; bash "$MK" "$RP" sigs
    printf '%s\n' 'source "$KTEST_SOURCE_PATH"' 'kt_test_init "GfxPipe" "$KT_TESTS_DIR" "$@"' \
        'kt_test_start "PIPE is trappable in a cell"' "trap ': x' PIPE" 't="$(trap -p PIPE)"' \
        'if [[ "$t" == *": x"* ]]; then kt_test_pass "$t"; else kt_test_fail "trap -p PIPE = [$t] (ignored on entry?)"; fi' \
        'trap - PIPE' > "$RP/sigs/tests/002_pipe.sh"
    o="$("$KT_TIMEOUT" -k 10 150 bash -c 'trap "" PIPE; exec bash "$@"' _ "$G" --root "$RP" --out "$TMP/outP" --bash "$BASH" all 2>&1 < /dev/null)"; rc=$?
    bad=""
    if [[ "$want" == jobctl ]]; then
        [[ "$o" == *"[WARN] "*SIGPIPE*" ignored when the gate started"* ]] || bad+="[jobctl: no [WARN] naming SIGPIPE] "
    else
        [[ "$rc" == 0 && "$o" == *$'\n'"__GATE__:PASS:1:1:0:0:0:0:0:3:3" ]] || bad+="[rc=$rc, not PASS 3/3] "
        [[ "$o" != *"[WARN] "*SIGPIPE* ]] || bad+="[a SIGPIPE WARN in mode $want] "
    fi
    if [[ -z "$bad" ]]; then
        kt_test_pass "mode $want: $(grep -a '^gate: segment start\|SIGPIPE' <<< "$o" | head -2 | tr '\n' ' ')${o##*$'\n'}"
    else
        kt_test_fail "$bad | ${o//$'\n'/ | } || fails: $(cat "$TMP/outP/cells/001/fails.txt" 2>/dev/null)"
    fi
fi

kt056_cleanup
kt_test_start "nothing that carries this file's nonce is left"
kt_proc_pids_gone "$N"   # (a busybox timeout watcher lingers ~1 s)
if [[ -z "$REPLY" ]]; then kt_test_pass "none"; else kt_test_fail "left: $REPLY"; fi

kt_test_log "056_PlatformHarness.sh completed"
