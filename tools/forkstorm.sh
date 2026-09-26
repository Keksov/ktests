#!/bin/bash
# forkstorm.sh — a FORK storm: N sibling bash processes that fork in a tight
# loop (`x=$(:)`), the load that makes timing assertions flaky on MSYS/cygwin.
#
# WHY A FORK STORM AND NOT CPU BURNERS. On this platform a fork of a bash costs
# ~15 ms at p50 when the machine is idle, but 2-9 % of forks take ~280 ms, and
# with 8 siblings forking concurrently — exactly what the threaded ktests runner
# produces, 8 test files each forking `$( )`s — p90 is ~290 ms on bash 5.2.37
# and p50 ~810 ms / p99 ~2.4 s on bash 5.3.9. Pure CPU load does not reproduce
# that; concurrent forking does. A timing assertion with a fork inside its
# timed window (a `$( )`, an external command, a pipe) is therefore only as
# stable as the slowest fork, and this tool is the load that shows it.
#
# CLI (run it with the SAME bash the tests will run under — see "RUNTIMES"):
#   forkstorm.sh start N        start N workers, print their pids, return
#   forkstorm.sh stop           stop the workers of the last `start`
#   forkstorm.sh status         alive workers of the last `start`, and every
#                               storm worker this runtime can see
#   forkstorm.sh self-check [N] idle fork latency, then under an N-worker storm
#                               (default 8), then stop and prove nothing leaked
#   Options for start/stop/status: --state FILE (default: ktests/.tmp/forkstorm.pids)
#
# LIBRARY (source it; nothing runs on source):
#   kt_storm_start N    start N workers; KT_STORM_PIDS / KT_STORM_TAG are set.
#                       rc 1 (and nothing started) when a storm is already
#                       running anywhere in this runtime, unless
#                       KT_STORM_ALLOW_OVERLAP=1 — two storms never overlap by
#                       accident.
#   kt_storm_stop       TERM, then KILL whatever survives 5 s; reap; sweep any
#                       in-flight worker child; rc 0 only when nothing of this
#                       storm is left.
#   kt_storm_alive      RESULT = the number of this storm's pids still alive
#   kt_storm_scan [TAG] RESULT = the number of storm processes visible in
#                       /proc (only TAG's when given; forked `$( )` children
#                       count too, they carry the worker's command line)
#
# Tunables (environment):
#   KT_STORM_FUNCS=1000     ballast functions each worker defines (a test shell
#                           has hundreds; measured: shell size moves the fork
#                           cost by <15 %, the storm is what matters)
#   KT_STORM_BALLAST=FILE   additionally `source` FILE in every worker (e.g. a
#                           kcl unit), to fork a shell shaped like a test file
#   KT_STORM_HEARTBEAT=DIR  each worker touches DIR/<its pid> after its FIRST
#                           fork — proof that the storm is actually forking
#
# RUNTIMES. Git-for-Windows' bash 5.2.37 and MSYS2's bash 5.3.9 are different
# cygwin runtimes with separate process tables: a worker started by one cannot
# be seen in the other's /proc nor signalled reliably from it. Start, stop and
# measure with ONE bash. timing_check.sh re-executes itself under its --bash
# for exactly that reason.
#
# Every worker's $0 is "forkstorm-worker:<tag>", so its /proc/<pid>/cmdline —
# and that of every `$( )` child it forks — names the storm it belongs to; that
# is what the leak checks look for.

if [[ -n "${_KT_FORKSTORM_SOURCED:-}" && "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi
_KT_FORKSTORM_SOURCED=1

declare -ga KT_STORM_PIDS=()
declare -g  KT_STORM_TAG=""

# The worker body. It must not contain the marker text itself (only $0 does),
# so a process whose command line merely MENTIONS this script is never counted.
# shellcheck disable=SC2016
# Arguments: $0 = marker, $1 = ballast function count, $2 = ballast file or '',
# $3 = heartbeat dir or ''. Passed as ARGUMENTS, not through the environment, so
# the tunables work whether or not the caller exported them.
_KT_STORM_WORKER='
__fs_n="${1:-1000}"
for (( __fs_i = 0; __fs_i < __fs_n; __fs_i++ )); do
    eval "__fs_f${__fs_i}() { local a=\$1 b=\$2; printf %s \"\$a\$b\"; }"
done
if [[ -n "${2:-}" ]]; then source "$2" >/dev/null 2>&1 || :; fi
trap "exit 0" TERM INT HUP
x=$(:)
if [[ -n "${3:-}" ]]; then : > "$3/$BASHPID"; fi
while :; do x=$(:); done
'

_kt_storm_marker() { printf -v REPLY 'forkstorm-worker:%s' "$1"; }

# kt_storm_scan [TAG] -> RESULT = storm processes visible in /proc
kt_storm_scan() {
    local tag="${1:-}" f n=0
    local -a argv
    for f in /proc/[0-9]*/cmdline; do
        argv=()
        { mapfile -d '' -t argv < "$f"; } 2>/dev/null || continue
        # bash -c SCRIPT NAME ... -> the marker is argv[3]
        (( ${#argv[@]} >= 4 )) || continue
        if [[ -n "$tag" ]]; then
            [[ "${argv[3]}" == "forkstorm-worker:$tag" ]] && n=$(( n + 1 ))
        else
            [[ "${argv[3]}" == "forkstorm-worker:"* ]] && n=$(( n + 1 ))
        fi
    done
    RESULT=$n
}

# _kt_storm_scan_pids TAG -> KT_STORM_FOUND=( pids of TAG's processes in /proc )
_kt_storm_scan_pids() {
    local want="forkstorm-worker:$1" f p
    local -a argv
    KT_STORM_FOUND=()
    for f in /proc/[0-9]*/cmdline; do
        argv=()
        { mapfile -d '' -t argv < "$f"; } 2>/dev/null || continue
        if (( ${#argv[@]} >= 4 )) && [[ "${argv[3]}" == "$want" ]]; then
            p="${f#/proc/}"; p="${p%/cmdline}"
            KT_STORM_FOUND+=( "$p" )
        fi
    done
}

kt_storm_alive() {
    local p n=0
    for p in "${KT_STORM_PIDS[@]}"; do
        if kill -0 "$p" 2>/dev/null; then n=$(( n + 1 )); fi
    done
    RESULT=$n
}

# kt_storm_start N -> rc 0, KT_STORM_PIDS / KT_STORM_TAG set
kt_storm_start() {
    local n="${1:-}" i
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then
        printf 'kt_storm_start: N must be a non-negative integer, got "%s"\n' "$n" >&2
        return 2
    fi
    if (( ${#KT_STORM_PIDS[@]} > 0 )); then
        printf 'kt_storm_start: this shell already runs storm %s — stop it first\n' "$KT_STORM_TAG" >&2
        return 1
    fi
    if [[ "${KT_STORM_ALLOW_OVERLAP:-0}" != "1" ]]; then
        kt_storm_scan
        if (( RESULT > 0 )); then
            printf 'kt_storm_start: %s storm process(es) already running in this runtime — refusing to overlap (KT_STORM_ALLOW_OVERLAP=1 overrides)\n' "$RESULT" >&2
            return 1
        fi
    fi
    local er="$EPOCHREALTIME"
    KT_STORM_TAG="$$.${er/[.,]/}"
    _kt_storm_marker "$KT_STORM_TAG"
    local marker="$REPLY"
    for (( i = 0; i < n; i++ )); do
        "$BASH" -c "$_KT_STORM_WORKER" "$marker" "${KT_STORM_FUNCS:-1000}" \
            "${KT_STORM_BALLAST:-}" "${KT_STORM_HEARTBEAT:-}" </dev/null >/dev/null 2>&1 &
        KT_STORM_PIDS+=( "$!" )
    done
    return 0
}

# kt_storm_stop -> rc 0 when nothing of this storm is left
kt_storm_stop() {
    local p i
    if [[ -z "$KT_STORM_TAG" ]]; then
        return 0
    fi
    for p in "${KT_STORM_PIDS[@]}"; do kill -TERM "$p" 2>/dev/null || :; done
    for (( i = 0; i < 50; i++ )); do
        kt_storm_alive
        (( RESULT == 0 )) && break
        sleep 0.1
    done
    if (( RESULT > 0 )); then
        for p in "${KT_STORM_PIDS[@]}"; do kill -KILL "$p" 2>/dev/null || :; done
    fi
    # reap our own children (a no-op for pids this shell did not start)
    for p in "${KT_STORM_PIDS[@]}"; do wait "$p" 2>/dev/null || :; done
    # an in-flight `$( )` child of a worker ends by itself within a fork's
    # time; wait for it, and kill it if it lingers
    for (( i = 0; i < 50; i++ )); do
        _kt_storm_scan_pids "$KT_STORM_TAG"
        (( ${#KT_STORM_FOUND[@]} == 0 )) && break
        (( i == 30 )) && for p in "${KT_STORM_FOUND[@]}"; do kill -KILL "$p" 2>/dev/null || :; done
        sleep 0.1
    done
    _kt_storm_scan_pids "$KT_STORM_TAG"
    kt_storm_alive
    if (( RESULT > 0 || ${#KT_STORM_FOUND[@]} > 0 )); then
        printf 'kt_storm_stop: storm %s left %s worker(s) and %s process(es): %s\n' \
            "$KT_STORM_TAG" "$RESULT" "${#KT_STORM_FOUND[@]}" "${KT_STORM_FOUND[*]}" >&2
        return 1
    fi
    KT_STORM_PIDS=()
    KT_STORM_TAG=""
    return 0
}

# --- latency probe used by self-check: RESULT = "p50 p90 p99 max" in ms -------
_kt_storm_forklat() {
    local s="${1:-100}" i a b
    local -a L=() S=()
    for (( i = 0; i < s; i++ )); do
        a=${EPOCHREALTIME/[.,]/}; x=$(:); b=${EPOCHREALTIME/[.,]/}
        L+=( $(( (b - a) / 1000 )) )
    done
    mapfile -t S < <(printf '%s\n' "${L[@]}" | sort -n)
    RESULT="${S[s/2]} ${S[s*9/10]} ${S[s*99/100]} ${S[s-1]}"
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _fs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _fs_state="$_fs_dir/../.tmp/forkstorm.pids"
    _fs_cmd="${1:-}"; shift || :
    _fs_args=()
    while (( $# > 0 )); do
        case "$1" in
            --state) _fs_state="${2:?--state needs a file}"; shift 2 ;;
            --state=*) _fs_state="${1#*=}"; shift ;;
            *) _fs_args+=( "$1" ); shift ;;
        esac
    done
    mkdir -p "$(dirname "$_fs_state")"

    _fs_load() {   # state file -> KT_STORM_TAG + KT_STORM_PIDS
        KT_STORM_TAG=""; KT_STORM_PIDS=()
        [[ -f "$_fs_state" ]] || return 1
        local line
        { read -r KT_STORM_TAG; while read -r line; do [[ -n "$line" ]] && KT_STORM_PIDS+=( "$line" ); done; } < "$_fs_state"
        [[ -n "$KT_STORM_TAG" ]]
    }

    case "$_fs_cmd" in
        start)
            if _fs_load; then
                kt_storm_alive
                if (( RESULT > 0 )); then
                    printf 'forkstorm: storm %s from %s is still running (%s alive) — stop it first\n' \
                        "$KT_STORM_TAG" "$_fs_state" "$RESULT" >&2
                    exit 1
                fi
            fi
            KT_STORM_TAG=""; KT_STORM_PIDS=()
            kt_storm_start "${_fs_args[0]:-8}" || exit $?
            printf '%s\n' "$KT_STORM_TAG" "${KT_STORM_PIDS[@]}" > "$_fs_state"
            printf 'forkstorm: started %s worker(s), tag %s, pids %s (state %s)\n' \
                "${#KT_STORM_PIDS[@]}" "$KT_STORM_TAG" "${KT_STORM_PIDS[*]}" "$_fs_state"
            ;;
        stop)
            if ! _fs_load; then
                printf 'forkstorm: no storm recorded in %s\n' "$_fs_state"
                exit 0
            fi
            if kt_storm_stop; then
                rm -f "$_fs_state"
                printf 'forkstorm: stopped storm, nothing left\n'
            else
                exit 1
            fi
            ;;
        status)
            if _fs_load; then
                kt_storm_alive; _fs_alive=$RESULT
                kt_storm_scan "$KT_STORM_TAG"
                printf 'forkstorm: storm %s — %s of %s worker(s) alive, %s process(es) in /proc\n' \
                    "$KT_STORM_TAG" "$_fs_alive" "${#KT_STORM_PIDS[@]}" "$RESULT"
            else
                printf 'forkstorm: no storm recorded in %s\n' "$_fs_state"
            fi
            kt_storm_scan
            printf 'forkstorm: %s storm process(es) of any tag visible in this runtime\n' "$RESULT"
            ;;
        self-check)
            _fs_n="${_fs_args[0]:-8}"
            printf 'forkstorm self-check: bash %s, %s workers\n' "$BASH_VERSION" "$_fs_n"
            _kt_storm_forklat 100
            printf '  idle        fork ms p50/p90/p99/max: %s\n' "${RESULT// //}"
            kt_storm_start "$_fs_n" || exit $?
            sleep 1
            kt_storm_alive; _fs_alive=$RESULT
            _kt_storm_forklat 100
            printf '  storm %-4s  fork ms p50/p90/p99/max: %s  (%s/%s workers alive)\n' \
                "$_fs_n" "${RESULT// //}" "$_fs_alive" "$_fs_n"
            _fs_tag="$KT_STORM_TAG"
            if kt_storm_stop; then _fs_rc=0; else _fs_rc=1; fi
            kt_storm_scan "$_fs_tag"
            printf '  after stop: %s process(es) of the storm left, stop rc %s\n' "$RESULT" "$_fs_rc"
            if (( _fs_rc == 0 && RESULT == 0 && _fs_alive == _fs_n )); then
                printf 'forkstorm self-check: OK\n'
            else
                printf 'forkstorm self-check: FAILED\n'
                exit 1
            fi
            ;;
        *)
            sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            [[ "$_fs_cmd" == "-h" || "$_fs_cmd" == "--help" ]] && exit 0
            exit 2
            ;;
    esac
fi
