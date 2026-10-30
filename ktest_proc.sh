#!/usr/bin/env bash
# ktest_proc.sh — the process table of the ktests harness, one API over the
# platforms (launch L2.1, PORTING.md H1-H3). A library: source it, nothing runs
# on source. Plain bash, no kbool/kkore/kklass. Sourced by ktest_runner.sh (the
# group stop), tools/strays.sh (the stray guard) and tools/forkstorm.sh.
#
# BACKENDS — chosen once per process, at the first call (kt_proc_init):
#   cygwin  /proc/PID/{ppid,pgid,sid,cmdline} (Git-bash, MSYS2): cheap reads
#           from cygwin's shared table; /proc/PID/stat (state, start time in ms
#           since boot) costs ~20 ms a process there, so strays.sh and the
#           runner keep their own cygwin code that reads stat only for the few
#           candidates (unchanged since before L2.1).
#   linux   /proc/PID/stat — one read gives state, ppid, pgrp, session and the
#           start time (field 22, clock ticks since boot; the comm field may
#           hold spaces and parentheses: the fields are counted from the LAST
#           ") "), /proc/PID/cmdline for the command line. No fork. The start
#           epoch = (now - /proc/uptime) + ticks * 1000 / HZ; HZ (USER_HZ) is
#           taken as 100 when this shell's own start time agrees with it,
#           else read once with `getconf CLK_TCK`. Both /proc/uptime and the
#           ticks truncate to a tick (10 ms), so the estimate can be up to one
#           tick EARLIER than the real start (measured: 3-5 % of the forks
#           taken right after a window start look 5-10 ms early — launch
#           L2.7-K): KT_PROC_START_EARLY_MS=20.
#   ps      no /proc (FreeBSD, macOS) or a Linux without it: ONE `ps` fork per
#           snapshot, `TZ=UTC0 LC_ALL=C ps -A -ww -o pid= -o ppid= -o pgid=
#           -o sid= -o state= -o etimes= -o lstart= -o args=` (one -o per
#           keyword: BSD ps takes the rest of an `-o a=,b=` argument as a's
#           header), the rows split by one `read` each. The keywords are
#           probed once (one ps call when the full set works, a few more
#           otherwise): pid ppid pgid args and etimes|etime are required,
#           sid, state and lstart optional — POSIX itself has only pid ppid
#           pgid etime args. The start is known to the SECOND: lstart (UTC,
#           turned into epoch seconds), else ps's whole-second clock minus
#           etime(s) (BSD ps truncates both, so etimes may exceed the real
#           elapsed time by up to 1 s). The start estimate is the END of that
#           second: never earlier than the real start, at most 1 s later
#           (KT_PROC_START_RES_MS=1000; a --since window is that coarse). The
#           start IDENTITY of a pid (reused pids) is that second. The ps
#           process itself is left out (`exec ps` in the $( ): no subshell).
#   none    nothing works: KT_PROC_WHY says why. Callers must not report
#           "no strays" then (strays.sh prints `strays: UNKNOWN (...)`).
# KT_PROC_BACKEND set in the environment (cygwin|linux|ps|none) forces a
# backend — the tests use it to run the ps backend on Linux and the none path.
# KT_PROC_NAPFD=fifo (a test knob, launch L5.4-8) forces kt_proc_napfd's FIFO
# path (FreeBSD's: no /dev/ptmx) on every platform.
#
# API
#   kt_proc_init          KT_PROC_BACKEND, KT_PROC_WHY, KT_PROC_HAS_SID (0/1:
#                         a session column exists), KT_PROC_HAS_STATE;
#                         KT_PROC_START_RES_MS (how coarse start times are:
#                         cygwin 1, Linux 10 = a clock tick, ps 1000);
#                         KT_PROC_START_EARLY_MS (how much EARLIER than the
#                         real start an estimate can be: linux 20, cygwin 0,
#                         ps 0 — every comparison of a start with a window
#                         start allows it: START + EARLY >= T0); rc 0
#                         when a backend works, 1 for none
#   kt_proc_snapshot [--cmd] [PREFIX]   the whole table into the global
#                         assoc arrays PREFIX{PP,PG,SID,STATE,RAW,ST,CMD}
#                         (default PREFIX KT_PROC_): ppid, pgid, session,
#                         state (first letter, Z = zombie), start identity,
#                         start epoch ms, command line (argv joined by spaces;
#                         only with --cmd, else empty); KT_PROC_NOW_MS = the
#                         snapshot's time. cygwin: PP/PG/SID (and CMD) only,
#                         STATE/RAW/ST empty (its stat is too slow for a full
#                         pass). rc 1 for none (arrays empty).
#   kt_proc_ppid PID / kt_proc_sid PID / kt_proc_pgid PID   REPLY = that value
#                         read NOW ("" when PID is gone); ps: one fork
#   kt_proc_state PID     REPLY = PID's state letter now (T stopped, Z zombie)
#   kt_proc_cmd PID       REPLY = PID's command line now ("" when gone)
#   kt_proc_samepipe P1 F1 P2 F2  rc 0 when fd F1 of P1 and fd F2 of P2 are the
#                         ends of ONE pipe: /proc/PID/fd (cygwin, Linux), else
#                         `fstat -p` (FreeBSD); rc 1 when unknown
#   kt_proc_adopted PID   rc 0 when PID's parent is 1 (cygwin: only that), of
#                         another session, or a `timeout` (a reaper) on this
#                         shell's ancestor chain: its own parent is gone
#   kt_proc_cwd PID       REPLY = PID's working directory ("" unknown):
#                         /proc/PID/cwd; ps: `procstat -f` where it exists
#   kt_proc_pids TEXT     REPLY = the pids (not this shell) whose command line
#                         contains TEXT, space-separated (the /proc
#                         listing order; ps: ascending)
#   kt_proc_pids_gone TEXT [S]  kt_proc_pids TEXT after up to S seconds (3) for
#                         it to empty (busybox timeout watchers linger ~1 s)
#   kt_proc_pid0 NAME     REPLY = the pids whose argv[0] is exactly NAME (ps:
#                         the first word of the command line)
#   kt_proc_napfd         REPLY = a new fd for fork-free `read -t` naps (a pty
#                         master, else an unlinked FIFO of its own; "" none)
#   kt_proc_ms TEXT       REPLY = TEXT (seconds, "." or "," fraction) in ms
#   kt_proc_winpid PID    REPLY = the Windows pid behind cygwin PID
#                         (/proc/PID/winpid); rc 1 and "" off cygwin or
#                         when PID is gone
#   kt_proc_winkill PID...  the LAST step of a stop (launch L2.7-G), cygwin
#                         only, for PIDs that outlived SIGKILL — a process
#                         whose cygwin signal handling is stuck (2026-10-22:
#                         two runners wedged in the Git runtime, one spinning
#                         a core; a Windows-suspended one) never acts on a
#                         cygwin signal. Per PID: the runtime's own
#                         `kill -f -9 PID` (by the cygwin pid: it opens and
#                         terminates the Windows process in one step, no
#                         winpid-reuse window); only when that fails, a
#                         narrowed `taskkill /F /FI "PID eq W" /FI
#                         "IMAGENAME eq NAME"` (W and NAME re-read from
#                         /proc/PID/winpid and winexename just before). Both
#                         bounded by the runtime's own `timeout`. The caller
#                         checks PID's identity first (pids are reused) and
#                         whether it is gone after. REPLY = "PID=WINPID …" of
#                         those it was SENT for; rc 1 (REPLY "") off cygwin
#                         or with no live winpid

if [[ -n "${_KT_PROC_SOURCED:-}" && "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi
_KT_PROC_SOURCED=1

declare -g  KT_PROC_BACKEND="${KT_PROC_BACKEND:-}" KT_PROC_WHY="" KT_PROC_HAS_SID=0 KT_PROC_HAS_STATE=0
declare -g  KT_PROC_START_RES_MS=1 KT_PROC_START_EARLY_MS=0
declare -g  KT_PROC_NOW_MS=0 _KTP_READY="" _KTP_HZ=100 _KTP_PSLS=0 _KTP_PSET=etimes _KTP_PSSTK=state
declare -ga _KTP_PSARGS=() _KTP_PSVARS=()
# KT_TMO_BOUND — the `timeout` options that keep it a plain time bound for a
# command that leaves a background process on purpose: FreeBSD's timeout
# without --foreground becomes the REAPER of everything below it and WAITS
# for all of it (to its limit — then it kills it); --foreground there, none
# elsewhere (launch L2.1)
declare -ga KT_TMO_BOUND=()
[[ "$OSTYPE" == freebsd* ]] && KT_TMO_BOUND=( --foreground )
declare -gA KT_PROC_PP=() KT_PROC_PG=() KT_PROC_SID=() KT_PROC_STATE=() KT_PROC_RAW=() KT_PROC_ST=() KT_PROC_CMD=()

# kt_proc_napfd — REPLY = a NEW fd that `read -t` can wait on and that never
# has data: the fork-free nap of the harness. A pty master (/dev/ptmx) where
# there is one (cygwin, Linux); else a FIFO of its own, opened read-write and
# unlinked at once (FreeBSD has no /dev/ptmx: one mkfifo, then no fork per
# nap — a `sleep` child per nap would show up as a fork of e.g. the gate's
# watchdog); else "" (rc 1: the caller sleeps). `-c` first: `<>` would try
# to CREATE a missing /dev/ptmx. The caller closes the fd.
kt_proc_napfd() {
    local __ktp_fd __ktp_ff
    REPLY=""
    if [[ "${KT_PROC_NAPFD:-}" != fifo && -c /dev/ptmx ]] && { exec {__ktp_fd}<>/dev/ptmx; } 2>/dev/null; then
        REPLY="$__ktp_fd"; return 0
    fi
    __ktp_ff="${TMPDIR:-/tmp}/kt_nap.$BASHPID.$RANDOM$RANDOM"
    if mkfifo -m 600 -- "$__ktp_ff" 2>/dev/null; then
        { exec {__ktp_fd}<>"$__ktp_ff"; } 2>/dev/null && REPLY="$__ktp_fd"
        rm -f -- "$__ktp_ff"
    fi
    [[ -n "$REPLY" ]]
    return $?
}

# kt_proc_ms TEXT — REPLY = TEXT (seconds, "." or "," fraction) in ms
kt_proc_ms() {
    local s="${1:-0}" i f
    s="${s/,/.}"
    i="${s%%.*}"; f=""
    [[ "$s" == *.* ]] && f="${s#*.}"
    f="${f}000"; f="${f:0:3}"
    [[ "$i" =~ ^[0-9]+$ ]] || i=0
    [[ "$f" =~ ^[0-9]+$ ]] || f=000
    REPLY=$(( 10#$i * 1000 + 10#$f ))
}

# _kt_proc_etime TEXT — REPLY = a ps etime `[[dd-]hh:]mm:ss` in seconds (rc 1
# when it is none)
_kt_proc_etime() {
    local t="$1" d=0 h=0 m=0 s=0
    [[ "$t" =~ ^(([0-9]+)-)?(([0-9]+):)?([0-9]+):([0-9]+)$ ]] || return 1
    d="${BASH_REMATCH[2]:-0}" h="${BASH_REMATCH[4]:-0}" m="${BASH_REMATCH[5]}" s="${BASH_REMATCH[6]}"
    REPLY=$(( ((10#$d * 24 + 10#$h) * 60 + 10#$m) * 60 + 10#$s ))
}

# _kt_proc_ps_try KW... — rc 0 when `ps -o KW= ... -p PID` prints a row for
# this shell with one value per keyword (args: the rest)
_kt_proc_ps_try() {
    local -a a=() w=()
    local k o me="$BASHPID"   # this process (not $$: a subshell's parent may be gone)
    for k in "$@"; do a+=( -o "$k=" ); done
    o="$(LC_ALL=C exec ps "${a[@]}" -p "$me" 2>/dev/null)" || return 1
    o="${o%%$'\n'*}"
    read -r -a w <<< "$o"
    [[ "${w[0]:-}" == "$me" ]] || return 1
    return 0
}

# _kt_proc_ps_probe — the ps keyword set (see BACKENDS); rc 1 without a usable ps
_kt_proc_ps_probe() {
    local -a kw=() opt=()
    local k ww=()
    command -v ps >/dev/null 2>&1 || { KT_PROC_WHY="no /proc and no ps"; return 1; }
    if _kt_proc_ps_try pid ppid pgid sid state etimes lstart args; then
        kw=( pid ppid pgid sid state etimes lstart args )
    else
        _kt_proc_ps_try pid ppid pgid args || { KT_PROC_WHY="ps -o pid=,ppid=,pgid=,args= does not work"; return 1; }
        kw=( pid ppid pgid )
        _kt_proc_ps_try pid sid && kw+=( sid )
        if _kt_proc_ps_try pid state; then kw+=( state ); elif _kt_proc_ps_try pid stat; then kw+=( stat ); fi
        if _kt_proc_ps_try pid etimes; then kw+=( etimes ); elif _kt_proc_ps_try pid etime; then kw+=( etime ); else
            KT_PROC_WHY="ps has neither etimes nor etime"; return 1
        fi
        _kt_proc_ps_try pid lstart && kw+=( lstart )
        kw+=( args )
    fi
    # -ww (no width limit) where ps takes it (BSD, procps, macOS)
    LC_ALL=C ps -ww -o pid= -p "$BASHPID" >/dev/null 2>&1 && ww=( -ww )
    _KTP_PSARGS=( -A "${ww[@]}" )
    KT_PROC_HAS_SID=0 KT_PROC_HAS_STATE=0 _KTP_PSLS=0 _KTP_PSET=etimes
    # the snapshot splits each row with ONE `read` into these names (the last
    # one takes the command line); a regex per row was ~4 ms on FreeBSD
    _KTP_PSVARS=()
    for k in "${kw[@]}"; do
        _KTP_PSARGS+=( -o "$k=" )
        case "$k" in
            sid) KT_PROC_HAS_SID=1; _KTP_PSVARS+=( __ktp_xsid ) ;;
            state|stat) KT_PROC_HAS_STATE=1; _KTP_PSSTK="$k"; _KTP_PSVARS+=( __ktp_xst ) ;;
            etimes|etime) _KTP_PSET="$k"; _KTP_PSVARS+=( __ktp_xet ) ;;
            lstart) _KTP_PSLS=1; _KTP_PSVARS+=( __ktp_xl1 __ktp_xl2 __ktp_xl3 __ktp_xl4 __ktp_xl5 ) ;;
            pid|ppid|pgid|args) _KTP_PSVARS+=( "__ktp_x$k" ) ;;
        esac
    done
    return 0
}

# kt_proc_init — choose the backend once (see BACKENDS); rc 1 for none
kt_proc_init() {
    # `return $?`, never a bare return: in a trap handler (the group stop in
    # ktests.sh's TERM trap) a bare return gives the status from BEFORE the trap
    if [[ -n "$_KTP_READY" ]]; then [[ "$KT_PROC_BACKEND" != none ]]; return $?; fi
    _KTP_READY=1
    local f="$KT_PROC_BACKEND" line rest up s __ktp_r="${REPLY-}"
    # REPLY is the caller's: the Linux branch uses kt_proc_ms (restored below;
    # L2.1 review — kt_runner_proc_start returned the uptime for a gone pid)
    local -a a
    KT_PROC_BACKEND=""
    case "$f" in
        cygwin|linux|ps|none|"") ;;
        *) f="" ;;
    esac
    if [[ -z "$f" ]]; then
        if [[ -r /proc/$BASHPID/ppid && -r /proc/$BASHPID/pgid ]]; then f=cygwin
        elif [[ "$OSTYPE" == linux* && -r /proc/$BASHPID/stat ]]; then f=linux
        else f=ps; fi
    fi
    case "$f" in
        # KT_PROC_START_EARLY_MS (launch L2.7-K): cygwin 0 — the boot epoch
        # from a truncated /proc/uptime is late, the start in ms (measured: no
        # fork right after t0 looked early, 500 of 500 on both runtimes)
        cygwin) KT_PROC_HAS_SID=1 KT_PROC_HAS_STATE=1 KT_PROC_START_RES_MS=1 KT_PROC_START_EARLY_MS=0 ;;
        linux)
            line=""; { IFS= read -r line < /proc/self/stat; } 2>/dev/null
            rest="${line##*) }"; a=( $rest )
            if [[ "$line" != *") "* ]] || (( ${#a[@]} < 20 )); then
                KT_PROC_WHY="/proc/self/stat unreadable or not in the Linux format"; f=none
            else
                KT_PROC_HAS_SID=1 KT_PROC_HAS_STATE=1
                KT_PROC_START_RES_MS=10 KT_PROC_START_EARLY_MS=20
                # USER_HZ: 100 unless this shell's start (ticks) would lie in
                # the future at 100/s; then ask getconf once
                up=0; { read -r up _ < /proc/uptime; } 2>/dev/null
                kt_proc_ms "$up"
                if (( a[19] * 10 > REPLY + 2000 )); then
                    s="$(getconf CLK_TCK 2>/dev/null)"
                    [[ "$s" =~ ^[1-9][0-9]*$ ]] && _KTP_HZ=$s
                fi
            fi ;;
        # ps 0: the END of the start's second — FreeBSD's and macOS' lstart is
        # the kernel's own start time (and ps-clock - etime(s) cannot name an
        # earlier second); a procps ps on Linux (only when forced: procps needs
        # /proc) builds lstart on the whole-second btime and can be up to 1 s
        # early — nothing compares windows that way
        ps) KT_PROC_START_RES_MS=1000 KT_PROC_START_EARLY_MS=0; _kt_proc_ps_probe || f=none ;;
        none) KT_PROC_WHY="${KT_PROC_WHY:-forced (KT_PROC_BACKEND=none)}" ;;
    esac
    KT_PROC_BACKEND="$f"
    REPLY="$__ktp_r"
    [[ "$f" != none ]]
}

# _kt_proc_lstart MON DAY HH:MM:SS YEAR — REPLY = that UTC time (a ps lstart
# under TZ=UTC0 LC_ALL=C) in epoch seconds; rc 1 when it is no such time
_kt_proc_lstart() {
    local m y d h mi s era yoe mp doy doe
    case "$1" in
        Jan) m=1 ;; Feb) m=2 ;; Mar) m=3 ;; Apr) m=4 ;; May) m=5 ;; Jun) m=6 ;;
        Jul) m=7 ;; Aug) m=8 ;; Sep) m=9 ;; Oct) m=10 ;; Nov) m=11 ;; Dec) m=12 ;;
        *) return 1 ;;
    esac
    [[ "$2" =~ ^[0-9]{1,2}$ && "$4" =~ ^[0-9]{4}$ && "$3" =~ ^([0-9]{1,2}):([0-9]{2}):([0-9]{2})$ ]] || return 1
    h=$(( 10#${BASH_REMATCH[1]} )) mi=$(( 10#${BASH_REMATCH[2]} )) s=$(( 10#${BASH_REMATCH[3]} ))
    d=$(( 10#$2 )) y=$(( 10#$4 ))
    # days from the civil date (H. Hinnant's algorithm)
    (( m <= 2 )) && y=$(( y - 1 ))
    era=$(( y / 400 )) yoe=$(( y - y / 400 * 400 )) mp=$(( (m + 9) % 12 ))
    doy=$(( (153 * mp + 2) / 5 + d - 1 ))
    doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
    REPLY=$(( (era * 146097 + doe - 719468) * 86400 + h * 3600 + mi * 60 + s ))
    return 0
}

# _kt_proc_now — KT_PROC_NOW_MS = now
_kt_proc_now() { kt_proc_ms "$EPOCHREALTIME"; KT_PROC_NOW_MS=$REPLY; }

# kt_proc_snapshot [--cmd] [PREFIX] — see the API
kt_proc_snapshot() {
    local __ktp_cmd=0 __ktp_pre=KT_PROC_
    [[ "${1:-}" == --cmd ]] && { __ktp_cmd=1; shift; }
    [[ -n "${1:-}" ]] && __ktp_pre="$1"
    local -n __ktp_PP="${__ktp_pre}PP" __ktp_PG="${__ktp_pre}PG" __ktp_SID="${__ktp_pre}SID" \
        __ktp_STATE="${__ktp_pre}STATE" __ktp_RAW="${__ktp_pre}RAW" __ktp_ST="${__ktp_pre}ST" __ktp_CMD="${__ktp_pre}CMD"
    __ktp_PP=(); __ktp_PG=(); __ktp_SID=(); __ktp_STATE=(); __ktp_RAW=(); __ktp_ST=(); __ktp_CMD=()
    kt_proc_init || { _kt_proc_now; return 1; }
    local __ktp_f __ktp_p __ktp_l __ktp_r __ktp_up __ktp_boot __ktp_c __ktp_out __ktp_et __ktp_me __ktp_ns __ktp_s IFS=$' \t\n'
    local -a __ktp_a __ktp_v __ktp_L
    case "$KT_PROC_BACKEND" in
        cygwin)
            _kt_proc_now
            for __ktp_f in /proc/[0-9]*; do
                __ktp_p="${__ktp_f#/proc/}"
                __ktp_a=( "" "" "" )
                { read -r __ktp_a[0] < "$__ktp_f/ppid"; read -r __ktp_a[1] < "$__ktp_f/pgid"; read -r __ktp_a[2] < "$__ktp_f/sid"; } 2>/dev/null
                [[ -n "${__ktp_a[0]}" && "${__ktp_a[0]}" != *[!0-9]* ]] || continue
                __ktp_PP[$__ktp_p]="${__ktp_a[0]}"; __ktp_PG[$__ktp_p]="${__ktp_a[1]}"; __ktp_SID[$__ktp_p]="${__ktp_a[2]}"
                __ktp_CMD[$__ktp_p]=""
                if (( __ktp_cmd )); then
                    __ktp_v=(); { mapfile -d '' -t __ktp_v < "$__ktp_f/cmdline"; } 2>/dev/null
                    __ktp_CMD[$__ktp_p]="${__ktp_v[*]}"
                fi
            done ;;
        linux)
            __ktp_up=0; { read -r __ktp_up _ < /proc/uptime; } 2>/dev/null
            _kt_proc_now
            kt_proc_ms "$__ktp_up"; __ktp_boot=$(( KT_PROC_NOW_MS - REPLY ))
            for __ktp_f in /proc/[0-9]*; do
                __ktp_p="${__ktp_f#/proc/}"
                __ktp_l=""; { IFS= read -r __ktp_l < "$__ktp_f/stat"; } 2>/dev/null
                [[ "$__ktp_l" == *") "* ]] || continue
                __ktp_r="${__ktp_l##*) }"
                __ktp_a=( $__ktp_r )
                (( ${#__ktp_a[@]} >= 20 )) || continue
                __ktp_STATE[$__ktp_p]="${__ktp_a[0]}"; __ktp_PP[$__ktp_p]="${__ktp_a[1]}"
                __ktp_PG[$__ktp_p]="${__ktp_a[2]}"; __ktp_SID[$__ktp_p]="${__ktp_a[3]}"
                __ktp_RAW[$__ktp_p]="${__ktp_a[19]}"
                __ktp_ST[$__ktp_p]=$(( __ktp_boot + __ktp_a[19] * 1000 / _KTP_HZ ))
                __ktp_CMD[$__ktp_p]=""
                if (( __ktp_cmd )); then
                    __ktp_v=(); { mapfile -d '' -t __ktp_v < "$__ktp_f/cmdline"; } 2>/dev/null
                    __ktp_c="${__ktp_v[*]}"
                    # a kernel thread or a zombie has no argv: [comm] like ps
                    if [[ -z "$__ktp_c" ]]; then __ktp_c="${__ktp_l#* (}"; __ktp_c="[${__ktp_c%) *}]"; fi
                    __ktp_CMD[$__ktp_p]="$__ktp_c"
                fi
            done ;;
        ps)
            # `exec`: the $( ) child IS the ps — no subshell copy of this shell in it
            # TZ=UTC0: lstart in UTC (it is turned into epoch seconds below)
            __ktp_out="$(TZ=UTC0 LC_ALL=C exec ps "${_KTP_PSARGS[@]}" 2>/dev/null)"
            _kt_proc_now
            __ktp_ns=$(( KT_PROC_NOW_MS / 1000 ))
            # the ps process itself: this shell's child running exactly our argv
            __ktp_me="ps ${_KTP_PSARGS[*]}"
            local __ktp_xpid __ktp_xppid __ktp_xpgid __ktp_xsid="" __ktp_xst="" __ktp_xet=0 __ktp_xargs \
                __ktp_xl1 __ktp_xl2 __ktp_xl3 __ktp_xl4 __ktp_xl5
            while read -r "${_KTP_PSVARS[@]}"; do
                [[ -n "$__ktp_xpid" && "$__ktp_xpid" != *[!0-9]* ]] || continue
                [[ "$__ktp_xppid" == "$BASHPID" && "$__ktp_xargs" == "$__ktp_me" ]] && continue
                __ktp_p="$__ktp_xpid"
                __ktp_PP[$__ktp_p]="$__ktp_xppid"; __ktp_PG[$__ktp_p]="$__ktp_xpgid"
                __ktp_SID[$__ktp_p]="$__ktp_xsid"; __ktp_STATE[$__ktp_p]="${__ktp_xst:0:1}"
                __ktp_et="$__ktp_xet"
                if [[ "$_KTP_PSET" == etime ]]; then _kt_proc_etime "$__ktp_et" || REPLY=0; __ktp_et=$REPLY; fi
                [[ -n "$__ktp_et" && "$__ktp_et" != *[!0-9]* ]] || __ktp_et=0
                # the start in WHOLE seconds: lstart (the kernel's start tv_sec), else
                # from etime(s) = ps's whole-second clock - the start's (BSD ps: both
                # truncated, so etimes may exceed the real elapsed time by up to 1 s)
                if (( _KTP_PSLS )) && _kt_proc_lstart "$__ktp_xl2" "$__ktp_xl3" "$__ktp_xl4" "$__ktp_xl5"; then
                    __ktp_s=$REPLY
                else
                    __ktp_s=$(( __ktp_ns - 10#$__ktp_et ))
                fi
                # the real start lies in [s, s+1): its END is the estimate, never
                # earlier than the real start (at most 1 s later), never in the future
                __ktp_ST[$__ktp_p]=$(( __ktp_s * 1000 + 999 ))
                (( __ktp_ST[$__ktp_p] > KT_PROC_NOW_MS )) && __ktp_ST[$__ktp_p]=$KT_PROC_NOW_MS
                __ktp_RAW[$__ktp_p]="$__ktp_s"
                if (( __ktp_cmd )); then __ktp_CMD[$__ktp_p]="$__ktp_xargs"; else __ktp_CMD[$__ktp_p]=""; fi
            done <<< "$__ktp_out" ;;
    esac
    return 0
}

# _kt_proc_one PID KW — REPLY = PID's ps KW now ("" when gone): one fork
_kt_proc_one() {
    local o
    o="$(LC_ALL=C exec ps -o "$2=" -p "$1" 2>/dev/null)" || o=""
    o="${o%%$'\n'*}"
    o="${o#"${o%%[! ]*}"}"; o="${o%"${o##*[! ]}"}"
    REPLY="$o"
}

# _kt_proc_stat_field PID I — REPLY = field I (0 = state) after the comm of
# /proc/PID/stat ("" when gone); linux and cygwin
_kt_proc_stat_field() {
    local l="" IFS=$' \t\n'
    local -a a
    REPLY=""
    { IFS= read -r l < "/proc/$1/stat"; } 2>/dev/null
    [[ "$l" == *") "* ]] || return 0
    a=( ${l##*) } )
    REPLY="${a[$2]:-}"
}

kt_proc_ppid() {
    kt_proc_init
    case "$KT_PROC_BACKEND" in
        cygwin) REPLY=""; { read -r REPLY < "/proc/$1/ppid"; } 2>/dev/null ;;
        linux) _kt_proc_stat_field "$1" 1 ;;
        ps) _kt_proc_one "$1" ppid ;;
        *) REPLY="" ;;
    esac
}
kt_proc_pgid() {
    kt_proc_init
    case "$KT_PROC_BACKEND" in
        cygwin) REPLY=""; { read -r REPLY < "/proc/$1/pgid"; } 2>/dev/null ;;
        linux) _kt_proc_stat_field "$1" 2 ;;
        ps) _kt_proc_one "$1" pgid ;;
        *) REPLY="" ;;
    esac
}
kt_proc_sid() {
    kt_proc_init
    case "$KT_PROC_BACKEND" in
        cygwin) REPLY=""; { read -r REPLY < "/proc/$1/sid"; } 2>/dev/null ;;
        linux) _kt_proc_stat_field "$1" 3 ;;
        ps) REPLY=""; (( KT_PROC_HAS_SID )) && _kt_proc_one "$1" sid ;;
        *) REPLY="" ;;
    esac
}
# kt_proc_state PID — REPLY = PID's state letter now (Z zombie, T stopped, ...; "" when gone)
kt_proc_state() {
    kt_proc_init
    case "$KT_PROC_BACKEND" in
        cygwin|linux) _kt_proc_stat_field "$1" 0 ;;
        ps) REPLY=""; (( KT_PROC_HAS_STATE )) && _kt_proc_one "$1" "$_KTP_PSSTK"; REPLY="${REPLY:0:1}" ;;
        *) REPLY="" ;;
    esac
}
kt_proc_cmd() {
    local -a v=()
    kt_proc_init
    case "$KT_PROC_BACKEND" in
        cygwin|linux) { mapfile -d '' -t v < "/proc/$1/cmdline"; } 2>/dev/null; REPLY="${v[*]}" ;;
        ps) _kt_proc_one "$1" args ;;
        *) REPLY="" ;;
    esac
}
kt_proc_samepipe() {
    local a
    if [[ -e "/proc/$1/fd/$2" ]]; then
        [[ -p "/proc/$1/fd/$2" && "/proc/$1/fd/$2" -ef "/proc/$3/fd/$4" ]]
        return $?
    fi
    command -v fstat >/dev/null 2>&1 || return 1
    _kt_proc_pipeid "$1" "$2"; a="$REPLY"
    _kt_proc_pipeid "$3" "$4"
    [[ -n "$a" && "$a" == "$REPLY" ]]
    return $?
}
# _kt_proc_pipeid PID FD — REPLY = "LO HI", the two kernel addresses of the
# pipe FD of PID is an end of (FreeBSD `fstat -p`: `pipe ADDR <-> PEER`; the
# two ends of one pipe give the same pair), "" when it is no pipe
_kt_proc_pipeid() {
    local o l u c p fd t x arrow y
    REPLY=""
    o="$(LC_ALL=C exec fstat -p "$1" 2>/dev/null)"
    while read -r u c p fd t x arrow y _; do
        [[ "$fd" == "$2" || "$fd" == "$2"\* ]] || continue
        [[ "$t" == pipe && "$arrow" == "<->" ]] || return 0
        if [[ "$x" < "$y" ]]; then REPLY="$x $y"; else REPLY="$y $x"; fi
        return 0
    done <<< "$o"
    return 0
}
# kt_proc_adopted PID — rc 0 when PID has been ADOPTED (the parent that started
# it is gone): its parent now is pid 1 — on cygwin that is all, as it always
# was; elsewhere also a process of another session (a subreaper: `systemd
# --user`, a container's init) or a `timeout` on THIS shell's own ancestor
# chain (FreeBSD's is the reaper of all below it — as strays.sh reads it).
# For tests that wait for an orphan.
kt_proc_adopted() {
    local pp s a n=0
    kt_proc_ppid "$1"; pp="$REPLY"
    [[ -n "$pp" ]] || return 1
    [[ "$pp" == 1 ]] && return 0
    [[ "$KT_PROC_BACKEND" == cygwin ]] && return 1
    kt_proc_sid "$1"; s="$REPLY"
    kt_proc_sid "$pp"
    [[ -n "$s" && -n "$REPLY" && "$s" != "$REPLY" ]] && return 0
    kt_proc_cmd "$pp"
    [[ "$REPLY" == "timeout "* || "$REPLY" == */"timeout "* || "$REPLY" == "gtimeout "* || "$REPLY" == */"gtimeout "* ]] || return 1
    a="$BASHPID"
    while [[ -n "$a" && "$a" != 0 && "$a" != 1 ]] && (( n++ < 200 )); do
        [[ "$a" == "$pp" ]] && return 0
        kt_proc_ppid "$a"; [[ "$REPLY" == "$a" ]] && break
        a="$REPLY"
    done
    return 1
}
kt_proc_cwd() {
    local old="$PWD" oldold="${OLDPWD-}" l rest o
    kt_proc_init
    REPLY=""
    case "$KT_PROC_BACKEND" in
        cygwin|linux)
            if builtin cd -P -- "/proc/$1/cwd" 2>/dev/null; then
                REPLY="$PWD"; builtin cd -- "$old" 2>/dev/null
            fi
            OLDPWD="$oldold" ;;
        ps)
            # FreeBSD: `procstat -f PID`, the row whose FD column is `cwd`
            # (a here-string: FreeBSD bash makes `<( )` a FIFO in TMPDIR)
            command -v procstat >/dev/null 2>&1 || return 0
            o="$(LC_ALL=C exec procstat -h -f "$1" 2>/dev/null)"
            while read -r _ _ l _ _ _ _ _ _ rest; do
                [[ "$l" == cwd ]] && { REPLY="$rest"; break; }
            done <<< "$o" ;;
    esac
    return 0
}

kt_proc_pids() {
    local p f out=""
    local -a ord=() a
    kt_proc_init || { REPLY=""; return 0; }
    if [[ "$KT_PROC_BACKEND" == ps ]]; then
        kt_proc_snapshot --cmd _KTP_Q
        for p in "${!_KTP_QCMD[@]}"; do
            [[ "$p" == "$$" || "$p" == "$BASHPID" ]] && continue
            [[ "${_KTP_QCMD[$p]}" == *"$1"* ]] && ord[$p]=1
        done
        for p in "${!ord[@]}"; do out+="$p "; done
        REPLY="${out% }"
        return 0
    fi
    # /proc: the command lines alone (one read a process)
    for f in /proc/[0-9]*/cmdline; do
        a=()
        { mapfile -d '' -t a < "$f"; } 2>/dev/null || continue
        [[ "${a[*]}" == *"$1"* ]] || continue
        p="${f#/proc/}"; p="${p%/cmdline}"
        [[ "$p" == "$$" || "$p" == "$BASHPID" ]] && continue
        out+="$p "
    done
    REPLY="${out% }"
    return 0
}
# kt_proc_pids_gone TEXT [SECONDS] — kt_proc_pids TEXT once it is empty, polled
# 0.1 s apart for up to SECONDS (default 3): REPLY = what is STILL there. For
# "nothing is left" checks: busybox's `timeout N cmd` leaves its watcher (with
# that command line) for up to a second after cmd ended — not a leak
kt_proc_pids_gone() {
    local i n=$(( ${2:-3} * 10 ))
    kt_proc_pids "$1"
    # only where that watcher exists: elsewhere (cygwin, GNU, BSD) the check is
    # immediate, as it always was
    [[ -z "$REPLY" ]] || kt_proc_bbtimeout || return 0
    for (( i = 0; i < n; i++ )); do
        [[ -z "$REPLY" ]] && return 0
        sleep 0.1
        kt_proc_pids "$1"
    done
    return 0
}
kt_proc_winpid() {
    REPLY=""
    kt_proc_init
    [[ "$KT_PROC_BACKEND" == cygwin ]] || return 1
    { read -r REPLY < "/proc/$1/winpid"; } 2>/dev/null
    [[ "$REPLY" =~ ^[1-9][0-9]*$ ]] && return 0
    REPLY=""
    return 1
}
kt_proc_winkill() {
    local __ktp_p __ktp_w __ktp_x __ktp_tk="" __ktp_out="" __ktp_rc
    local __ktp_bin="${BASH%/*}"
    local -a __ktp_tmo=()
    # the runtime's own timeout (never System32's timeout.exe from PATH)
    [[ -x "$__ktp_bin/timeout" ]] && __ktp_tmo=( "$__ktp_bin/timeout" -k 2 20 )
    for __ktp_p in "$@"; do
        [[ "$__ktp_p" =~ ^[1-9][0-9]*$ ]] || continue
        kt_proc_winpid "$__ktp_p" || continue
        __ktp_out+="$__ktp_p=$REPLY "
        # (the forks here are fine: a stop's last resort, never a timed window)
        __ktp_rc=1
        if [[ -x "$__ktp_bin/kill" ]]; then
            "${__ktp_tmo[@]}" "$__ktp_bin/kill" -f -9 "$__ktp_p" </dev/null >/dev/null 2>&1
            __ktp_rc=$?
        fi
        (( __ktp_rc == 0 )) && continue
        # the fallback: taskkill narrowed to that winpid AND that image, both
        # read again now
        kt_proc_winpid "$__ktp_p" || continue
        __ktp_w="$REPLY" __ktp_x=""
        { IFS= read -r __ktp_x < "/proc/$__ktp_p/winexename"; } 2>/dev/null
        __ktp_x="${__ktp_x##*\\}"
        [[ -n "$__ktp_x" ]] || continue
        if [[ -z "$__ktp_tk" ]]; then
            __ktp_tk="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}" 2>/dev/null)/System32/taskkill.exe"
            [[ -x "$__ktp_tk" ]] || continue
        fi
        # MSYS2_ARG_CONV_EXCL: /F and /FI stay switches, never paths
        MSYS2_ARG_CONV_EXCL='*' "${__ktp_tmo[@]}" "$__ktp_tk" /F /FI "PID eq $__ktp_w" /FI "IMAGENAME eq $__ktp_x" </dev/null >/dev/null 2>&1
    done
    REPLY="${__ktp_out% }"
    [[ -n "$REPLY" ]]
}
# kt_proc_bbtimeout — rc 0 when `timeout` is busybox's (one probe, cached;
# _KTP_BBTMO=0/1 preset overrides)
kt_proc_bbtimeout() {
    if [[ -z "${_KTP_BBTMO:-}" ]]; then
        _KTP_BBTMO=0
        [[ "$(timeout --help 2>&1)" == *BusyBox* ]] && _KTP_BBTMO=1
    fi
    (( _KTP_BBTMO ))
}
kt_proc_pid0() {
    local p f out=""
    local -a ord=() a
    kt_proc_init || { REPLY=""; return 0; }
    if [[ "$KT_PROC_BACKEND" == ps ]]; then
        kt_proc_snapshot --cmd _KTP_Q
        for p in "${!_KTP_QCMD[@]}"; do
            [[ "${_KTP_QCMD[$p]%% *}" == "$1" ]] && ord[$p]=1
        done
        for p in "${!ord[@]}"; do out+="$p "; done
        REPLY="${out% }"
        return 0
    fi
    for f in /proc/[0-9]*/cmdline; do
        a=()
        { mapfile -d '' -t a < "$f"; } 2>/dev/null || continue
        [[ "${a[0]:-}" == "$1" ]] || continue
        p="${f#/proc/}"; p="${p%/cmdline}"
        out+="$p "
    done
    REPLY="${out% }"
    return 0
}
declare -gA _KTP_QPP=() _KTP_QPG=() _KTP_QSID=() _KTP_QSTATE=() _KTP_QRAW=() _KTP_QST=() _KTP_QCMD=()
