#!/usr/bin/env bash
# suitejob.sh — run test suites as jobs of their own: the suite-job machinery
# of the master sweep (tests/tests.sh), moved here in gate G1 (DG5) so that the
# master and ktests/tools/gate.sh share one implementation. A library: source
# it, nothing runs on source. Plain bash, no kbool/kkore/kklass; it sources
# ./strays.sh (beside it) unless that is loaded already.
#
#   kt_suitejob_init SINCE [MATCH]   start a sweep: the stray window starts at
#                       SINCE (an EPOCHREALTIME taken by the caller — the
#                       master takes it before it loads anything); MATCH
#                       (optional; the master passes KT_STRAYS_MATCH) narrows
#                       every stray scan to processes whose command line
#                       contains it (a test running a nested sweep uses a
#                       nonce). Resets the per-sweep records below.
#   kt_suitejob_discover ROOT        KT_SUITEJOB_SUITES = every DIR/tests/tests.sh
#                       under ROOT except ROOT's own tests/tests.sh, in the
#                       master's walk order (depth first; at each level DIR's
#                       own tests/tests.sh first, then its non-hidden
#                       subdirectories in glob order); RESULT = the count.
#   kt_suitejob_run LABEL CMD...     run CMD as a BACKGROUND job under `set -m`
#                       (a process group of its own, default SIGINT, the
#                       caller's stdin; TTOU/TTIN ignored in the job) and
#                       `wait` for it. Records LABEL and its start time (for
#                       the stray report). rc 0: the job ended, its status in
#                       KT_SUITEJOB_RC. rc 1: the wait was BROKEN by the
#                       caller's trap (kt_suitejob_break) — the job still
#                       runs, KT_SUITEJOB_PID still names it, KT_SUITEJOB_RC is
#                       the wait's 128+N (0: the break came before the wait);
#                       call kt_suitejob_signal.
#   kt_suitejob_break                call it from a trap (e.g. USR1, G2's
#                       segment watchdog): the running kt_suitejob_run stops
#                       waiting and returns 1 (also when the signal came
#                       between the fork and the `wait`; only the instant
#                       between that check and `wait` itself can miss it — a
#                       watchdog repeats its signal while the job runs). A
#                       trap may instead run the stop path itself and exit
#                       (the master's TERM/INT/HUP).
#   kt_suitejob_tstp                 the TSTP trap body (`trap kt_suitejob_tstp
#                       TSTP`): Ctrl-Z suspends the job's group with the
#                       caller (kt_runner_group_suspend when ktest_runner.sh is
#                       loaded, else the same steps here), resumes it on CONT;
#                       kt_suitejob_run then waits again.
#   kt_suitejob_signal [RC]          stop the running job (no-op without one):
#                       TERM + CONT to its group (the master's suites `exec`
#                       ktests.sh, whose TERM trap stops its own run group), a
#                       fork-free grace of KT_SUITEJOB_GRACE tenths of a second
#                       (default 150 = 15 s; ktests.sh needs <= ~6 s) while
#                       the job's leader lives, then KILL to the group (to a
#                       leader that lives on: again, up to KT_STRAYS_KILL_MS,
#                       then on cygwin the Windows-side kill (`kill -f -9`) —
#                       launch L2.7-G), reap — never `wait` for a leader still
#                       alive (named in a [WARN] line with its winpid, RC 137,
#                       KT_SUITEJOB_LEADER_LEFT="PID=WINPID"; every later
#                       kt_suitejob_strays reports it — see there).
#                       KT_SUITEJOB_RC = the reaped status, KT_SUITEJOB_PID="";
#                       RC (the caller's exit code) is kept in
#                       KT_SUITEJOB_SIGNAL_RC. Traps are the caller's: it
#                       ignores TERM/INT/HUP itself first when it must.
#   kt_suitejob_strays LABEL         the stray check (`--session self --since
#                       SINCE [--match MATCH]`, the strict orphan rule, marker
#                       or not): rc 0 none; else one look again 1 s later (a
#                       run's group watchdog may be just ending), then report
#                       ("[WARN] N stray process(es) found after LABEL:" and a
#                       row per process with the label running when it
#                       started), stop them (kt_strays_stop), record, rc 1;
#                       survivors: "[WARN] N could NOT be stopped (winpid
#                       PID=WINPID ...):" (the winpids on cygwin) + a table.
#                       A job leader kt_suitejob_signal could NOT stop (the
#                       scan never lists it: this shell's own child) is
#                       reported here too, while it lives — by the first
#                       check after the stop and by every final check
#                       (KT_SUITEJOB_CUR empty): "[WARN] job leader P of
#                       LABEL could NOT be stopped (winpid W)", a row
#                       "pid P (job leader) started during LABEL: …", rc 1.
#
# STATE (globals, read by the caller):
#   KT_SUITEJOB_SUITES   discover's result
#   KT_SUITEJOB_PID      the running job's pid = its process group id ("" none)
#   KT_SUITEJOB_RC       status of the last job (see kt_suitejob_run/_signal)
#   KT_SUITEJOB_CUR      LABEL of the job running or last run ("" before)
#   KT_SUITEJOB_SIGNAL_RC  RC given to kt_suitejob_signal ("" never called)
#   KT_SUITEJOB_NAMES / KT_SUITEJOB_T0   every LABEL run and its start (epoch ms)
#   KT_SUITEJOB_STRAY_ROWS    one line per stray found: "pid P (FLAG) started
#                        during LABEL: CMD"
#   KT_SUITEJOB_STRAY_LABELS  assoc: LABEL -> 1 for each label a stray was
#                        started during (KT_SUITEJOB_BEFORE for one started
#                        before the first job)
#   KT_SUITEJOB_STRAY_LEFT    how many strays the last kt_suitejob_strays
#                        could NOT stop (0: none, or all stopped; a job
#                        leader left alive counts)
#   KT_SUITEJOB_LEADER_LEFT   "PID=WINPID" of the job leader the last
#                        kt_suitejob_signal could NOT stop ("" none)
# SETTINGS: KT_SUITEJOB_GRACE (tenths of a second, default 150),
#   KT_SUITEJOB_BEFORE (the label of the time before the first job, default
#   "(before the first suite)"), KT_SUITEJOB_SINCE / KT_SUITEJOB_MATCH (set by
#   kt_suitejob_init).
#
# Users: tests/tests.sh (the master sweep) and, from G2, ktests/tools/gate.sh
# (the segment runs each cell with kt_suitejob_run; its exec'd watchdog sends
# USR1, whose trap calls kt_suitejob_break). Fork-light: builtins, the
# fork-free strays.sh scan and `read -t` naps; the job itself is the only fork.

if [[ -n "${_KT_SUITEJOB_SOURCED:-}" && "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi
_KT_SUITEJOB_SOURCED=1

if ! declare -F kt_strays_scan >/dev/null; then
    __kt_sj_src="${BASH_SOURCE[0]}"
    __kt_sj_dir="${__kt_sj_src%/*}"; [[ "$__kt_sj_dir" == "$__kt_sj_src" ]] && __kt_sj_dir=.
    source "$__kt_sj_dir/strays.sh"
    unset __kt_sj_src __kt_sj_dir
fi

declare -ga KT_SUITEJOB_SUITES=() KT_SUITEJOB_NAMES=() KT_SUITEJOB_T0=() KT_SUITEJOB_STRAY_ROWS=()
declare -gA KT_SUITEJOB_STRAY_LABELS=()
declare -g  KT_SUITEJOB_PID="" KT_SUITEJOB_RC=0 KT_SUITEJOB_CUR="" KT_SUITEJOB_SIGNAL_RC=""
declare -g  KT_SUITEJOB_STRAY_LEFT=0 KT_SUITEJOB_LEADER_LEFT=""
# job leaders kt_suitejob_signal could not stop: PID -> "WINPID|LABEL|REPORTED"
declare -gA _KT_SUITEJOB_LEFT=()
declare -g  KT_SUITEJOB_SINCE="${KT_SUITEJOB_SINCE:-$EPOCHREALTIME}" KT_SUITEJOB_MATCH="${KT_SUITEJOB_MATCH:-}"
declare -g  KT_SUITEJOB_GRACE="${KT_SUITEJOB_GRACE:-150}"
declare -g  KT_SUITEJOB_BEFORE="${KT_SUITEJOB_BEFORE:-(before the first suite)}"
declare -ga _KT_SUITEJOB_OPTS=( --session self )
declare -g  _KT_SUITEJOB_SUSP=0 _KT_SUITEJOB_BRK=0

kt_suitejob_init() {
    KT_SUITEJOB_SINCE="${1:-$EPOCHREALTIME}"
    KT_SUITEJOB_MATCH="${2:-}"
    _KT_SUITEJOB_OPTS=( --session self )
    [[ -n "$KT_SUITEJOB_MATCH" ]] && _KT_SUITEJOB_OPTS+=( --match "$KT_SUITEJOB_MATCH" )
    KT_SUITEJOB_NAMES=() KT_SUITEJOB_T0=() KT_SUITEJOB_STRAY_ROWS=()
    KT_SUITEJOB_STRAY_LABELS=()
    KT_SUITEJOB_PID="" KT_SUITEJOB_RC=0 KT_SUITEJOB_CUR="" KT_SUITEJOB_SIGNAL_RC=""
    return 0
}

# _kt_suitejob_walk DIR ROOT — the master's process_dir
_kt_suitejob_walk() {
    local base_dir="$1" entry
    if [[ -f "$base_dir/tests/tests.sh" && "$base_dir" != "$2" ]]; then
        KT_SUITEJOB_SUITES+=("$base_dir/tests/tests.sh")
    fi
    for entry in "$base_dir"/*; do
        if [[ -d "$entry" && ! "${entry##*/}" =~ ^\. ]]; then
            _kt_suitejob_walk "$entry" "$2"
        fi
    done
}
kt_suitejob_discover() {
    KT_SUITEJOB_SUITES=()
    _kt_suitejob_walk "$1" "$1"
    RESULT=${#KT_SUITEJOB_SUITES[@]}
    return 0
}

kt_suitejob_run() {
    local label="$1" m=0
    shift
    _kt_strays_ms "$EPOCHREALTIME"
    KT_SUITEJOB_NAMES+=( "$label" ); KT_SUITEJOB_T0+=( "$REPLY" )
    KT_SUITEJOB_CUR="$label" KT_SUITEJOB_LEADER_LEFT=""
    [[ $- == *m* ]] && m=1
    _KT_SUITEJOB_BRK=0
    set -m
    ( trap '' TTOU TTIN; exec "$@" ) &
    KT_SUITEJOB_PID=$!
    (( m )) || set +m
    while :; do
        _KT_SUITEJOB_SUSP=0
        # a break that arrived before the wait (right after the fork) counts
        (( _KT_SUITEJOB_BRK )) && { KT_SUITEJOB_RC=0; return 1; }
        wait "$KT_SUITEJOB_PID"; KT_SUITEJOB_RC=$?
        (( _KT_SUITEJOB_BRK )) && return 1
        (( _KT_SUITEJOB_SUSP )) || break
    done
    KT_SUITEJOB_PID=""
    return 0
}

kt_suitejob_break() {
    _KT_SUITEJOB_BRK=1
    return 0
}

kt_suitejob_tstp() {
    local p="$KT_SUITEJOB_PID" r
    _KT_SUITEJOB_SUSP=1
    if declare -F kt_runner_group_suspend >/dev/null; then
        kt_runner_group_suspend "$p"
        return 0
    fi
    # kt_runner_group_suspend's steps without the ktests runner: TSTP to the
    # group, stop this shell, on CONT continue the group — and by pid (a group
    # CONT can be lost for a member on the Git runtime under load)
    if [[ -n "$p" && "$p" != *[!0-9]* ]]; then
        kill -TSTP -- "-$p" 2>/dev/null || kill -TSTP "$p" 2>/dev/null
    fi
    kill -STOP "$BASHPID"
    if [[ -n "$p" && "$p" != *[!0-9]* ]]; then
        kill -CONT -- "-$p" 2>/dev/null || kill -CONT "$p" 2>/dev/null
        _kt_strays_nap_open
        for (( r = 0; r < 3; r++ )); do
            _kt_strays_members "$p"
            [[ -z "$REPLY" ]] && break
            kill -CONT $REPLY 2>/dev/null
            _kt_strays_nap 0.1
        done
        _kt_strays_nap_close
    fi
    return 0
}

# _kt_suitejob_alive PID — rc 0 while PID lives and is no zombie (a dead job
# not reaped yet is gone: `wait` reaps it at once)
_kt_suitejob_alive() {
    kill -0 "$1" 2>/dev/null || return 1
    kt_proc_state "$1"
    [[ "$REPLY" != Z ]]
}
kt_suitejob_signal() {
    local i kms p="$KT_SUITEJOB_PID"
    KT_SUITEJOB_SIGNAL_RC="${1:-}" KT_SUITEJOB_LEADER_LEFT=""
    [[ -n "$p" ]] || return 0
    kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null
    kill -CONT -- "-$p" 2>/dev/null || kill -CONT "$p" 2>/dev/null
    _kt_strays_nap_open
    for (( i = 0; i < KT_SUITEJOB_GRACE; i++ )); do
        kill -0 "$p" 2>/dev/null || break
        _kt_strays_nap 0.1
    done
    kill -KILL -- "-$p" 2>/dev/null || kill -KILL "$p" 2>/dev/null
    # a leader that ignores even KILL would hang the `wait` for ever (launch
    # L2.7-G: a process that acts on no cygwin signal): KILL again while it
    # lives, up to KT_STRAYS_KILL_MS (SIGKILL delivery lags under load), then
    # end it from the Windows side (kt_proc_winkill, cygwin only); `wait` only
    # for a leader that is gone
    kms="${KT_STRAYS_KILL_MS:-10000}"
    [[ "$kms" =~ ^[0-9]+$ ]] || kms=10000
    for (( i = 0; i < kms / 100; i++ )); do
        _kt_suitejob_alive "$p" || break
        _kt_strays_nap 0.1
        kill -KILL "$p" 2>/dev/null
    done
    if _kt_suitejob_alive "$p" && kt_proc_winkill "$p"; then
        echo "[WARN] job $p ignored SIGKILL: kill sent from the Windows side (kill -f, winpid ${REPLY#*=})"
        for (( i = 0; i < 50; i++ )); do
            _kt_suitejob_alive "$p" || break
            _kt_strays_nap 0.1
        done
    fi
    _kt_strays_nap_close
    if _kt_suitejob_alive "$p"; then
        kt_proc_winpid "$p"
        echo "[WARN] job $p could NOT be stopped${REPLY:+ (winpid $REPLY)}; not waited for"
        KT_SUITEJOB_RC=137 KT_SUITEJOB_LEADER_LEFT="$p=$REPLY"
        _KT_SUITEJOB_LEFT[$p]="$REPLY|$KT_SUITEJOB_CUR|0"
    else
        wait "$p" 2>/dev/null; KT_SUITEJOB_RC=$?
    fi
    KT_SUITEJOB_PID=""
    return 0
}

kt_suitejob_strays() {
    local rc=0
    KT_SUITEJOB_STRAY_LEFT=0
    _kt_suitejob_strays_scan "$1" || rc=1
    _kt_suitejob_leaders_left || rc=1
    return $rc
}
# _kt_suitejob_leaders_left — report the job leaders kt_suitejob_signal could
# not stop that still live (the same winpid; a zombie or a gone one is
# forgotten): each once after its stop, and again in every final check
# (KT_SUITEJOB_CUR empty). rc 1 when one was reported.
_kt_suitejob_leaders_left() {
    local p w lab rep rc=0
    for p in "${!_KT_SUITEJOB_LEFT[@]}"; do
        IFS='|' read -r w lab rep <<< "${_KT_SUITEJOB_LEFT[$p]}"
        if ! _kt_suitejob_alive "$p" || { kt_proc_winpid "$p"; [[ "$REPLY" != "$w" ]]; }; then
            unset "_KT_SUITEJOB_LEFT[$p]"
            continue
        fi
        [[ "$rep" == 1 && -n "$KT_SUITEJOB_CUR" ]] && continue
        _KT_SUITEJOB_LEFT[$p]="$w|$lab|1"
        echo "[WARN] job leader $p of $lab could NOT be stopped${w:+ (winpid $w)}"
        KT_SUITEJOB_STRAY_ROWS+=( "pid $p (job leader) started during $lab: could NOT be stopped${w:+ (winpid $w)}" )
        KT_SUITEJOB_STRAY_LABELS["$lab"]=1
        KT_SUITEJOB_STRAY_LEFT=$(( KT_SUITEJOB_STRAY_LEFT + 1 ))
        rc=1
    done
    return $rc
}
_kt_suitejob_strays_scan() {
    local label="$1" p i s c
    kt_strays_scan "${_KT_SUITEJOB_OPTS[@]}" "$KT_SUITEJOB_SINCE"
    # no process table at all (launch L2.1): say so, never a silent "none"
    [[ -n "$KT_STRAYS_UNKNOWN" ]] && { echo "[WARN] stray check after $label: n/a ($KT_STRAYS_UNKNOWN)"; return 0; }
    (( RESULT == 0 )) && return 0
    _kt_strays_nap_open; _kt_strays_nap 1; _kt_strays_nap_close
    kt_strays_scan "${_KT_SUITEJOB_OPTS[@]}" "$KT_SUITEJOB_SINCE"
    (( RESULT == 0 )) && return 0
    # busybox's `timeout N cmd` leaves its WATCHER (argv `timeout N cmd…`, a
    # detached root: adopted by init) for up to ~1 s after cmd ended: while
    # such a row is among the hits, look again — at most 3 s more (launch L2.1)
    if kt_proc_bbtimeout; then   # (ktest_proc.sh; _KTP_BBTMO=1: a test seam)
        for (( i = 0; i < 6; i++ )); do
            c=0
            for p in "${KT_STRAYS[@]}"; do
                [[ "${KT_STRAYS_FLAG[$p]}" == yes && "${KT_STRAYS_CMD[$p]}" == "timeout "* ]] && c=1
            done
            (( c )) || break
            _kt_strays_nap_open; _kt_strays_nap 0.5; _kt_strays_nap_close
            kt_strays_scan "${_KT_SUITEJOB_OPTS[@]}" "$KT_SUITEJOB_SINCE"
            (( RESULT == 0 )) && return 0
        done
    fi
    echo "[WARN] $RESULT stray process(es) found after $label:"
    for p in "${KT_STRAYS[@]}"; do
        s="$KT_SUITEJOB_BEFORE"
        # an estimate may be up to KT_PROC_START_EARLY_MS early (Linux: a
        # tick; ../ktest_proc.sh — launch L2.7-K)
        for (( i = 0; i < ${#KT_SUITEJOB_T0[@]}; i++ )); do
            (( KT_STRAYS_START[$p] + ${KT_PROC_START_EARLY_MS:-0} >= KT_SUITEJOB_T0[i] )) && s="${KT_SUITEJOB_NAMES[i]}"
        done
        KT_SUITEJOB_STRAY_LABELS["$s"]=1
        c="${KT_STRAYS_CMD[$p]//$'\n'/ }"; (( ${#c} > 100 )) && c="${c:0:97}..."
        printf '    pid %s ppid %s age %ss orphan=%s started during %s: %s\n' "$p" \
            "${KT_STRAYS_PPID[$p]}" "${KT_STRAYS_AGE[$p]}" "${KT_STRAYS_FLAG[$p]}" "$s" "$c"
        KT_SUITEJOB_STRAY_ROWS+=( "pid $p (${KT_STRAYS_FLAG[$p]}) started during $s: $c" )
    done
    if kt_strays_stop "${_KT_SUITEJOB_OPTS[@]}" "$KT_SUITEJOB_SINCE"; then
        echo "[WARN] stopped them, none left"
    else
        # each survivor's Windows pid (cygwin; launch L2.7-G), for a stop by hand
        s=""
        for p in "${KT_STRAYS[@]}"; do kt_proc_winpid "$p" && s+="${s:+ }$p=$REPLY"; done
        KT_SUITEJOB_STRAY_LEFT=$RESULT
        echo "[WARN] $RESULT could NOT be stopped${s:+ (winpid $s)}:"
        kt_strays_print '    '
    fi
    return 1
}
