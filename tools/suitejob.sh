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
#                       the job's leader lives, then KILL to the group, reap.
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
#                       started), stop them, record, rc 1.
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
    KT_SUITEJOB_CUR="$label"
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

kt_suitejob_signal() {
    local i p="$KT_SUITEJOB_PID"
    KT_SUITEJOB_SIGNAL_RC="${1:-}"
    [[ -n "$p" ]] || return 0
    kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null
    kill -CONT -- "-$p" 2>/dev/null || kill -CONT "$p" 2>/dev/null
    _kt_strays_nap_open
    for (( i = 0; i < KT_SUITEJOB_GRACE; i++ )); do
        kill -0 "$p" 2>/dev/null || break
        _kt_strays_nap 0.1
    done
    _kt_strays_nap_close
    kill -KILL -- "-$p" 2>/dev/null || kill -KILL "$p" 2>/dev/null
    wait "$p" 2>/dev/null; KT_SUITEJOB_RC=$?
    KT_SUITEJOB_PID=""
    return 0
}

kt_suitejob_strays() {
    local label="$1" p i s c
    kt_strays_scan "${_KT_SUITEJOB_OPTS[@]}" "$KT_SUITEJOB_SINCE"
    (( RESULT == 0 )) && return 0
    _kt_strays_nap_open; _kt_strays_nap 1; _kt_strays_nap_close
    kt_strays_scan "${_KT_SUITEJOB_OPTS[@]}" "$KT_SUITEJOB_SINCE"
    (( RESULT == 0 )) && return 0
    echo "[WARN] $RESULT stray process(es) found after $label:"
    for p in "${KT_STRAYS[@]}"; do
        s="$KT_SUITEJOB_BEFORE"
        for (( i = 0; i < ${#KT_SUITEJOB_T0[@]}; i++ )); do
            (( KT_STRAYS_START[$p] >= KT_SUITEJOB_T0[i] )) && s="${KT_SUITEJOB_NAMES[i]}"
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
        echo "[WARN] $RESULT could NOT be stopped:"
        kt_strays_print '    '
    fi
    return 1
}
