#!/usr/bin/env bash
# strays.sh — find and stop STRAY processes of the kbool test machinery: test
# runners, test files, fork-storm workers and their children whose owner is
# gone. On 2026-10-16 a killed test/load run left 8 fork-storm workers and a
# whole ktests process tree running for ~5 h (Defender scanned every fork,
# ~50 % CPU); this is the guard that finds such leftovers.
#
# CLI (run it with the SAME bash the tests ran under — see "RUNTIMES"):
#   strays.sh list [OPTS] [--all]   the orphans (default) or every marker
#                       process (--all); columns PID, PPID, AGE (s), ORPHAN
#                       (yes / sub / young / live-session / no), COMMAND
#   strays.sh stop [OPTS]           stop the orphans (ORPHAN=yes) and their
#                       descendants (sub): TERM+CONT once to each tree's root,
#                       a grace (3 s; 5.5 s when a root is a ktests.sh, whose
#                       own group stop needs 5 s), then KILL survivors by pid,
#                       re-sent until they are gone or KT_STRAYS_KILL_MS (ms,
#                       default 10000: SIGKILL delivery lags under load) have
#                       passed, then (cygwin) the Windows side for each
#                       survivor — `kill -f -9`, a narrowed taskkill only if
#                       that fails (launch L2.7-G: a process that acts on no
#                       cygwin signal); rc 0 when none is left, rc 1 + the
#                       list
#   OPTS: --session SID|self (only processes of that session — `self` = this
#   shell's — and the STRICT rule, see below; the master sweep uses it),
#   --since EPOCH (only processes started at/after EPOCH, seconds, a fraction
#   allowed, less max(20 ms, KT_PROC_START_EARLY_MS); a time filter),
#   --match TEXT (only processes whose command line contains TEXT; the tests
#   use a nonce),
#   --older-than MIN (unfiltered rule: a detached tree younger than MIN
#   minutes is ORPHAN=young, default 120 = KT_STRAYS_OLDER_DEFAULT), --width N
#   (COMMAND column, default 100).
#
# LIBRARY (source it; nothing runs on source):
#   kt_strays_scan [OPTS] [SINCE]  KT_STRAYS = the listed pids (ascending),
#                       RESULT = their count; per pid KT_STRAYS_PPID / _AGE /
#                       _FLAG / _CMD / _START (epoch ms). OPTS as the CLI's
#                       (--all, --session, --since, --match, --older-than).
#   kt_strays_stop [OPTS] [SINCE]  stop what kt_strays_scan lists as yes/sub;
#                       KT_STRAYS = what is left; rc 0/1.
#   kt_strays_print [PREFIX]       print the KT_STRAYS rows (a header first).
#   kt_strays_group_settle PGID LABEL  the end-of-run check of a ktests run
#                       group: wait up to 1 s, fork-free, for PGID to be
#                       empty twice in a row (/proc members; its watchdog
#                       leaves by itself); members still there are named in a
#                       [WARN] line and stopped (TERM+CONT, KILL after 3 s).
#                       rc 0 when the group was empty, 1 when something was
#                       left.
#
# THE MARKER RULE. A process belongs to the test machinery when its command
# line (/proc/PID/cmdline, joined with spaces) contains one of: `ktests.sh`,
# `ktest_runner`, `run_test "` (the threaded runner's xargs workers),
# `forkstorm-worker:`, `kt_iso`, `__KT_END_` (the per-file test shell's
# wrapper), the repo root path followed by `/`, `\`, a space or the end
# (/c/…, C:/…, C:\…, /cygdrive/c/… — no case), or an argument `tests.sh` /
# `…/tests.sh` while its working directory is under the repo root. Only such
# a process is listed on its own — except under --session + --since (the
# master sweep): there a DETACHED process needs no marker, its session and
# start time already prove it is the sweep's (a leaked `sleep`, `nc`, `awk`).
# A descendant of a listed orphan is shown as ORPHAN=sub, whatever its
# command line.
#
# THE ORPHAN RULE. `ppid 1` alone means nothing on cygwin: every process
# started by a Windows program (a terminal, an IDE, an agent's tool shell, the
# OTHER runtime's bash) shows ppid 1 too. The difference is the session:
# cygwin starts such a process as the leader of a session of its own
# (sid == pid == pgid), while a process whose cygwin parent died keeps the
# session (and group) it was born in (sid != pid) — measured on both runtimes.
# So: walk up the ppid chain to the topmost process still in /proc (the
# ROOT); the tree is DETACHED when the root's parent is gone — ppid 1 (a
# cygwin parent that exited) or a pid no longer in /proc (a parent killed at
# the WINDOWS level: Task Manager, taskkill /F, an agent's stopped background
# task — cygwin then keeps the dead ppid) — and sid != pid. The caller's own
# tree (same root) is never detached: its chain reaches the caller, alive.
# A live tree is never an orphan, however deep. Not covered: a process that
# called setsid and then lost its parent looks like a root.
#   STRICT (--session): every marker process of a detached tree is an orphan
#   (ORPHAN=yes), whatever its age — the caller names its own session.
#   UNFILTERED (no --session; --since is only a time filter): a detached tree
#   is an orphan only when it is OLDER than --older-than (default 120 min,
#   longer than a full master sweep; a tree whose ROOT is `timeout D` stays
#   young until D + its kill-after + 10 s have passed, however long D is;
#   younger: ORPHAN=young) and its session leader (sid) is gone too (alive:
#   ORPHAN=live-session — a terminal's background job). Neither is ever
#   stopped. The age limit is what protects an agent's live background run:
#   its tool shell (the session leader) exits right after the call, so a
#   bounded `( timeout N … ) &` run IS detached with a dead leader; it is
#   left alone until it is older than the limit (or than N).
# This process, its ancestors and its own descendants are never listed, nor
# the caller's un-started fork for the other side of a pipe (`… | while read`:
# a child of an ancestor with that ancestor's command line whose stdin is the
# pipe this process writes into); the caller's own `( … ) &` jobs are listed.
#
# START TIME. /proc/PID/stat field 22 (starttime, ms since boot on cygwin) +
# boot epoch (EPOCHREALTIME - /proc/uptime) — the same on both runtimes; the
# estimate is never earlier than the real start there. Off cygwin it can be
# (Linux: up to one tick): KT_PROC_START_EARLY_MS (set by ../ktest_proc.sh per
# backend: linux 20, cygwin 0, ps 0 — launch L2.7-K); --since allows
# max(20 ms, KT_PROC_START_EARLY_MS) — the old 20 ms margin is the floor.
#
# RUNTIMES. Git-for-Windows' bash 5.2.37 and MSYS2's bash 5.3.9 are different
# cygwin runtimes with separate process tables: this script sees (and stops)
# only the processes of the runtime it runs in. Run it once under each bash.
#
# PLATFORMS (launch L2.1). The process table comes from ../ktest_proc.sh: on
# cygwin the code below as it always was; on Linux /proc/PID/stat (state,
# ppid, pgrp, session and start time in ONE read; start = boot + ticks/HZ)
# and /proc/PID/cmdline; without /proc (FreeBSD, macOS) one `ps` per table
# (start time to the second; the estimate is the end of that second). Off
# cygwin the ORPHAN RULE is read per session: a process is
# reparented to pid 1 OR TO A SUBREAPER (`systemd --user` on a desktop, a
# container's init) — so the ROOT is the topmost ancestor still in the SAME
# SESSION, and the tree is DETACHED when that root is no session leader
# (sid != pid): its parent died, whoever adopted it. A REAPER among the
# caller's own ancestors (FreeBSD's `timeout` without --foreground adopts all
# below it, in the caller's session) cuts the walk too: a child of an
# ancestor `timeout` that is not on the caller's chain was adopted (GNU
# timeout has that one child only). Without a session column
# (a `ps` that has none, e.g. macOS) a root that leads its process group
# counts as a leader, --session filters nothing and the strict rule needs a
# marker. Kernel threads (session 0) are never listed. With no process table
# at all the CLI prints `strays: UNKNOWN (no process table: WHY)` and exits 3
# — never a blind "none"; the library sets KT_STRAYS_UNKNOWN=WHY.
#
# FORK-LIGHT. The scan reads /proc with bash builtins only (`read`, `mapfile`,
# a builtin `cd` for the tests.sh cwd check): one pass, no fork (the ps
# backend: one fork per table). Waits are
# `read -t` on a pty master of their own (/dev/ptmx: nothing ever arrives),
# no forked `sleep` (FreeBSD has no /dev/ptmx: a FIFO of its own, opened
# read-write and unlinked — kt_proc_napfd; `sleep` only when neither works).

if [[ -n "${_KT_STRAYS_SOURCED:-}" && "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi
_KT_STRAYS_SOURCED=1

if ! declare -F kt_proc_init >/dev/null; then
    __kt_st_src="${BASH_SOURCE[0]}"
    __kt_st_dir="${__kt_st_src%/*}"; [[ "$__kt_st_dir" == "$__kt_st_src" ]] && __kt_st_dir=.
    source "$__kt_st_dir/../ktest_proc.sh"
    unset __kt_st_src __kt_st_dir
fi

declare -ga KT_STRAYS=()
declare -gA KT_STRAYS_PPID=() KT_STRAYS_AGE=() KT_STRAYS_FLAG=() KT_STRAYS_CMD=() KT_STRAYS_START=()
declare -g  _KT_STRAYS_ROOT="" _KT_STRAYS_READY=""
declare -ga _KT_STRAYS_PATHS=()
# the process table of the last _kt_strays_table
declare -gA _KTS_PP=() _KTS_PG=() _KTS_SID=() _KTS_ST=() _KTS_RAW=() _KTS_STATE=() _KTS_CMD=()
declare -g  _KTS_BOOT_MS=0 _KTS_NOW_MS=0 _KTS_NAP_FD="" KT_STRAYS_UNKNOWN=""
declare -ga _KTS_ALIVE=()
# the unfiltered age limit in minutes (--older-than): longer than a full master
# sweep (~35 min measured), so an agent's live background sweep is never hit
declare -g  KT_STRAYS_OLDER_DEFAULT=120

# _kt_strays_init — the repo root (this file's ../..) and its path spellings
_kt_strays_init() {
    [[ -n "$_KT_STRAYS_READY" ]] && return 0
    local src="${BASH_SOURCE[0]}" dir old="$PWD" oldold="${OLDPWD-}" root="" rest d
    dir="${src%/*}"; [[ "$dir" == "$src" ]] && dir=.
    [[ "$dir" == /* ]] || dir="./$dir"
    if builtin cd -P -- "$dir/../.." 2>/dev/null; then
        root="$PWD"
        builtin cd -- "$old" 2>/dev/null
    fi
    OLDPWD="$oldold"
    _KT_STRAYS_ROOT="$root"
    _KT_STRAYS_PATHS=()
    if [[ -n "$root" && "$root" != / ]]; then
        _KT_STRAYS_PATHS+=( "$root" )
        if [[ "$root" =~ ^/([a-zA-Z])(/.*)?$ ]]; then
            d="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
            _KT_STRAYS_PATHS+=( "$d:$rest" "$d:${rest//\//\\}" "/cygdrive/$d$rest" )
        fi
    fi
    _KT_STRAYS_READY=1
}

# _kt_strays_ms TEXT — REPLY = TEXT (seconds, "." or "," fraction) in ms
_kt_strays_ms() {
    local s="${1:-0}" i f
    s="${s/,/.}"
    i="${s%%.*}"; f=""
    [[ "$s" == *.* ]] && f="${s#*.}"
    f="${f}000"; f="${f:0:3}"
    [[ "$i" =~ ^[0-9]+$ ]] || i=0
    [[ "$f" =~ ^[0-9]+$ ]] || f=000
    REPLY=$(( 10#$i * 1000 + 10#$f ))
}

# _kt_strays_dur_ms TEXT — REPLY = a GNU timeout DURATION (N[.N][smhd]) in ms;
# rc 1 when it is no duration (or 0: timeout 0 means no limit)
_kt_strays_dur_ms() {
    local d="$1" u=1000
    [[ "$d" =~ ^([0-9]+)([.][0-9]+)?([smhd]?)$ ]] || return 1
    case "${BASH_REMATCH[3]}" in m) u=60000 ;; h) u=3600000 ;; d) u=86400000 ;; esac
    _kt_strays_ms "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    REPLY=$(( REPLY * u / 1000 ))
    (( REPLY > 0 ))
}

# _kt_strays_timeout_ms CMD — when CMD runs GNU `timeout [OPTS] DURATION …`:
# REPLY = DURATION + its --kill-after in ms, rc 0; else rc 1. The command line
# is split on spaces (no glob); only a command line that starts with timeout
# (or gtimeout: macOS brew coreutils, launch L5.4-9).
_kt_strays_timeout_ms() {
    local c="$1" i=1 ka=0 d=""
    local -a w
    [[ "$c" == "timeout "* || "$c" == *"/timeout "* || "$c" == "timeout.exe "* || "$c" == *"/timeout.exe "* \
       || "$c" == "gtimeout "* || "$c" == *"/gtimeout "* || "$c" == "gtimeout.exe "* || "$c" == *"/gtimeout.exe "* ]] || return 1
    read -r -a w <<< "$c"
    while (( i < ${#w[@]} )); do
        case "${w[i]}" in
            -k|--kill-after) _kt_strays_dur_ms "${w[i+1]:-}" && ka=$REPLY; i=$(( i + 2 )) ;;
            --kill-after=*) _kt_strays_dur_ms "${w[i]#*=}" && ka=$REPLY; i=$(( i + 1 )) ;;
            -k*) _kt_strays_dur_ms "${w[i]#-k}" && ka=$REPLY; i=$(( i + 1 )) ;;
            -s|--signal) i=$(( i + 2 )) ;;
            --) i=$(( i + 1 )); break ;;
            -*) i=$(( i + 1 )) ;;
            *) break ;;
        esac
    done
    _kt_strays_dur_ms "${w[i]:-}" || return 1
    REPLY=$(( REPLY + ka ))
    return 0
}

# _kt_strays_nap_open / _kt_strays_nap SEC / _kt_strays_nap_close — a
# fork-free wait: `read -t` on a pty master nothing writes to (Windows timer
# granularity: a 0.02 s nap takes ~30 ms). Opened per stop/settle and closed
# after, so no child inherits it. Without a pty: a FIFO of its own
# (kt_proc_napfd, FreeBSD), else `sleep`.
_kt_strays_nap_open() {
    [[ -n "$_KTS_NAP_FD" ]] && return 0
    # a pty master; a FIFO of its own where there is no /dev/ptmx (FreeBSD).
    # REPLY is the caller's (_kt_gate_spawn returns the stub pid in it)
    local __kts_r="${REPLY-}"
    kt_proc_napfd; _KTS_NAP_FD="$REPLY"
    REPLY="$__kts_r"
    return 0
}
_kt_strays_nap() {
    if [[ -n "$_KTS_NAP_FD" ]]; then
        read -r -t "$1" -u "$_KTS_NAP_FD" _ 2>/dev/null
    else
        sleep "$1"
    fi
    return 0
}
_kt_strays_nap_close() {
    # (braces: a `2>` on a bare exec would stay on the caller for good — the
    # gate launcher lost its stderr after its first spawn, launch L5.4-K1)
    [[ -n "$_KTS_NAP_FD" ]] && { exec {_KTS_NAP_FD}>&-; } 2>/dev/null
    _KTS_NAP_FD=""
    return 0
}

# _kt_strays_table — read every /proc/PID of this runtime into _KTS_*: ppid,
# pgid, sid and the command line of all (cheap: cygwin answers them from its
# shared process table, ~0.1 ms each). /proc/PID/stat is NOT read here: it
# queries Windows for times and memory (~20 ms a process, ~1 s for 50, and
# far more under load) — _kt_strays_stat reads it for the few candidates.
_kt_strays_table() {
    local f p up c pp pg sd IFS=$' \t\n'
    local -a argv
    KT_STRAYS_UNKNOWN=""
    if ! kt_proc_init || [[ "$KT_PROC_BACKEND" != cygwin ]]; then
        # off cygwin: the whole table at once (state, start, command line
        # included), see PLATFORMS; none: an empty table, KT_STRAYS_UNKNOWN
        kt_proc_snapshot --cmd _KTS_ || KT_STRAYS_UNKNOWN="no process table: $KT_PROC_WHY"
        _KTS_NOW_MS=$KT_PROC_NOW_MS
        return 0
    fi
    _KTS_PP=(); _KTS_PG=(); _KTS_SID=(); _KTS_ST=(); _KTS_RAW=(); _KTS_STATE=(); _KTS_CMD=()
    { read -r up _ < /proc/uptime; } 2>/dev/null || up=0
    _kt_strays_ms "$EPOCHREALTIME"; _KTS_NOW_MS=$REPLY
    _kt_strays_ms "$up"; _KTS_BOOT_MS=$(( _KTS_NOW_MS - REPLY ))
    for f in /proc/[0-9]*; do
        p="${f#/proc/}"
        pp="" pg="" sd=""
        { read -r pp < "$f/ppid"; read -r pg < "$f/pgid"; read -r sd < "$f/sid"; } 2>/dev/null
        [[ -n "$pp" && "$pp" != *[!0-9]* ]] || continue
        argv=()
        { mapfile -d '' -t argv < "$f/cmdline"; } 2>/dev/null
        c="${argv[*]}"
        _KTS_PP[$p]="$pp"
        _KTS_PG[$p]="$pg"
        _KTS_SID[$p]="$sd"
        _KTS_CMD[$p]="$c"
    done
}

# _kt_strays_stat PID — read PID's /proc stat once per table: _KTS_STATE
# (Z = zombie, X = gone), _KTS_RAW (starttime, ms since boot: the identity of
# a pid across scans), _KTS_ST (start, epoch ms). rc 1 when it is gone.
_kt_strays_stat() {
    [[ -n "${_KTS_STATE[$1]+x}" ]] && { [[ "${_KTS_STATE[$1]}" != X ]]; return $?; }
    # off cygwin the table holds every live pid with its stat: not in it = gone
    if [[ "$KT_PROC_BACKEND" != cygwin ]]; then
        _KTS_STATE[$1]=X; _KTS_RAW[$1]=""; _KTS_ST[$1]=0
        return 1
    fi
    local line="" rest c IFS=$' \t\n'
    local -a a
    { IFS= read -r line < "/proc/$1/stat"; } 2>/dev/null
    rest="${line##*) }"
    # state ppid pgid sid tty tpgid flags ... starttime = a[19]
    a=( $rest )
    if [[ "$line" != *") "* ]] || (( ${#a[@]} < 20 )); then
        _KTS_STATE[$1]=X; _KTS_RAW[$1]=""; _KTS_ST[$1]=0
        return 1
    fi
    _KTS_STATE[$1]="${a[0]}"
    _KTS_RAW[$1]="${a[19]}"
    _KTS_ST[$1]=$(( _KTS_BOOT_MS + a[19] ))
    [[ -z "${_KTS_CMD[$1]:-}" ]] && { c="${line#* (}"; _KTS_CMD[$1]="[${c%%) *}]"; }
    return 0
}

# _kt_strays_marker PID — rc 0 when PID's command line carries a marker
_kt_strays_marker() {
    local c="${_KTS_CMD[$1]:-}" m nc=0 old oldold rc=1 d
    case "$c" in
        *ktests.sh*|*ktest_runner*|*'run_test "'*|*forkstorm-worker:*|*kt_iso*|*__KT_END_*) return 0 ;;
    esac
    shopt -q nocasematch && nc=1
    shopt -s nocasematch
    # the repo path as a whole path component: followed by / \ a space or the end
    for m in "${_KT_STRAYS_PATHS[@]}"; do
        if [[ "$c" == *"$m" || "$c" == *"$m"/* || "$c" == *"$m"\\* || "$c" == *"$m "* ]]; then
            rc=0; break
        fi
    done
    # an argument tests.sh / …/tests.sh run from inside the repo
    if (( rc != 0 )) && [[ -n "$_KT_STRAYS_ROOT" ]] \
       && [[ "$c" == tests.sh || "$c" == tests.sh\ * || "$c" == *\ tests.sh || "$c" == *\ tests.sh\ * \
             || "$c" == */tests.sh || "$c" == */tests.sh\ * ]]; then
        if [[ "$KT_PROC_BACKEND" != cygwin ]]; then
            kt_proc_cwd "$1"; d="$REPLY"
            [[ -n "$d" ]] && [[ "$d" == "$_KT_STRAYS_ROOT" || "$d" == "$_KT_STRAYS_ROOT"/* ]] && rc=0
        else
        old="$PWD"; oldold="${OLDPWD-}"
        if builtin cd -P -- "/proc/$1/cwd" 2>/dev/null; then
            d="$PWD"
            builtin cd -- "$old" 2>/dev/null
            [[ "$d" == "$_KT_STRAYS_ROOT" || "$d" == "$_KT_STRAYS_ROOT"/* ]] && rc=0
        fi
        OLDPWD="$oldold"
        fi
    fi
    (( nc )) || shopt -u nocasematch
    return $rc
}

# _kt_strays_self_chain — mark in the CALLER's assoc `ex` this shell ($BASHPID,
# $$), its parent ($PPID) and every ancestor: the table's ppid, and where the
# table has no entry a direct read of /proc/PID/ppid (a /proc read that failed
# while the table was built must not let an ancestor through — a tool shell
# was once reported by its own `strays.sh list --all`).
_kt_strays_self_chain() {
    local s p n pp
    for s in "$BASHPID" "$$" "$PPID"; do
        p="$s"; n=0
        while [[ "$p" =~ ^[0-9]+$ ]] && (( p > 1 && n++ < 500 )); do
            ex[$p]=1
            pp="${_KTS_PP[$p]:-}"
            if [[ -z "$pp" ]]; then
                if [[ "$KT_PROC_BACKEND" == cygwin ]]; then
                    { read -r pp < "/proc/$p/ppid"; } 2>/dev/null || pp=""
                else
                    kt_proc_ppid "$p"; pp="$REPLY"
                fi
            fi
            [[ -n "$pp" ]] || break
            p="$pp"
        done
    done
}

# kt_strays_scan [--all] [--session SID|self] [--since EPOCH] [--match TEXT]
#                [--older-than MIN] [SINCE]
kt_strays_scan() {
    local all=0 sess="" match="" since="" since_ms=-1 older="$KT_STRAYS_OLDER_DEFAULT"
    while (( $# > 0 )); do
        case "$1" in
            --all) all=1; shift ;;
            --session) sess="${2:-}"; shift 2 ;;
            --session=*) sess="${1#*=}"; shift ;;
            --match) match="${2:-}"; shift 2 ;;
            --match=*) match="${1#*=}"; shift ;;
            --since) since="${2:-}"; shift 2 ;;
            --since=*) since="${1#*=}"; shift ;;
            --older-than) older="${2:-}"; shift 2 ;;
            --older-than=*) older="${1#*=}"; shift ;;
            *) since="$1"; shift ;;
        esac
    done
    [[ "$older" =~ ^[0-9]+$ ]] || older="$KT_STRAYS_OLDER_DEFAULT"
    _kt_strays_init
    _kt_strays_table
    if [[ -n "$since" ]]; then
        # the tolerance: KT_PROC_START_EARLY_MS, at least the old 20 ms margin
        _kt_strays_ms "$since"; since_ms=${KT_PROC_START_EARLY_MS:-0}
        (( since_ms < 20 )) && since_ms=20
        since_ms=$(( REPLY - since_ms ))
    fi
    # off cygwin (PLATFORMS): roots per session (sscope); no session column (nosid)
    local sscope=0 nosid=0 sarg="$sess"
    if [[ "$KT_PROC_BACKEND" != cygwin ]]; then
        if (( KT_PROC_HAS_SID )); then sscope=1; else nosid=1; fi
    fi
    if [[ "$sess" == self ]]; then
        sess="${_KTS_SID[$BASHPID]:-${_KTS_SID[$$]:-}}"
    fi
    KT_STRAYS=(); KT_STRAYS_PPID=(); KT_STRAYS_AGE=(); KT_STRAYS_FLAG=(); KT_STRAYS_CMD=(); KT_STRAYS_START=()

    local p q pp n mine s r
    local -A ex=() root=() kids=() take=() tclass=()
    # this process and its ancestors
    _kt_strays_self_chain
    # roots (topmost process still in /proc; off cygwin: in the same session);
    # own descendants; children lists
    for p in "${!_KTS_PP[@]}"; do
        q="$p"; mine=0; n=0; r=""
        while :; do
            [[ "$q" == "$BASHPID" || "$q" == "$$" ]] && mine=1
            pp="${_KTS_PP[$q]}"
            # ppid 0 / its own pid: init and the kernel processes (FreeBSD ps lists
            # pid 0 with ppid 0 — the walk would spin to 500; L2.1 review)
            [[ "$pp" == 1 || "$pp" == 0 || "$pp" == "$q" || -z "${_KTS_PP[$pp]+x}" ]] && break
            if (( sscope )) && [[ -z "$r" && "${_KTS_SID[$pp]}" != "${_KTS_SID[$q]}" ]]; then r="$q"; fi
            # a REAPER among this shell's ancestors adopted q: FreeBSD's
            # `timeout` (without --foreground) is the reaper of everything
            # below it, in the caller's own session. Its one real child is on
            # the caller's chain; any other child of it was adopted (also safe
            # for GNU timeout, which has only that one child)
            if (( sscope )) && [[ -z "$r" && -n "${ex[$pp]+x}" && -z "${ex[$q]+x}" ]] \
               && [[ "${_KTS_CMD[$pp]}" == timeout\ * || "${_KTS_CMD[$pp]}" == */timeout\ * \
                     || "${_KTS_CMD[$pp]}" == gtimeout\ * || "${_KTS_CMD[$pp]}" == */gtimeout\ * ]]; then r="$q"; fi
            q="$pp"
            (( ++n > 500 )) && break
        done
        root[$p]="${r:-$q}"
        (( mine )) && ex[$p]=1
        pp="${_KTS_PP[$p]}"
        # DT12: the caller's un-started fork for the other side of a pipe
        # (`strays.sh list --all | while …`): a child of the self chain that
        # still carries its parent's command line AND reads this process's
        # stdout — its fd 0 is the same pipe as our fd 1 (`-p` + `-ef`: stat
        # calls, no fork; cygwin shows a pipe as pipe:[N] with its own inode).
        # The caller's own `( … ) &` / `{ …; } &` job has the same command
        # line but not that stdin, so it is still listed (review F4).
        [[ -n "${ex[$pp]+x}" && -n "${_KTS_CMD[$p]:-}" && "${_KTS_CMD[$p]}" == "${_KTS_CMD[$pp]:-}" \
           && -p "/proc/$p/fd/0" && "/proc/$p/fd/0" -ef "/proc/$BASHPID/fd/1" ]] && ex[$p]=1
        # off cygwin the same check through kt_proc_samepipe (no /proc: fstat)
        [[ "$KT_PROC_BACKEND" != cygwin && -z "${ex[$p]+x}" && -n "${ex[$pp]+x}" && -n "${_KTS_CMD[$p]:-}" \
           && "${_KTS_CMD[$p]}" == "${_KTS_CMD[$pp]:-}" ]] && kt_proc_samepipe "$p" 0 "$BASHPID" 1 && ex[$p]=1
        [[ -n "${_KTS_PP[$pp]+x}" ]] && kids[$pp]+=" $p"
    done
    # each tree's class: no (live) / yes / young / live-session (see the header)
    local age lim strict=0 myroot="${root[$BASHPID]:-${root[$$]:-}}" cls lead det
    [[ -n "$sess" ]] && strict=1
    (( nosid )) && [[ -n "$sarg" ]] && strict=1
    _kt_strays_tclass() {   # $1 = a root -> REPLY = its class (memoised)
        local r="$1"
        if [[ -n "${tclass[$r]+x}" ]]; then REPLY="${tclass[$r]}"; return 0; fi
        REPLY=no
        det=0
        if (( sscope )); then
            # its parent died (the root's parent is 1, gone or of another
            # session: init or a subreaper adopted it) and it leads no
            # session; session 0 = a kernel thread
            [[ "$r" != "$myroot" && "${_KTS_SID[$r]}" != "$r" && "${_KTS_SID[$r]}" != 0 ]] && det=1
        elif (( nosid )); then
            [[ "$r" != "$myroot" && "${_KTS_PG[$r]}" != "$r" ]] \
               && [[ "${_KTS_PP[$r]}" == 1 || -z "${_KTS_PP[${_KTS_PP[$r]}]+x}" ]] && det=1
        elif [[ "$r" != "$myroot" && "${_KTS_SID[$r]}" != "$r" ]] \
           && [[ "${_KTS_PP[$r]}" == 1 || -z "${_KTS_PP[${_KTS_PP[$r]}]+x}" ]]; then
            det=1
        fi
        if (( det )); then
            REPLY=yes
            if (( ! strict )); then
                lead="${_KTS_SID[$r]}"
                if [[ -n "$lead" && -n "${_KTS_PP[$lead]+x}" ]]; then
                    REPLY=live-session
                elif _kt_strays_stat "$r"; then
                    # young: newer than --older-than, or a `timeout D` root
                    # whose D (+ its kill-after, + 10 s) has not elapsed
                    age=$(( _KTS_NOW_MS - _KTS_ST[$r] ))
                    lim=$(( older * 60000 ))
                    if _kt_strays_timeout_ms "${_KTS_CMD[$r]}" && (( REPLY + 10000 > lim )); then
                        lim=$(( REPLY + 10000 ))
                    fi
                    REPLY=yes
                    (( age < lim )) && REPLY=young
                fi
            fi
        fi
        tclass[$r]="$REPLY"
    }
    local -a stack=()
    for p in "${!_KTS_PP[@]}"; do
        [[ -n "${ex[$p]+x}" ]] && continue
        [[ -z "$sess" || "${_KTS_SID[$p]}" == "$sess" ]] || continue
        [[ -z "$match" || "${_KTS_CMD[$p]}" == *"$match"* ]] || continue
        _kt_strays_tclass "${root[$p]}"; cls="$REPLY"
        # the marker rule; the sweep (--session + --since) takes any detached process
        if ! (( strict && since_ms >= 0 )) || [[ "$cls" == no ]] || (( nosid )); then
            _kt_strays_marker "$p" || continue
        fi
        [[ "$cls" == yes ]] || (( all )) || continue
        _kt_strays_stat "$p" && [[ "${_KTS_STATE[$p]}" != Z ]] || continue
        (( since_ms < 0 || _KTS_ST[$p] >= since_ms )) || continue
        take[$p]="$cls"
        [[ "$cls" == yes ]] && stack+=( "$p" )
    done
    unset -f _kt_strays_tclass
    # the descendants of the orphans, whatever their command line
    while (( ${#stack[@]} > 0 )); do
        p="${stack[-1]}"; unset 'stack[-1]'
        for q in ${kids[$p]:-}; do
            [[ -n "${ex[$q]+x}" ]] && continue
            _kt_strays_stat "$q" && [[ "${_KTS_STATE[$q]}" != Z ]] || continue
            [[ "${take[$q]:-}" == yes || "${take[$q]:-}" == sub ]] && continue
            take[$q]=sub
            stack+=( "$q" )
        done
    done
    local -a ord=()
    for p in "${!take[@]}"; do ord[$p]=1; done
    for p in "${!ord[@]}"; do
        KT_STRAYS+=( "$p" )
        KT_STRAYS_PPID[$p]="${_KTS_PP[$p]}"
        KT_STRAYS_START[$p]="${_KTS_ST[$p]}"
        n=$(( (_KTS_NOW_MS - _KTS_ST[$p]) / 1000 )); (( n < 0 )) && n=0
        KT_STRAYS_AGE[$p]=$n
        KT_STRAYS_FLAG[$p]="${take[$p]}"
        KT_STRAYS_CMD[$p]="${_KTS_CMD[$p]}"
    done
    RESULT=${#KT_STRAYS[@]}
    return 0
}

# kt_strays_print [PREFIX] — the KT_STRAYS rows; KT_STRAYS_WIDTH = COMMAND width
kt_strays_print() {
    local pre="${1:-}" p c w="${KT_STRAYS_WIDTH:-100}"
    [[ "$w" =~ ^[0-9]+$ ]] && (( w >= 8 )) || w=100
    printf '%s%7s %7s %7s  %-12s  %s\n' "$pre" PID PPID AGE ORPHAN COMMAND
    for p in "${KT_STRAYS[@]}"; do
        c="${KT_STRAYS_CMD[$p]//$'\n'/ }"
        c="${c//$'\t'/ }"
        (( ${#c} > w )) && c="${c:0:w-3}..."
        printf '%s%7s %7s %7s  %-12s  %s\n' "$pre" "$p" "${KT_STRAYS_PPID[$p]}" \
            "${KT_STRAYS_AGE[$p]}" "${KT_STRAYS_FLAG[$p]}" "$c"
    done
}

# _kt_strays_signal SIG [PID...] — send SIG to the given pids (default: every
# target in __kts_tgt, an assoc pid -> raw /proc starttime of the caller) that
# are alive with an unchanged starttime (a reused pid is never signalled);
# RESULT = how many were alive, _KTS_ALIVE = those pids. Needs a fresh
# _kt_strays_table.
_kt_strays_signal() {
    local sig="$1" p n=0
    shift
    _KTS_ALIVE=()
    (( $# > 0 )) || set -- "${!__kts_tgt[@]}"
    for p in "$@"; do
        [[ -n "${__kts_tgt[$p]+x}" ]] || continue
        _kt_strays_stat "$p" || continue
        [[ "${_KTS_RAW[$p]}" == "${__kts_tgt[$p]}" ]] || continue
        [[ "${_KTS_STATE[$p]}" == Z ]] && continue
        n=$(( n + 1 )); _KTS_ALIVE+=( "$p" )
        [[ -n "$sig" ]] && kill "-$sig" "$p" 2>/dev/null
    done
    RESULT=$n
}

# _kt_strays_adopt — add to __kts_tgt the live children of live targets (a
# fork made while stopping; a test shell's next child), transitively; never
# this shell or its chain (kt_strays_scan's exclusion is rebuilt the same way)
_kt_strays_adopt() {
    local p pp grown=1 s n
    local -A ex=()
    _kt_strays_self_chain
    while (( grown )); do
        grown=0
        for p in "${!_KTS_PP[@]}"; do
            [[ -n "${__kts_tgt[$p]+x}" || -n "${ex[$p]+x}" ]] && continue
            pp="${_KTS_PP[$p]}"
            [[ -n "${__kts_tgt[$pp]+x}" ]] || continue
            _kt_strays_stat "$pp" && _kt_strays_stat "$p" || continue
            if [[ "${_KTS_RAW[$pp]}" == "${__kts_tgt[$pp]}" ]]; then
                __kts_tgt[$p]="${_KTS_RAW[$p]}"; grown=1
            fi
        done
    done
}

# kt_strays_stop [OPTS] [SINCE] — stop what kt_strays_scan lists as yes/sub:
# TERM+CONT ONCE to each tree's ROOT (a target whose parent is no target: an
# orphaned ktests.sh then stops its own group, a test shell runs its cleanup
# — a TERM re-sent every 0.1 s cut those short), a fork-free grace until all
# are gone (3 s; 5.5 s when a root is a ktests.sh), then KILL by pid what
# survives (and what was forked meanwhile), re-sent until all are gone or
# KT_STRAYS_KILL_MS (default 10000) have passed — SIGKILL delivery can lag
# seconds under load; on cygwin the survivors' Windows processes then get
# the Windows-side kill (kt_proc_winkill, launch L2.7-G); reap. rc 0 when none is left; else
# rc 1, KT_STRAYS = what is left.
kt_strays_stop() {
    local -a args=( "$@" ) roots=()
    local -A __kts_tgt=()
    local p t0 kms grace=3000
    kt_strays_scan "${args[@]}"
    for p in "${KT_STRAYS[@]}"; do
        [[ "${KT_STRAYS_FLAG[$p]}" == yes || "${KT_STRAYS_FLAG[$p]}" == sub ]] || continue
        __kts_tgt[$p]="${_KTS_RAW[$p]}"
    done
    (( ${#__kts_tgt[@]} == 0 )) && { RESULT=0; KT_STRAYS=(); return 0; }
    for p in "${!__kts_tgt[@]}"; do
        [[ -n "${__kts_tgt[${_KTS_PP[$p]}]+x}" ]] && continue
        roots+=( "$p" )
        [[ "${_KTS_CMD[$p]}" == *ktests.sh* ]] && grace=5500
    done
    _kt_strays_nap_open
    _kt_strays_signal TERM "${roots[@]}"
    _kt_strays_signal CONT "${roots[@]}"
    _kt_strays_ms "$EPOCHREALTIME"; t0=$REPLY
    while :; do
        _kt_strays_nap 0.1
        _kt_strays_table
        _kt_strays_adopt
        _kt_strays_signal ""
        (( RESULT == 0 )) && break
        (( _KTS_NOW_MS - t0 >= grace )) && break
    done
    # KILL by wall clock, not by a round count (gate G2, found in G1): under
    # full-sweep load SIGKILL DELIVERY lags — a target killed 20x over 2 s was
    # still alive (its signal thread was not scheduled), and a false "LEFT"
    # makes the caller's suite (a gate cell) STRAY. Re-send to the
    # identity-checked targets until they are gone or KT_STRAYS_KILL_MS (ms,
    # default 10000) have passed; 0.1 s apart for the first 2 s, then 0.25 s.
    kms="${KT_STRAYS_KILL_MS:-10000}"
    [[ "$kms" =~ ^[0-9]+$ ]] || kms=10000
    _kt_strays_ms "$EPOCHREALTIME"; t0=$REPLY
    while :; do
        _kt_strays_table
        _kt_strays_adopt
        _kt_strays_signal KILL
        (( RESULT == 0 )) && break
        (( _KTS_NOW_MS - t0 >= kms )) && break
        if (( _KTS_NOW_MS - t0 < 2000 )); then _kt_strays_nap 0.1; else _kt_strays_nap 0.25; fi
    done
    # the last step (launch L2.7-G), cygwin only: a target alive after
    # KT_STRAYS_KILL_MS of SIGKILLs does not act on cygwin signals at all (two
    # runners on 2026-10-22, wedged in the Git runtime for over an hour) — its
    # Windows process gets the kill (kt_proc_winkill: `kill -f -9`, else a
    # narrowed taskkill; the targets were identity-checked just above), then
    # up to 5 s for it to go
    if (( RESULT > 0 )) && kt_proc_winkill "${_KTS_ALIVE[@]}"; then
        for (( t0 = 0; t0 < 20; t0++ )); do
            _kt_strays_nap 0.25
            _kt_strays_table
            _kt_strays_signal ""
            (( RESULT == 0 )) && break
        done
    fi
    _kt_strays_nap_close
    # reap our own children (a no-op for an orphan: its parent is gone)
    for p in "${!__kts_tgt[@]}"; do wait "$p" 2>/dev/null || :; done
    kt_strays_scan "${args[@]}"
    local -a left=()
    for p in "${KT_STRAYS[@]}"; do
        [[ "${KT_STRAYS_FLAG[$p]}" == yes || "${KT_STRAYS_FLAG[$p]}" == sub ]] && left+=( "$p" )
    done
    _kt_strays_signal ""
    # what is left: the scan's yes/sub rows plus a surviving target
    for p in "${!__kts_tgt[@]}"; do
        [[ "${_KTS_RAW[$p]:-}" == "${__kts_tgt[$p]}" && "${_KTS_STATE[$p]:-}" != Z ]] || continue
        [[ -n "${KT_STRAYS_FLAG[$p]+x}" ]] && continue
        left+=( "$p" ); KT_STRAYS_PPID[$p]="${_KTS_PP[$p]}"; KT_STRAYS_FLAG[$p]=sub
        KT_STRAYS_AGE[$p]=$(( (_KTS_NOW_MS - _KTS_ST[$p]) / 1000 ))
        KT_STRAYS_CMD[$p]="${_KTS_CMD[$p]}"; KT_STRAYS_START[$p]="${_KTS_ST[$p]}"
    done
    KT_STRAYS=( "${left[@]}" )
    RESULT=${#KT_STRAYS[@]}
    (( RESULT == 0 ))
}

# _kt_strays_members PGID — REPLY = the live pids of process group PGID (not
# this shell): kt_runner_group_members when the runner is loaded, else /proc
_kt_strays_members() {
    local p out=""
    if declare -F kt_runner_group_members >/dev/null; then
        kt_runner_group_members "$1"; out="$REPLY"
    else
        _kt_strays_table
        for p in "${!_KTS_PG[@]}"; do
            [[ "${_KTS_PG[$p]}" == "$1" ]] || continue
            _kt_strays_stat "$p" && [[ "${_KTS_STATE[$p]}" != Z ]] && out+="$p "
        done
    fi
    REPLY=""
    for p in $out; do [[ "$p" == "$BASHPID" || "$p" == "$$" ]] || REPLY+="$p "; done
    REPLY="${REPLY% }"
}

# kt_strays_group_settle PGID LABEL — the end of a run whose group PGID must be
# empty now. rc 0: it is; rc 1: members were left (named, then stopped).
# Clean path (P3b review round 2, F10): the group's watchdog leaves ~15 ms
# after kt_runner_group_close; `kill -0 -- -PGID` (cheap, no /proc stat) is
# polled until it says empty, then the /proc members (kt_runner_group_members)
# must be empty twice, one short fork-free nap apart (an exec'ing member can
# be missing from one look). Measured, clean 1/2-file runs, 5.2: ~30-50 ms,
# no fork (was 77-140 ms + 1-2 forked sleeps).
kt_strays_group_settle() {
    local g="${1:-}" label="${2:-run}" i p c n empty=0 t0
    local -A __kts_tgt=()
    local -a names=()
    [[ -n "$g" && "$g" != *[!0-9]* ]] || return 0
    _kt_strays_nap_open
    _kt_strays_ms "$EPOCHREALTIME"; t0=$REPLY
    while :; do
        if kill -0 -- "-$g" 2>/dev/null; then
            empty=0
        else
            _kt_strays_members "$g"
            if [[ -z "$REPLY" ]]; then
                (( ++empty >= 2 )) && { _kt_strays_nap_close; return 0; }
            else
                empty=0
            fi
        fi
        _kt_strays_ms "$EPOCHREALTIME"
        (( REPLY - t0 >= 1000 )) && break
        _kt_strays_nap 0.005
    done
    _kt_strays_init
    _kt_strays_table
    if [[ "$KT_PROC_BACKEND" != cygwin ]]; then
        # off cygwin the members from THIS table: a second snapshot (the
        # runner's) could name a member forked meanwhile that _kt_strays_stat
        # would read as gone (L2.1 review)
        REPLY=""
        for p in "${!_KTS_PG[@]}"; do
            [[ "${_KTS_PG[$p]}" == "$g" && "$p" != "$BASHPID" && "$p" != "$$" ]] && REPLY+="$p "
        done
    else
        _kt_strays_members "$g"
    fi
    for p in $REPLY; do
        _kt_strays_stat "$p" && [[ "${_KTS_STATE[$p]}" != Z ]] || continue
        __kts_tgt[$p]="${_KTS_RAW[$p]}"
        c="${_KTS_CMD[$p]//$'\n'/ }"; (( ${#c} > 80 )) && c="${c:0:77}..."
        names+=( "$p ($c)" )
    done
    n=${#names[@]}
    if (( n == 0 )); then _kt_strays_nap_close; return 0; fi
    printf '[WARN] %s: %s process(es) of the run group %s left after the run, stopping: %s\n' \
        "$label" "$n" "$g" "${names[*]}"
    _kt_strays_nap_open
    kill -TERM -- "-$g" 2>/dev/null
    kill -CONT -- "-$g" 2>/dev/null
    _kt_strays_ms "$EPOCHREALTIME"; t0=$REPLY
    for (( i = 0; i < 100; i++ )); do
        _kt_strays_members "$g"
        [[ -z "$REPLY" ]] && break
        _kt_strays_ms "$EPOCHREALTIME"
        if (( REPLY - t0 >= 3000 )); then
            kill -KILL -- "-$g" 2>/dev/null
            _kt_strays_table
            _kt_strays_signal KILL
        fi
        _kt_strays_nap 0.1
    done
    _kt_strays_nap_close
    for p in "${!__kts_tgt[@]}"; do wait "$p" 2>/dev/null || :; done
    return 1
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _st_cmd="${1:-}"; shift || :
    _st_opts=()
    while (( $# > 0 )); do
        case "$1" in
            --since|--session|--match|--older-than) _st_opts+=( "$1" "${2:?$1 needs a value}" ); shift 2 ;;
            --all) _st_opts+=( --all ); shift ;;
            --width) KT_STRAYS_WIDTH="${2:?--width needs a number}"; shift 2 ;;
            --width=*) KT_STRAYS_WIDTH="${1#*=}"; shift ;;
            --since=*|--session=*|--match=*|--older-than=*) _st_opts+=( "$1" ); shift ;;
            *) printf 'strays: unknown argument "%s"\n' "$1" >&2; exit 2 ;;
        esac
    done
    if [[ -n "${KT_STRAYS_WIDTH:-}" && ! "$KT_STRAYS_WIDTH" =~ ^[0-9]+$ ]]; then
        printf 'strays: --width needs a number, got "%s"\n' "$KT_STRAYS_WIDTH" >&2
        exit 2
    fi
    for (( _st_i = 0; _st_i < ${#_st_opts[@]}; _st_i++ )); do
        if [[ "${_st_opts[_st_i]}" == --older-than && ! "${_st_opts[_st_i+1]}" =~ ^[0-9]+$ ]]; then
            printf 'strays: --older-than needs whole minutes, got "%s"\n' "${_st_opts[_st_i+1]}" >&2
            exit 2
        fi
    done
    # the runtime = the source of the `/` mount (C:/bin/Git vs C:/bin/msys64)
    _st_rt="?"
    if [[ -r /proc/mounts ]]; then
        while read -r _st_a _st_b _; do
            [[ "$_st_b" == / ]] && { _st_rt="$_st_a"; break; }
        done < /proc/mounts
    fi
    # off cygwin the runtime id may be "none" (no /proc/mounts): name the
    # process table instead
    if kt_proc_init && [[ "$KT_PROC_BACKEND" != cygwin && "$_st_rt" == "?" ]]; then
        _st_rt="${OSTYPE:-?}, process table $KT_PROC_BACKEND"
    fi
    case "$_st_cmd" in
        list|stop)
            # never a blind "none" (L2.1): without a process table say so, rc 3
            if ! kt_proc_init; then
                printf 'strays: UNKNOWN (no process table: %s; bash %s)\n' "$KT_PROC_WHY" "$BASH_VERSION"
                exit 3
            fi ;;
    esac
    case "$_st_cmd" in
        list)
            kt_strays_scan "${_st_opts[@]}"
            if (( RESULT == 0 )); then
                printf 'strays: none (bash %s, runtime %s)\n' "$BASH_VERSION" "$_st_rt"
            else
                kt_strays_print
                printf 'strays: %s process(es) (bash %s, runtime %s)\n' "$RESULT" "$BASH_VERSION" "$_st_rt"
            fi
            ;;
        stop)
            for _st_o in "${_st_opts[@]}"; do
                [[ "$_st_o" == --all ]] && { printf 'strays: stop takes no --all (it stops orphans only)\n' >&2; exit 2; }
            done
            kt_strays_scan --all "${_st_opts[@]}"
            _st_n=0 _st_keep=0
            for _st_p in "${KT_STRAYS[@]}"; do
                case "${KT_STRAYS_FLAG[$_st_p]}" in
                    yes|sub) _st_n=$(( _st_n + 1 )) ;;
                    young|live-session) _st_keep=$(( _st_keep + 1 )) ;;
                esac
            done
            if (( _st_keep > 0 )); then
                printf 'strays: %s detached process(es) left alone (young: newer than --older-than; live-session: its session leader lives) — `list --all` shows them\n' "$_st_keep"
            fi
            if (( _st_n == 0 )); then
                printf 'strays: none to stop\n'
                exit 0
            fi
            kt_strays_scan "${_st_opts[@]}"
            printf 'strays: stopping %s process(es):\n' "$RESULT"
            kt_strays_print '  '
            if kt_strays_stop "${_st_opts[@]}"; then
                printf 'strays: stopped, none left\n'
            else
                printf 'strays: %s process(es) LEFT:\n' "$RESULT"
                kt_strays_print '  '
                exit 1
            fi
            ;;
        *)
            sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            [[ "$_st_cmd" == -h || "$_st_cmd" == --help ]] && exit 0
            exit 2
            ;;
    esac
fi
