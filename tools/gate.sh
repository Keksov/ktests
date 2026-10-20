#!/bin/bash
# gate.sh — the phase gate (ktests/GATE_PLAN.md): run test suites under one or
# more bash runtimes, every suite as a hermetic CELL of its own, and report a
# line per cell, a summary per runtime and one machine line.
#
#   gate.sh [options] SUITE... [-- ARGS...]
#
#   SUITE   `all` (every suite of the master sweep, in its discovery order), a
#           suite id = the suite's dir relative to the root without /tests
#           (kkore, kklass, ktests, kcl = kcl/tests, kcl/tstringlist), or a
#           unique last component (tstringlist). Cells always run in
#           discovery order. Unknown or ambiguous: usage error, rc 2, before
#           anything runs.
#   ARGS    passed to every suite's tests.sh (e.g. -- -n 1-12)
#
# Options:
#   --bash PATH     a runtime to run the cells under; repeatable, one SEGMENT
#                   per --bash, one after another (DG3). Default
#                   KT_GATE_BASHES="PATH;PATH"; with neither the bash running
#                   this script alone, and a `[WARN] one runtime only`.
#   --mode threaded|single  the runner mode of every cell (default threaded)
#   --workers N     the runner's --workers
#   --cwd neutral|suite     the cell's working dir: an empty dir of its own
#                   (default) or the suite's tests/ dir
#   --timeout SEC   per cell (default 1800): the cell's group is stopped,
#                   verdict TIMEOUT
#   --root DIR      the tree to test (default: the one holding this ktests)
#   --out DIR       the run's directory: a new one (made with an atomic mkdir)
#                   or an existing EMPTY one (dot names count; claimed with an
#                   exclusive marker). Default ${TMPDIR:-/tmp}/kt-gate/
#                   STAMP-PID; only there old runs are rotated (see OUT).
#   --keep          keep the sandbox of PASSED cells too (others always kept)
#   --nohup         no parent watch (see PROCESSES): for a run detached on
#                   purpose. Implied when SIGHUP is ignored on entry
#                   (`nohup gate.sh …`).
#   G3, not yet (usage error rc 2): --compare --rerun-failed --changed
#   --repeat --parallel --fail-fast --warm, --mode both, --cwd both.
#   Ctrl-Z (TSTP) is not supported: a `[WARN]`, ignored.
#
# Output (stdout; every line also appended to OUT/progress.txt — a background
# run is watched with `tail OUT/progress.txt`):
#   gate STAMP root=ROOT out=OUT            header: start, tree, run dir
#   gate repos: NAME SHA[+dirty] ...        the root repo and its submodules
#   gate bashes: / gate cells:              the runtimes, the selection
#   [ i/N] VER MODE CWD SUITE VERDICT PASSED/TOTAL [warn=W] DUR [log=...] [(why)]
#           [FAIL] ...                      the first 5 lines of the [FAIL]
#                                           messages (with their continuations)
#   gate VER: C cells  P PASS  F FAIL  0 FLAKY  E ENV  T TIMEOUT  S STRAY  X CRASH  Y NOTRUN  tests p/t  DUR
#   gate VERDICT  out=OUT
#   __GATE__:VERDICT:cells:pass:fail:flaky:env:timeout:stray:passed_tests:total_tests
# `fail` in the machine line counts FAIL and CRASH cells; cells = cells
# planned; NOTRUN (and INTERRUPTED / not started) cells are in none of the
# fields, so pass + fail + ... can be less than cells.
#
# Verdict of a cell (worst wins): STRAY (it left a process: found, stopped)
# · TIMEOUT (stopped at --timeout) · NOTRUN (the suite has no test file:
# summary `error no-test-files`; not a failure) · CRASH (no summary file
# from the runner, or one that says `error REASON`: the runner itself did
# not finish) · FAIL · PASS. ENV refines CRASH and FAIL — the machine, not
# the test: a FAIL whose summary has `env NAME` lines (the RUNNER saw a file
# die of a fork failure) or whose log has a RAW fork-failure line
# (KT_ENV_FORK_FAILURE_RE in a line that is no test message: never in
# [FAIL]/[PASS]/[WARN] lines or their continuations — a test may talk about
# fork failures; the runner's own "source aborted" line counts); a CRASH with
# such a raw line, or without a summary at rc 125-127. An ENV cell is re-run
# ONCE in a fresh sandbox, the second run decides, both attempts are kept.
# INTERRUPTED: the cell was stopped by a stop of the gate (not a verdict of
# the suite). `warn=N` (the log's [WARN] lines) is a column, not a verdict.
# Gate VERDICT: PASS, FAIL, ENV or INTERRUPTED.
# Exit status: 0 every cell PASS (or NOTRUN, at least one PASS) · 1 any
# FAIL/TIMEOUT/STRAY/CRASH, a segment that died or lost its watchdog, or
# every cell NOTRUN (`[WARN] nothing ran`) · 2 usage · 3 no hard failure, ENV
# left after the retry · 4 reserved (FLAKY, G3) · 128+N interrupted by signal
# N (143 also for a lost parent), after the running cell was stopped.
#
# PROCESSES (GATE_PLAN 4.1; the two runtimes cannot signal or see each other):
#   launcher  this script as started: parses, resolves, claims OUT, writes
#             one spec per runtime (OUT/seg-N.spec, mixed C:/... paths, the
#             caller's locale etc.), starts the segment with `env
#             --default-signal=INT,QUIT -i` (INT/QUIT trappable in the cells;
#             plus setsid/perl for a new session in its own runtime; its nap
#             fd closed), never signals it — except, in its own runtime, once
#             when a stop goes unanswered for KT_GATE_STOP_WAIT — and never
#             trusts its rc: OUT/seg-N.result is the verdict. A 1 s nap loop
#             relays the segment's lines, checks the result and the stub,
#             rewrites OUT/hb every 5 s, watches its own parent (kill -0 +
#             /proc/PPID/winpid; parent gone = TERM) and the watchdog's
#             OUT/seg-N.wdhb: silent for 30 ticks -> a rescue watchdog (the
#             same `gate.sh --watchdog`, up to 3). TERM/INT/HUP: OUT/STOP,
#             wait for the result, report, 128+N.
#   segment   `BASH gate.sh --segment SPEC`: runs its cells one by one through
#             suitejob.sh (kt_suitejob_run: a job-control group per cell; it
#             `wait`s, no fork while a cell runs), the stray check after every
#             cell (window = the cell's start) and once at the end (window =
#             the segment's start). Before every cell it makes sure a watchdog
#             is alive (seg-N.wdpid): else it starts one again, once, then
#             stops (`no-watchdog`). Its exec'd WATCHDOG (`gate.sh
#             --watchdog`, builtins only, 1 s tick, touches seg-N.wdhb) sends
#             USR1 — only while a cell runs, repeated until the segment
#             acknowledges — on OUT/STOP, on 30 ticks without a fresh OUT/hb
#             (launcher killed) and at the running cell's deadline
#             (--timeout); when the segment itself is gone (a `taskkill /T`
#             tree kill) it stops the cells of the segment's session and
#             writes the result (`segment-killed`).
#   cell      the suite's tests.sh with HOME, TMPDIR/TMP/TEMP, USERPROFILE,
#             ProgramData, __KK_CFG_ETC, KKLASS_CKK_DIR of its own
#             (OUT/cells/NNN/{home,tmp,etc,ckk}), KT_SUMMARY_FILE, cwd
#             OUT/cells/NNN/cwd (or the suite dir), stdin /dev/null, fds 0-2
#             only. The environment is deny-by-default: the segment starts
#             from `env -i` and keeps only PATH and the caller's whitelisted
#             variables (locale, TZ, COMSPEC, SYSTEMROOT, ...; see
#             _KT_GATE_ENV_KEEP). The launcher resets its own shell state
#             first: an exported SHELLOPTS/BASHOPTS/CDPATH changes nothing.
#
# OUT: .kt_gate (marker `kt-gate 2 PID WINPID START CREATED RUNTIME`),
#   progress.txt, argv.txt, hb, STOP, INTERRUPTED, FINISHED,
#   seg-N.{spec,log,lines,cur,why,ack,pid,wdpid,wdhb,result,strays.txt},
#   cells/NNN/{result,log.txt,summary,fails.txt,strays.txt} (+ log.1.txt,
#   summary.1, fails.1.txt of an ENV first attempt) and the sandbox dirs. A
#   cell's `result` is KEY=VALUE lines: idx bash_version bash_path mode cwd
#   suite repeat verdict rc total passed failed warn fail_lines strays
#   attempts duration_ms log reason attempt1 (G3's cells.tsv columns).
#   Rotation ONLY under the default root ${TMPDIR:-/tmp}/kt-gate (an
#   explicit --out's neighbours may be the user's runs): of its gate-marked
#   dirs the newest 10 are kept; an older one is removed only when gate made
#   it (CREATED=1), its owner is dead (same runtime: kill -0; the other
#   runtime: FINISHED/INTERRUPTED or older than 24 h) and it is complete
#   (every seg-N.spec has its seg-N.result) or older than 2 h.
#
# Test knobs (environment of the launcher; they reach segments via the
# spec): KT_GATE_HB_TICKS (stale heartbeat / silent watchdog, ticks, default
# 30), KT_GATE_HB_EVERY (heartbeat period, ticks, default 5),
# KT_GATE_STOP_WAIT (seconds the launcher waits for a stopping segment,
# default 90).
#
# Plain bash (DG2): no kbool/kkore/kklass. Sources suitejob.sh (and with it
# strays.sh) and ../ktest_env_signatures.sh.
if [[ -n "${_KT_GATE_SOURCED:-}" && "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi
_KT_GATE_SOURCED=1

# Run as a program: the shell state this script relies on, whatever the
# caller exported (review R2: SHELLOPTS/BASHOPTS from the environment apply at
# startup — failglob killed the launcher, noclobber/errexit/nounset/allexport
# would too; an exported CDPATH made `cd -P DIR` land in another folder).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set +a +e +f +u +C +o pipefail +o posix 2>/dev/null
    shopt -u failglob nullglob dotglob nocaseglob nocasematch extglob globstar 2>/dev/null
    unset CDPATH GLOBIGNORE
    IFS=$' \t\n'
fi

__kt_gate_src="${BASH_SOURCE[0]}"
__kt_gate_dir="${__kt_gate_src%/*}"; [[ "$__kt_gate_dir" == "$__kt_gate_src" ]] && __kt_gate_dir=.
__kt_gate_old="$PWD"
if ! builtin cd -P -- "$__kt_gate_dir" 2>/dev/null; then
    printf 'gate: cannot find my own directory (%s)\n' "$__kt_gate_dir" >&2
    exit 2
fi
_KT_GATE_DIR="$PWD"
builtin cd -- "$__kt_gate_old" 2>/dev/null
_KT_GATE_SELF="$_KT_GATE_DIR/${__kt_gate_src##*/}"
unset __kt_gate_src __kt_gate_dir __kt_gate_old
source "$_KT_GATE_DIR/suitejob.sh" || exit 2
source "$_KT_GATE_DIR/../ktest_env_signatures.sh" || exit 2

# the caller's variables a cell keeps (besides PATH, and what the gate sets)
declare -ga _KT_GATE_ENV_KEEP=( LANG LANGUAGE TZ COMSPEC SYSTEMROOT WINDIR SYSTEMDRIVE PATHEXT TERM
    USERNAME NUMBER_OF_PROCESSORS PROCESSOR_ARCHITECTURE OS COMPUTERNAME )

# ---------------------------------------------------------------------------
# common helpers
# ---------------------------------------------------------------------------

# _kt_gate_dur MS -> REPLY "12.3s"; _kt_gate_hms MS -> REPLY "1h02m03s"/"2m03s"/"3s"
_kt_gate_dur() { REPLY="$(( $1 / 1000 )).$(( $1 % 1000 / 100 ))s"; }
_kt_gate_hms() {
    local s=$(( $1 / 1000 ))
    if (( s >= 3600 )); then printf -v REPLY '%dh%02dm%02ds' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
    elif (( s >= 60 )); then printf -v REPLY '%dm%02ds' $(( s / 60 )) $(( s % 60 ))
    else REPLY="${s}s"; fi
}

# _kt_gate_put FILE LINE... — FILE = the LINEs, atomically (temp + mv: a reader
# that sees FILE sees it whole)
_kt_gate_put() {
    local f="$1" t="$1.tmp.$BASHPID"
    shift
    printf '%s\n' "$@" > "$t" && mv -f -- "$t" "$f"
}

# _kt_gate_rt — REPLY = this runtime: the source of the `/` mount
_kt_gate_rt() {
    local a b c
    REPLY="none"
    if [[ -r /proc/mounts ]]; then
        while read -r a b c; do [[ "$b" == / ]] && { REPLY="$a"; break; }; done < /proc/mounts
    fi
}

# _kt_gate_readkv FILE — the assoc _KT_GATE_KV = FILE's KEY=VALUE lines
declare -gA _KT_GATE_KV=() _KT_GATE_FFILES=()
_kt_gate_readkv() {
    local k v
    _KT_GATE_KV=()
    [[ -f "$1" ]] || return 1
    while IFS='=' read -r k v; do [[ -n "$k" ]] && _KT_GATE_KV["$k"]="$v"; done < "$1"
    return 0
}

# _kt_gate_line IDX VERDICT COUNTS WARN DUR_MS EXTRA — REPLY = the cell's
# progress line (spec globals: KT_GATE_S_TOTAL, KT_GATE_S_SW, KT_GATE_S_VW;
# the cell's _KT_GATE_CMODE/_CCWD/_CSUITE)
_kt_gate_line() {
    local w=${#KT_GATE_S_TOTAL} ws=""
    (( $4 > 0 )) && ws="warn=$4"
    _kt_gate_dur "$5"
    printf -v REPLY '[%*d/%d] %-*s %-8s %-7s %-*s  %-11s %9s  %-7s %7s%s' "$w" "$1" "$KT_GATE_S_TOTAL" \
        "${KT_GATE_S_VW:-6}" "$_KT_GATE_VER" "$_KT_GATE_CMODE" "$_KT_GATE_CCWD" "$KT_GATE_S_SW" "$_KT_GATE_CSUITE" \
        "$2" "$3" "$ws" "$REPLY" "$6"
}

# ===========================================================================
# LAUNCHER
# ===========================================================================

kt_gate_usage() { sed -n '2,/^$/p' "$_KT_GATE_SELF" | sed 's/^# \{0,1\}//'; }

_kt_gate_usage_error() {
    printf 'gate: %s\n' "$1" >&2
    printf 'gate: usage: gate.sh [options] SUITE... [-- ARGS...]   (gate.sh --help)\n' >&2
    exit 2
}

# kt_gate_parse ARGS... — the CLI into _KT_GATE_* (usage errors exit 2)
kt_gate_parse() {
    _KT_GATE_BASHES=() _KT_GATE_SUITES_ARG=() _KT_GATE_ARGS=()
    _KT_GATE_MODE=threaded _KT_GATE_WORKERS="" _KT_GATE_CWD=neutral _KT_GATE_TIMEOUT=1800
    _KT_GATE_ROOT_ARG="" _KT_GATE_OUT_ARG="" _KT_GATE_KEEP=0 _KT_GATE_NOHUP=0
    local o eq
    while (( $# > 0 )); do
        eq=0
        if [[ "$1" == --?*=* ]]; then
            set -- "${1%%=*}" "${1#*=}" "${@:2}"; eq=1
        fi
        o="$1"
        case "$o" in
            --bash|--mode|--workers|--cwd|--timeout|--root|--out)
                (( $# >= 2 )) || _kt_gate_usage_error "$o needs a value"
                case "$o" in
                    --bash) [[ -n "$2" ]] || _kt_gate_usage_error "--bash needs a path"; _KT_GATE_BASHES+=( "$2" ) ;;
                    --mode)
                        case "$2" in
                            threaded|single) _KT_GATE_MODE="$2" ;;
                            both) _kt_gate_usage_error "--mode both is not yet implemented (gate G3)" ;;
                            *) _kt_gate_usage_error "--mode must be threaded or single, got \"$2\"" ;;
                        esac ;;
                    --cwd)
                        case "$2" in
                            neutral|suite) _KT_GATE_CWD="$2" ;;
                            both) _kt_gate_usage_error "--cwd both is not yet implemented (gate G3)" ;;
                            *) _kt_gate_usage_error "--cwd must be neutral or suite, got \"$2\"" ;;
                        esac ;;
                    --workers) [[ "$2" =~ ^[1-9][0-9]*$ ]] || _kt_gate_usage_error "--workers needs a number >= 1, got \"$2\""
                               _KT_GATE_WORKERS="$2" ;;
                    --timeout) [[ "$2" =~ ^[1-9][0-9]*$ ]] || _kt_gate_usage_error "--timeout needs whole seconds >= 1, got \"$2\""
                               _KT_GATE_TIMEOUT="$2" ;;
                    --root) _KT_GATE_ROOT_ARG="$2" ;;
                    --out) _KT_GATE_OUT_ARG="$2" ;;
                esac
                shift 2 ;;
            --keep|--nohup)
                (( eq )) && _kt_gate_usage_error "$o takes no value"
                [[ "$o" == --keep ]] && _KT_GATE_KEEP=1 || _KT_GATE_NOHUP=1
                shift ;;
            --compare|--rerun-failed|--repeat|--changed|--parallel|--fail-fast|--warm)
                _kt_gate_usage_error "$o is not yet implemented (gate G3)" ;;
            --segment|--watchdog)
                _kt_gate_usage_error "$o is internal (the launcher starts it)" ;;
            -h|--help) kt_gate_usage; exit 0 ;;
            --) shift; _KT_GATE_ARGS=( "$@" ); break ;;
            -*) _kt_gate_usage_error "unknown option $o" ;;
            *) _KT_GATE_SUITES_ARG+=( "$o" ); shift ;;
        esac
    done
    (( ${#_KT_GATE_SUITES_ARG[@]} > 0 )) || _kt_gate_usage_error "no suite given (name suites, or all)"
    return 0
}

# _kt_gate_mpath PATH -> REPLY: the mixed C:/... spelling (`cygpath -m`): the
# one that names the same file in every cygwin runtime, whatever its mount
# prefix (review R11); without cygpath (or for a non-drive path) PATH as is
_kt_gate_mpath() {
    local m=""
    [[ -n "$_KT_GATE_CYGPATH" ]] && m="$(cygpath -m -- "$1" 2>/dev/null)"
    if [[ "$m" =~ ^[A-Za-z]:/ ]]; then REPLY="$m"; else REPLY="$1"; fi
}

# _kt_gate_dotslash PATH -> REPLY: a relative PATH as ./PATH (never a CDPATH
# or option-looking lookup)
_kt_gate_dotslash() {
    if [[ "$1" == /* || "$1" =~ ^[A-Za-z]:[/\\] ]]; then REPLY="$1"; else REPLY="./$1"; fi
}

# kt_gate_root — _KT_GATE_ROOT (this runtime's spelling, resolved) and
# _KT_GATE_ROOTM (mixed) from --root or this ktests' parent
kt_gate_root() {
    local r="${_KT_GATE_ROOT_ARG:-$_KT_GATE_DIR/../..}" old="$PWD"
    _kt_gate_dotslash "$r"
    builtin cd -P -- "$REPLY" 2>/dev/null || _kt_gate_usage_error "--root $r: no such directory"
    r="$PWD"
    builtin cd -- "$old" 2>/dev/null
    _KT_GATE_ROOT="${r%/}"; [[ -n "$_KT_GATE_ROOT" ]] || _KT_GATE_ROOT=/
    _kt_gate_mpath "$_KT_GATE_ROOT"; _KT_GATE_ROOTM="$REPLY"
}

# kt_gate_resolve — _KT_GATE_SEL = the selected suite ids in discovery order;
# _KT_GATE_ALL_IDS = every id
kt_gate_resolve() {
    local s id a
    local -a m=()
    local -A want=()
    kt_suitejob_discover "$_KT_GATE_ROOT"
    _KT_GATE_ALL_IDS=()
    for s in "${KT_SUITEJOB_SUITES[@]}"; do
        id="${s#"$_KT_GATE_ROOT"/}"; id="${id%/tests/tests.sh}"
        _KT_GATE_ALL_IDS+=( "$id" )
    done
    (( ${#_KT_GATE_ALL_IDS[@]} > 0 )) || _kt_gate_usage_error "no suites (DIR/tests/tests.sh) under $_KT_GATE_ROOT"
    for a in "${_KT_GATE_SUITES_ARG[@]}"; do
        a="${a%/}"; a="${a%/tests.sh}"; a="${a%/tests}"; a="${a#./}"
        if [[ "$a" == all ]]; then
            for id in "${_KT_GATE_ALL_IDS[@]}"; do want["$id"]=1; done
            continue
        fi
        m=()
        for id in "${_KT_GATE_ALL_IDS[@]}"; do [[ "$id" == "$a" ]] && m=( "$id" ); done
        if (( ${#m[@]} == 0 )); then
            for id in "${_KT_GATE_ALL_IDS[@]}"; do [[ "${id##*/}" == "$a" ]] && m+=( "$id" ); done
        fi
        case ${#m[@]} in
            0) _kt_gate_usage_error "unknown suite \"$a\" (suites under $_KT_GATE_ROOT: ${_KT_GATE_ALL_IDS[*]})" ;;
            1) want["${m[0]}"]=1 ;;
            *) _kt_gate_usage_error "ambiguous suite \"$a\": ${m[*]}" ;;
        esac
    done
    _KT_GATE_SEL=()
    for id in "${_KT_GATE_ALL_IDS[@]}"; do [[ -n "${want["$id"]+x}" ]] && _KT_GATE_SEL+=( "$id" ); done
    return 0
}

# kt_gate_bashes — every runtime: _KT_GATE_B_PATH (launcher spelling),
# _KT_GATE_B_MIXED (C:/...), _KT_GATE_B_VER, _KT_GATE_B_RT (its / mount)
kt_gate_bashes() {
    local b u out
    local -a list=( "${_KT_GATE_BASHES[@]}" ) env_w L
    _KT_GATE_ONE=0
    if (( ${#list[@]} == 0 )) && [[ -n "${KT_GATE_BASHES:-}" ]]; then
        IFS=';' read -r -a list <<< "$KT_GATE_BASHES"
    fi
    if (( ${#list[@]} == 0 )); then list=( "$BASH" ); _KT_GATE_ONE=1; fi
    _KT_GATE_B_PATH=() _KT_GATE_B_MIXED=() _KT_GATE_B_VER=() _KT_GATE_B_RT=()
    for b in "${list[@]}"; do
        [[ -n "$b" ]] || continue
        u="$b"
        [[ -n "$_KT_GATE_CYGPATH" ]] && u="$(cygpath -u -- "$b" 2>/dev/null)"
        [[ -n "$u" && -f "$u" && -x "$u" ]] || _kt_gate_usage_error "--bash $b is not an executable file"
        env_w=( "PATH=${u%/*}:$PATH" )
        [[ -n "${SYSTEMROOT:-}" ]] && env_w+=( "SYSTEMROOT=$SYSTEMROOT" )
        [[ -n "${WINDIR:-}" ]] && env_w+=( "WINDIR=$WINDIR" )
        out="$(env -i "${env_w[@]}" "$u" -c 'printf "%s\n" "${BASH_VERSION%%(*}"; r=none; while read -r a b c; do [[ "$b" == / ]] && { r="$a"; break; }; done < /proc/mounts; printf "%s\n" "$r"' 2>/dev/null </dev/null)"
        mapfile -t L <<< "$out"
        [[ "${L[0]:-}" =~ ^[0-9]+\.[0-9]+ ]] || _kt_gate_usage_error "--bash $b does not run as a bash (no BASH_VERSION)"
        _KT_GATE_B_PATH+=( "$u" ); _KT_GATE_B_VER+=( "${L[0]}" ); _KT_GATE_B_RT+=( "${L[1]:-none}" )
        if [[ -n "$_KT_GATE_CYGPATH" ]]; then _KT_GATE_B_MIXED+=( "$(cygpath -m -- "$u" 2>/dev/null)" ); else _KT_GATE_B_MIXED+=( "$u" ); fi
    done
    (( ${#_KT_GATE_B_PATH[@]} > 0 )) || _kt_gate_usage_error "no bash to run (empty --bash / KT_GATE_BASHES)"
    return 0
}

# kt_gate_out — claim OUT, write the marker, argv.txt; rotation.
#   default: ${TMPDIR:-/tmp}/kt-gate/STAMP-PID made by an ATOMIC mkdir (a name
#     taken — the other runtime has its own pids — gets -2, -3, ...).
#   --out DIR: a new DIR (its parent made with -p, the leaf by an atomic mkdir)
#     or an existing EMPTY one — emptiness checked on the RESOLVED path, dot
#     names included; then the marker is created exclusively (noclobber), so
#     two gates never share a dir (review R2: CDPATH, F8, F14).
#   The marker `kt-gate 2 PID WINPID START CREATED RUNTIME` records whether
#   gate made the dir (CREATED=1): rotation never removes one it did not make.
kt_gate_out() {
    local o="$_KT_GATE_OUT_ARG" stamp old="$PWD" base p n=1 wp="" rc
    local -a e=()
    _KT_GATE_CREATED=0 _KT_GATE_DEFROOT=0
    if [[ -z "$o" ]]; then
        p="${TMPDIR:-/tmp}/kt-gate"
        mkdir -p -- "$p" 2>/dev/null
        printf -v stamp '%(%Y%m%d-%H%M%S)T' -1
        base="$p/$stamp-$$"; o="$base"
        until mkdir -- "$o" 2>/dev/null; do
            (( ++n > 50 )) && _kt_gate_usage_error "cannot create a run dir under $p"
            o="$base-$n"
        done
        _KT_GATE_CREATED=1 _KT_GATE_DEFROOT=1
    else
        _kt_gate_dotslash "$o"; o="$REPLY"
        if [[ -e "$o" || -L "$o" ]]; then
            [[ -d "$o" ]] || _kt_gate_usage_error "--out $_KT_GATE_OUT_ARG exists and is not a directory"
        else
            [[ "${o%/}" == */* ]] && mkdir -p -- "${o%/*}" 2>/dev/null
            mkdir -- "$o" 2>/dev/null && _KT_GATE_CREATED=1
            [[ -d "$o" ]] || _kt_gate_usage_error "cannot create --out $_KT_GATE_OUT_ARG"
        fi
    fi
    builtin cd -P -- "$o" 2>/dev/null || _kt_gate_usage_error "cannot enter --out $_KT_GATE_OUT_ARG"
    o="$PWD"
    builtin cd -- "$old" 2>/dev/null
    if (( ! _KT_GATE_CREATED )); then
        shopt -s nullglob dotglob; e=( "$o"/* ); shopt -u nullglob dotglob
        (( ${#e[@]} == 0 )) || _kt_gate_usage_error "--out $_KT_GATE_OUT_ARG is not empty ($o)"
    fi
    { read -r wp < "/proc/$$/winpid"; } 2>/dev/null
    set -C
    { printf 'kt-gate 2 %s %s %s %s %s\n' "$$" "${wp:-0}" "$EPOCHSECONDS" "$_KT_GATE_CREATED" "$_KT_GATE_RT" > "$o/.kt_gate"; } 2>/dev/null
    rc=$?
    set +C
    (( rc == 0 )) || _kt_gate_usage_error "--out $_KT_GATE_OUT_ARG is in use by another gate ($o)"
    _KT_GATE_OUT="$o"
    _kt_gate_mpath "$_KT_GATE_OUT"; _KT_GATE_OUTM="$REPLY"
    mkdir -p -- "$_KT_GATE_OUT/cells"
    printf '%q ' "$_KT_GATE_SELF" "${_KT_GATE_ARGV[@]}" > "$_KT_GATE_OUT/argv.txt"; echo >> "$_KT_GATE_OUT/argv.txt"
    : > "$_KT_GATE_OUT/progress.txt"
    (( _KT_GATE_DEFROOT )) && kt_gate_rotate
    return 0
}

# kt_gate_rotate — ONLY under the default root (review R3): of its
# gate-marked dirs the newest 10 stay; an older one is removed only when gate
# made it (marker v2, CREATED=1), its owner is dead (same runtime: kill -0;
# the other runtime: FINISHED/INTERRUPTED or older than 24 h) AND it is
# complete — every seg-N.spec has its seg-N.result — or older than 2 h (F15)
kt_gate_rotate() {
    local parent="${_KT_GATE_OUT%/*}" d pid st cr rt tag ver i n s ok age
    local -a dirs=() starts=()
    for d in "$parent"/*/; do
        d="${d%/}"
        [[ -f "$d/.kt_gate" && ! -L "$d" ]] || continue
        st=0; { read -r _ _ _ _ st _ < "$d/.kt_gate"; } 2>/dev/null
        [[ "$st" =~ ^[0-9]+$ ]] || st=0
        # insertion sort by start, oldest first
        for (( i = ${#dirs[@]}; i > 0 && starts[i-1] > st; i-- )); do
            dirs[i]="${dirs[i-1]}"; starts[i]="${starts[i-1]}"
        done
        dirs[i]="$d"; starts[i]="$st"
    done
    n=$(( ${#dirs[@]} - 10 ))
    for (( i = 0; i < n; i++ )); do
        d="${dirs[i]}"
        [[ "$d" == "$_KT_GATE_OUT" ]] && continue
        tag="" ver="" pid="" st="" cr="" rt=""
        { read -r tag ver pid _ st cr rt < "$d/.kt_gate"; } 2>/dev/null
        [[ "$tag" == kt-gate && "$ver" == 2 && "$cr" == 1 && "$pid" =~ ^[0-9]+$ && "$st" =~ ^[0-9]+$ ]] || continue
        age=$(( EPOCHSECONDS - st ))
        if [[ "$rt" == "$_KT_GATE_RT" ]]; then
            kill -0 "$pid" 2>/dev/null && continue
        else
            [[ -e "$d/FINISHED" || -e "$d/INTERRUPTED" ]] || (( age > 86400 )) || continue
        fi
        ok=1
        for s in "$d"/seg-*.spec; do
            [[ -e "$s" ]] || continue
            [[ -e "${s%.spec}.result" ]] || ok=0
        done
        (( ok || age > 7200 )) || continue
        rm -rf -- "$d"
    done
}

# kt_gate_repos — REPLY = "NAME SHA[+dirty] ..." for the root and its submodules
kt_gate_repos() {
    local r="$_KT_GATE_ROOT" sha st p k v out=""
    local -a subs=()
    REPLY="(no git)"
    command -v git >/dev/null 2>&1 || return 0
    sha="$(git -C "$r" rev-parse --short HEAD 2>/dev/null)"
    [[ -n "$sha" ]] || { REPLY="(not a git repository)"; return 0; }
    st="$(git -C "$r" status --porcelain 2>/dev/null)"
    out="${r##*/} $sha${st:++dirty}"
    if [[ -f "$r/.gitmodules" ]]; then
        while IFS=' =' read -r k v; do
            [[ "$k" == path ]] && subs+=( "${v# }" )
        done < <(sed 's/^[[:space:]]*//; s/[[:space:]]*=[[:space:]]*/ = /' "$r/.gitmodules")
    fi
    for p in "${subs[@]}"; do
        p="${p% }"
        sha="$(git -C "$r/$p" rev-parse --short HEAD 2>/dev/null)"
        [[ -n "$sha" ]] || { out+=" $p (none)"; continue; }
        st="$(git -C "$r/$p" status --porcelain 2>/dev/null)"
        out+=" $p $sha${st:++dirty}"
    done
    REPLY="$out"
}

# _kt_gate_say LINE — stdout + progress.txt
_kt_gate_say() {
    printf '%s\n' "$1"
    printf '%s\n' "$1" >> "$_KT_GATE_OUT/progress.txt" 2>/dev/null
}

# _kt_gate_relay N — print the segment's new, complete lines
_kt_gate_relay() {
    local f="$_KT_GATE_OUT/seg-$1.lines" l
    local -a L=()
    [[ -f "$f" ]] || return 0
    mapfile -s "$_KT_GATE_SHOWN" L < "$f"
    for l in "${L[@]}"; do
        [[ "$l" == *$'\n' ]] || break      # a line still being written
        _kt_gate_say "${l%$'\n'}"
        _KT_GATE_SHOWN=$(( _KT_GATE_SHOWN + 1 ))
    done
}

_kt_gate_hb() { printf '%s\n' "$EPOCHREALTIME" > "$_KT_GATE_OUT/hb" 2>/dev/null; }

# _kt_gate_parent_ok — rc 1 when the launcher's parent is gone (also a
# parent killed at the Windows level: cygwin keeps its pid, /proc loses it)
_kt_gate_parent_ok() {
    local w=""
    (( _KT_GATE_WATCH )) || return 0
    kill -0 "$_KT_GATE_PP" 2>/dev/null || return 1
    { read -r w < "/proc/$_KT_GATE_PP/winpid"; } 2>/dev/null
    [[ -n "$w" && "$w" == "$_KT_GATE_PPW" ]]
}

_kt_gate_on_sig() { (( _KT_GATE_SIG )) || { _KT_GATE_SIG=$1; _KT_GATE_SIGWHY="$2"; }; }

# _kt_gate_stop_request — OUT/STOP + the INTERRUPTED mark (once)
_kt_gate_stop_request() {
    (( _KT_GATE_STOPPED )) && return 0
    _KT_GATE_STOPPED=1
    : > "$_KT_GATE_OUT/STOP"
    printf 'launcher: %s (exit %s)\n' "$_KT_GATE_SIGWHY" "$_KT_GATE_SIG" >> "$_KT_GATE_OUT/INTERRUPTED"
    _kt_gate_say "[WARN] gate interrupted ($_KT_GATE_SIGWHY): stopping the running cell"
}

# kt_gate_spec K — write OUT/seg-N.spec for runtime K (0-based; N = K+1)
kt_gate_spec() {
    local k=$1 n=$(( $1 + 1 )) s v i
    KT_GATE_S_VERSION=1
    KT_GATE_S_SEG=$n
    # mixed C:/... paths (review R11): the same file under any mount prefix;
    # the segment turns them into its own spelling once (cygpath -u)
    KT_GATE_S_OUT="$_KT_GATE_OUTM"
    KT_GATE_S_ROOT="$_KT_GATE_ROOTM"
    KT_GATE_S_SELF="$_KT_GATE_SELFM"
    KT_GATE_S_BASH="${_KT_GATE_B_MIXED[k]}"
    KT_GATE_S_TOTAL=$_KT_GATE_NCELLS
    KT_GATE_S_SW=$_KT_GATE_SW
    KT_GATE_S_VW=$_KT_GATE_VW
    KT_GATE_S_TIMEOUT=$_KT_GATE_TIMEOUT
    KT_GATE_S_KEEP=$_KT_GATE_KEEP
    KT_GATE_S_WORKERS="$_KT_GATE_WORKERS"
    KT_GATE_S_HB_TICKS=$_KT_GATE_HB_TICKS
    KT_GATE_S_LAUNCHER="$$ ${_KT_GATE_RT}"
    KT_GATE_S_ARGS=( "${_KT_GATE_ARGS[@]}" )
    KT_GATE_S_ENV=()
    for v in "${_KT_GATE_ENV_KEEP[@]}"; do
        [[ -n "${!v+x}" ]] && KT_GATE_S_ENV+=( "$v=${!v}" )
    done
    for v in $(compgen -e); do
        [[ "$v" == LC_* ]] && KT_GATE_S_ENV+=( "$v=${!v}" )
    done
    KT_GATE_S_C_IDX=() KT_GATE_S_C_SUITE=() KT_GATE_S_C_MODE=() KT_GATE_S_C_CWD=() KT_GATE_S_C_REP=()
    i=$(( k * ${#_KT_GATE_SEL[@]} ))
    for s in "${_KT_GATE_SEL[@]}"; do
        i=$(( i + 1 ))
        KT_GATE_S_C_IDX+=( "$i" ); KT_GATE_S_C_SUITE+=( "$s" ); KT_GATE_S_C_MODE+=( "$_KT_GATE_MODE" )
        KT_GATE_S_C_CWD+=( "$_KT_GATE_CWD" ); KT_GATE_S_C_REP+=( 1 )
    done
    declare -p KT_GATE_S_VERSION KT_GATE_S_SEG KT_GATE_S_OUT KT_GATE_S_ROOT KT_GATE_S_SELF KT_GATE_S_BASH \
        KT_GATE_S_TOTAL KT_GATE_S_SW KT_GATE_S_VW KT_GATE_S_TIMEOUT KT_GATE_S_KEEP KT_GATE_S_WORKERS KT_GATE_S_HB_TICKS \
        KT_GATE_S_LAUNCHER KT_GATE_S_ARGS KT_GATE_S_ENV KT_GATE_S_C_IDX KT_GATE_S_C_SUITE KT_GATE_S_C_MODE \
        KT_GATE_S_C_CWD KT_GATE_S_C_REP > "$_KT_GATE_OUT/seg-$n.spec"
}

# _kt_gate_env_cmd K -> the array _KT_GATE_CMD: the start of runtime K's bash
# with a clean environment (env -i), INT/QUIT default (see kt_gate_segment_run)
_kt_gate_env_cmd() {
    local b="${_KT_GATE_B_PATH[$1]}"
    _KT_GATE_CMD=( env --default-signal=INT,QUIT -i "PATH=${b%/*}:$PATH" )
    [[ -n "${SYSTEMROOT:-}" ]] && _KT_GATE_CMD+=( "SYSTEMROOT=$SYSTEMROOT" )
    [[ -n "${WINDIR:-}" ]] && _KT_GATE_CMD+=( "WINDIR=$WINDIR" )
    _KT_GATE_CMD+=( "$b" )
}

# _kt_gate_spawn SAME LOG CMD... — CMD in the background, stdin /dev/null,
# output appended to LOG; the launcher's nap fd (a pty master) is closed
# around it so no child inherits it (review R12); the other runtime's stub in
# a process group of its own (a terminal's Ctrl-C reaches the launcher only —
# a signal to the stub would TerminateProcess the child, G0). Not under
# `set -m` in the own runtime: setsid() fails for a group leader.
# REPLY = the stub's pid.
_kt_gate_spawn() {
    local same=$1 log=$2
    shift 2
    _kt_strays_nap_close
    if (( same )); then
        "$@" < /dev/null >> "$log" 2>&1 &
        REPLY=$!
    else
        set -m
        "$@" < /dev/null >> "$log" 2>&1 &
        REPLY=$!
        set +m
    fi
    _kt_strays_nap_open
}

# _kt_gate_rescue K N — a rescue watchdog for segment N (runtime K) whose own
# watchdog went silent (review R6): the same `gate.sh --watchdog`, started
# from here, in the segment's runtime, for the segment's main (seg-N.pid)
_kt_gate_rescue() {
    local k=$1 n=$2 sp="" sst=""
    { read -r sp _ _ sst < "$_KT_GATE_OUT/seg-$n.pid"; } 2>/dev/null
    [[ "$sp" =~ ^[0-9]+$ && -n "$sst" ]] || return 1
    _kt_gate_env_cmd "$k"
    _KT_GATE_CMD+=( "$_KT_GATE_SELFM" --watchdog "$_KT_GATE_OUTM/seg-$n.spec" "$sp" "$sst" )
    _kt_gate_spawn "${_KT_GATE_B_SAME[k]}" "$_KT_GATE_OUT/seg-$n.log" "${_KT_GATE_CMD[@]}"
    _KT_GATE_RESCUES+=( "$REPLY" )
    _kt_gate_say "[WARN] segment $n: its watchdog went silent - a rescue watchdog was started (pid $REPLY)"
    return 0
}

# kt_gate_segment_run K — start the segment of runtime K, relay its lines,
# heartbeat, watch the parent, until its result is there (or it is gone)
kt_gate_segment_run() {
    local k=$1 n=$(( $1 + 1 )) stub tick=0 gone=0 t0=$SECONDS i wmiss=0 sp=""
    local res="$_KT_GATE_OUT/seg-$n.result" wdhb="$_KT_GATE_OUT/seg-$n.wdhb" lmark="$_KT_GATE_OUT/seg-$n.lmark"
    # env --default-signal (in _kt_gate_env_cmd): a `&` start without job
    # control hands the child INT and QUIT as SIG_IGN, which no trap in the
    # segment or a cell can undo (review R1: kcl/thttpserver 006 lost its INT
    # trap); env resets them right before the exec of the target bash, through
    # setsid/perl too
    _kt_gate_env_cmd "$k"
    local -a cmd=( "${_KT_GATE_CMD[@]}" "$_KT_GATE_SELFM" --segment "$_KT_GATE_OUTM/seg-$n.spec" )
    # same runtime: a session of its own (the stray checks look at the
    # segment's session — never at the caller's other processes); the other
    # runtime starts it as a session leader anyway
    if (( _KT_GATE_B_SAME[k] )); then
        if [[ -n "$_KT_GATE_SETSID" ]]; then
            cmd=( "$_KT_GATE_SETSID" "${cmd[@]}" )
        elif [[ -n "$_KT_GATE_PERL" ]]; then
            cmd=( "$_KT_GATE_PERL" -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 127' "${cmd[@]}" )
        fi
    fi
    _KT_GATE_SHOWN=0 _KT_GATE_RESCUES=()
    _kt_gate_hb
    : > "$_KT_GATE_OUT/seg-$n.log"
    _kt_gate_spawn "${_KT_GATE_B_SAME[k]}" "$_KT_GATE_OUT/seg-$n.log" "${cmd[@]}"
    stub=$REPLY
    _KT_GATE_SEG_T0[k]=$EPOCHREALTIME
    while :; do
        _kt_strays_nap 1
        _kt_gate_relay "$n"
        if (( ! _KT_GATE_SIG )) && ! _kt_gate_parent_ok; then
            _kt_gate_on_sig 143 "the launcher's parent is gone"
        fi
        if (( _KT_GATE_SIG && ! _KT_GATE_STOPPED )); then
            _kt_gate_stop_request; t0=$SECONDS
        fi
        [[ -e "$res" ]] && break
        if ! kill -0 "$stub" 2>/dev/null; then
            # gone without a result: give its watchdog time to write one
            (( ++gone > 30 )) && break
        fi
        # the segment's watchdog ticks seg-N.wdhb every second: silent for
        # HB_TICKS ticks (killed, hung) -> a rescue watchdog (review R6)
        if [[ -e "$wdhb" && "$wdhb" -nt "$lmark" ]]; then
            : > "$lmark"; wmiss=0
        elif (( ++wmiss >= _KT_GATE_HB_TICKS && ${#_KT_GATE_RESCUES[@]} < 3 )); then
            _kt_gate_rescue "$k" "$n"
            wmiss=0
        fi
        if (( _KT_GATE_STOPPED && SECONDS - t0 > _KT_GATE_STOP_WAIT )); then
            # the stop was not answered: in this runtime, ask the segment
            # itself (its USR1 trap reads the reason); then give up
            if (( _KT_GATE_B_SAME[k] && ! _KT_GATE_POKED )); then
                _KT_GATE_POKED=1; t0=$SECONDS
                sp=""; { read -r sp _ < "$_KT_GATE_OUT/seg-$n.pid"; } 2>/dev/null
                printf 'stop\n' > "$_KT_GATE_OUT/seg-$n.why"
                [[ "$sp" =~ ^[0-9]+$ ]] && kill -USR1 "$sp" 2>/dev/null
                _kt_gate_say "[WARN] segment $n: no answer to the stop in ${_KT_GATE_STOP_WAIT}s - signalled it directly"
            else
                break
            fi
        fi
        (( ++tick % _KT_GATE_HB_EVERY == 0 )) && _kt_gate_hb
    done
    # the stubs linger while the segment's last processes leave: bounded
    for (( i = 0; i < 100; i++ )); do kill -0 "$stub" 2>/dev/null || break; _kt_strays_nap 0.1; done
    kill -0 "$stub" 2>/dev/null || wait "$stub" 2>/dev/null
    for sp in "${_KT_GATE_RESCUES[@]}"; do
        for (( i = 0; i < 30; i++ )); do kill -0 "$sp" 2>/dev/null || break; _kt_strays_nap 0.1; done
        kill -0 "$sp" 2>/dev/null || wait "$sp" 2>/dev/null
    done
    _kt_gate_relay "$n"
    _KT_GATE_SEG_T1[k]=$EPOCHREALTIME
}

# kt_gate_collect K — per-runtime counts from its cells' result files
kt_gate_collect() {
    local k=$1 n=$(( $1 + 1 )) i idx f v
    local -A c=( [PASS]=0 [FAIL]=0 [ENV]=0 [TIMEOUT]=0 [STRAY]=0 [CRASH]=0 [NOTRUN]=0 [INTERRUPTED]=0 [UNSTARTED]=0 )
    local tp=0 tt=0 a b
    for (( i = 0; i < ${#_KT_GATE_SEL[@]}; i++ )); do
        idx=$(( k * ${#_KT_GATE_SEL[@]} + i + 1 ))
        printf -v f '%s/cells/%03d/result' "$_KT_GATE_OUT" "$idx"
        if _kt_gate_readkv "$f"; then
            v="${_KT_GATE_KV[verdict]:-CRASH}"
            [[ -n "${c[$v]+x}" && "$v" != UNSTARTED ]] || v=CRASH
            c[$v]=$(( c[$v] + 1 ))
            tp=$(( tp + ${_KT_GATE_KV[passed]:-0} )); tt=$(( tt + ${_KT_GATE_KV[total]:-0} ))
        else
            c[UNSTARTED]=$(( c[UNSTARTED] + 1 ))
        fi
    done
    local s=""
    _kt_gate_readkv "$_KT_GATE_OUT/seg-$n.result" && s="${_KT_GATE_KV[status]:-}"
    for v in PASS FAIL ENV TIMEOUT STRAY CRASH NOTRUN INTERRUPTED UNSTARTED; do
        _KT_GATE_TOT[$v]=$(( ${_KT_GATE_TOT[$v]:-0} + c[$v] ))
    done
    _KT_GATE_TOT[tp]=$(( ${_KT_GATE_TOT[tp]:-0} + tp )); _KT_GATE_TOT[tt]=$(( ${_KT_GATE_TOT[tt]:-0} + tt ))
    _kt_strays_ms "${_KT_GATE_SEG_T0[k]:-$EPOCHREALTIME}"; a=$REPLY
    _kt_strays_ms "${_KT_GATE_SEG_T1[k]:-$EPOCHREALTIME}"; b=$REPLY
    _kt_gate_hms $(( b - a ))
    printf -v "_KT_GATE_SUMLINE[$k]" 'gate %-*s: %d cells  %d PASS  %d FAIL  0 FLAKY  %d ENV  %d TIMEOUT  %d STRAY  %d CRASH  %d NOTRUN  tests %d/%d  %s' \
        "$_KT_GATE_VW" "${_KT_GATE_B_VER[k]}" "${#_KT_GATE_SEL[@]}" "${c[PASS]}" "${c[FAIL]}" "${c[ENV]}" "${c[TIMEOUT]}" \
        "${c[STRAY]}" "${c[CRASH]}" "${c[NOTRUN]}" "$tp" "$tt" "$REPLY"
    (( c[INTERRUPTED] > 0 )) && _KT_GATE_SUMLINE[k]+="  ${c[INTERRUPTED]} interrupted"
    (( c[UNSTARTED] > 0 )) && _KT_GATE_SUMLINE[k]+="  ${c[UNSTARTED]} not started"
    # a segment that died (no result, or killed) or ran without a watchdog
    if [[ -z "$s" ]]; then
        _KT_GATE_SEGFAIL+=( "segment $n (${_KT_GATE_B_VER[k]}) left no result: see seg-$n.log" )
    elif [[ "$s" == segment-killed ]] && (( ! _KT_GATE_SIG )); then
        _KT_GATE_SEGFAIL+=( "segment $n (${_KT_GATE_B_VER[k]}) was killed from outside: see seg-$n.log" )
    elif [[ "$s" == no-watchdog ]]; then
        _KT_GATE_SEGFAIL+=( "segment $n (${_KT_GATE_B_VER[k]}) stopped: its watchdog could not be (re)started: see seg-$n.log" )
    fi
    return 0
}

kt_gate_main() {
    local k
    _KT_GATE_ARGV=( "$@" )
    kt_gate_parse "$@"
    _KT_GATE_CYGPATH=""; command -v cygpath >/dev/null 2>&1 && _KT_GATE_CYGPATH=1
    _kt_gate_rt; _KT_GATE_RT="$REPLY"
    kt_gate_root
    kt_gate_resolve
    kt_gate_bashes
    _KT_GATE_HB_TICKS="${KT_GATE_HB_TICKS:-30}"; [[ "$_KT_GATE_HB_TICKS" =~ ^[1-9][0-9]*$ ]] || _KT_GATE_HB_TICKS=30
    _KT_GATE_HB_EVERY="${KT_GATE_HB_EVERY:-5}"; [[ "$_KT_GATE_HB_EVERY" =~ ^[1-9][0-9]*$ ]] || _KT_GATE_HB_EVERY=5
    _KT_GATE_STOP_WAIT="${KT_GATE_STOP_WAIT:-90}"; [[ "$_KT_GATE_STOP_WAIT" =~ ^[1-9][0-9]*$ ]] || _KT_GATE_STOP_WAIT=90
    _KT_GATE_SETSID="$(type -P setsid 2>/dev/null)"; _KT_GATE_PERL=""
    [[ -z "$_KT_GATE_SETSID" ]] && _KT_GATE_PERL="$(type -P perl 2>/dev/null)"
    # the parent watch (G0 amendment 6) and its opt-out: --nohup, or SIGHUP
    # ignored on entry (nohup) — a run detached on purpose outlives its parent
    _KT_GATE_WATCH=1 _KT_GATE_PP="$PPID" _KT_GATE_PPW=""
    [[ "$(trap -p HUP)" == *"''"* ]] && _KT_GATE_NOHUP=1
    (( _KT_GATE_NOHUP )) && _KT_GATE_WATCH=0
    { read -r _KT_GATE_PPW < "/proc/$PPID/winpid"; } 2>/dev/null
    [[ "$PPID" =~ ^[0-9]+$ ]] && (( PPID > 1 )) && [[ -n "$_KT_GATE_PPW" ]] || _KT_GATE_WATCH=0

    _KT_GATE_B_SAME=()
    for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
        _KT_GATE_B_SAME[k]=0; [[ "${_KT_GATE_B_RT[k]}" == "$_KT_GATE_RT" ]] && _KT_GATE_B_SAME[k]=1
    done
    kt_gate_out
    _kt_gate_mpath "$_KT_GATE_SELF"; _KT_GATE_SELFM="$REPLY"
    _KT_GATE_NCELLS=$(( ${#_KT_GATE_SEL[@]} * ${#_KT_GATE_B_PATH[@]} ))
    local s
    _KT_GATE_SW=8
    for s in "${_KT_GATE_SEL[@]}"; do (( ${#s} > _KT_GATE_SW )) && _KT_GATE_SW=${#s}; done
    _KT_GATE_VW=1
    for s in "${_KT_GATE_B_VER[@]}"; do (( ${#s} > _KT_GATE_VW )) && _KT_GATE_VW=${#s}; done
    _KT_GATE_SIG=0 _KT_GATE_SIGWHY="" _KT_GATE_STOPPED=0 _KT_GATE_POKED=0
    _KT_GATE_SEG_T0=() _KT_GATE_SEG_T1=() _KT_GATE_SUMLINE=() _KT_GATE_SEGFAIL=() _KT_GATE_RESCUES=()
    declare -gA _KT_GATE_TOT=()
    trap '_kt_gate_on_sig 143 "TERM"' TERM
    trap '_kt_gate_on_sig 130 "INT"' INT
    (( _KT_GATE_NOHUP )) || trap '_kt_gate_on_sig 129 "HUP"' HUP
    # Ctrl-Z (review R13): a suspended launcher would stop heartbeating and
    # its segment would stop the run 30 s later — not supported, ignored
    trap '_kt_gate_say "[WARN] suspending a gate is not supported (ignored); stop it with Ctrl-C / TERM"' TSTP
    # a dead stdout (parent gone) must not kill the launcher; a CAUGHT signal
    # (unlike an ignored one) is reset to default in the children
    trap ': SIGPIPE' PIPE
    _kt_strays_nap_open

    local st
    printf -v st '%(%Y-%m-%dT%H:%M:%S)T' -1
    _kt_gate_say "gate $st root=$_KT_GATE_ROOT out=$_KT_GATE_OUTM"
    kt_gate_repos
    _kt_gate_say "gate repos: $REPLY"
    local bl=""
    for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
        bl+="${bl:+  }${_KT_GATE_B_VER[k]} ${_KT_GATE_B_MIXED[k]}"
    done
    _kt_gate_say "gate bashes: $bl"
    _kt_gate_say "gate cells: $_KT_GATE_NCELLS = ${#_KT_GATE_B_PATH[@]} bash x ${#_KT_GATE_SEL[@]} suite(s) (${_KT_GATE_SEL[*]})  mode=$_KT_GATE_MODE cwd=$_KT_GATE_CWD timeout=${_KT_GATE_TIMEOUT}s${_KT_GATE_WORKERS:+ workers=$_KT_GATE_WORKERS}${_KT_GATE_ARGS[*]:+ args: ${_KT_GATE_ARGS[*]}}"
    (( _KT_GATE_ONE )) && _kt_gate_say "[WARN] one runtime only (no --bash, no KT_GATE_BASHES): $BASH_VERSION"
    if [[ -z "$_KT_GATE_SETSID$_KT_GATE_PERL" ]]; then
        for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
            [[ "${_KT_GATE_B_RT[k]}" == "$_KT_GATE_RT" ]] && { _kt_gate_say "[WARN] no setsid/perl: a same-runtime segment shares the caller's session (its stray checks see the caller's processes)"; break; }
        done
    fi
    if (( ! _KT_GATE_WATCH )); then
        if (( _KT_GATE_NOHUP )); then _kt_gate_say "gate: parent watch off (--nohup / SIGHUP ignored)"
        else _kt_gate_say "gate: parent watch off (no cygwin parent to watch)"; fi
    fi

    for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
        (( _KT_GATE_SIG )) && break
        kt_gate_spec "$k"
        kt_gate_segment_run "$k"
    done
    for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
        kt_gate_collect "$k"
    done
    for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
        _kt_gate_say "${_KT_GATE_SUMLINE[k]}"
    done
    for s in "${_KT_GATE_SEGFAIL[@]}"; do _kt_gate_say "[WARN] $s"; done

    local v rc hard=$(( ${_KT_GATE_TOT[FAIL]:-0} + ${_KT_GATE_TOT[TIMEOUT]:-0} + ${_KT_GATE_TOT[STRAY]:-0} + ${_KT_GATE_TOT[CRASH]:-0} + ${#_KT_GATE_SEGFAIL[@]} ))
    if (( _KT_GATE_SIG )); then
        v=INTERRUPTED; rc=$_KT_GATE_SIG
    elif (( hard > 0 )); then
        v=FAIL; rc=1
    elif (( ${_KT_GATE_TOT[ENV]:-0} > 0 )); then
        v=ENV; rc=3
    elif (( ${_KT_GATE_TOT[NOTRUN]:-0} == _KT_GATE_NCELLS )); then
        _kt_gate_say "[WARN] nothing ran: no cell found a test file"
        v=FAIL; rc=1
    elif (( ${_KT_GATE_TOT[PASS]:-0} + ${_KT_GATE_TOT[NOTRUN]:-0} == _KT_GATE_NCELLS )); then
        v=PASS; rc=0
    else
        v=FAIL; rc=1
    fi
    local mline
    printf -v mline '__GATE__:%s:%d:%d:%d:0:%d:%d:%d:%d:%d' "$v" "$_KT_GATE_NCELLS" "${_KT_GATE_TOT[PASS]:-0}" \
        $(( ${_KT_GATE_TOT[FAIL]:-0} + ${_KT_GATE_TOT[CRASH]:-0} )) "${_KT_GATE_TOT[ENV]:-0}" "${_KT_GATE_TOT[TIMEOUT]:-0}" \
        "${_KT_GATE_TOT[STRAY]:-0}" "${_KT_GATE_TOT[tp]:-0}" "${_KT_GATE_TOT[tt]:-0}"
    _kt_gate_say "gate $v  out=$_KT_GATE_OUTM"
    _kt_gate_say "$mline"
    if [[ "$v" == INTERRUPTED ]]; then
        [[ -e "$_KT_GATE_OUT/INTERRUPTED" ]] || printf 'launcher: %s\n' "$_KT_GATE_SIGWHY" >> "$_KT_GATE_OUT/INTERRUPTED"
    else
        printf '%s\n' "$mline" > "$_KT_GATE_OUT/FINISHED"
    fi
    _kt_strays_nap_close
    return "$rc"
}

# ===========================================================================
# SEGMENT (`gate.sh --segment SPEC`, in the runtime under test)
# ===========================================================================

# _kt_gate_seg_env — deny-by-default environment: unset every exported
# variable but PATH (and the shell's own PWD/SHLVL) and every exported
# function (fork-free: builtins into a file, mapfile — GATE_PLAN 4.2), then
# export the caller's whitelisted variables from the spec. (Both cygwin
# runtimes add MSYSTEM=MINGW64 to every process started without one — it is
# the runtime's, not the caller's, and cannot be removed.)
_kt_gate_seg_env() {
    local f="$KT_GATE_S_OUT/seg-$KT_GATE_S_SEG.env" n kv
    local -a names=() funcs=()
    compgen -e > "$f"; mapfile -t names < "$f"
    for n in "${names[@]}"; do
        case "$n" in
            PATH|PWD|SHLVL) ;;
            *) unset "$n" 2>/dev/null || export -n "$n" 2>/dev/null ;;
        esac
    done
    declare -Fx > "$f"; mapfile -t funcs < "$f"
    for n in "${funcs[@]}"; do unset -f "${n#declare -fx }" 2>/dev/null; done
    rm -f -- "$f"
    for kv in "${KT_GATE_S_ENV[@]}"; do export "$kv"; done
    # the target bash first: the runner's child `bash` is the same build
    export PATH="${BASH%/*}:$PATH"
}

_kt_gate_seg_usr1() { _KT_GATE_BRK=1; kt_suitejob_break; }

# _kt_gate_seg_why — REPLY = the watchdog's request ("" none)
_kt_gate_seg_why() {
    REPLY=""
    { IFS= read -r REPLY < "$_KT_GATE_F_WHY"; } 2>/dev/null
    if [[ -z "$REPLY" ]]; then
        if (( _KT_GATE_SEGSIG )); then REPLY="signal"
        elif [[ -e "$KT_GATE_S_OUT/STOP" ]]; then REPLY="stop"; fi
    fi
    return 0
}

# _kt_gate_seg_stopping — rc 0 when the segment must not start another cell
_kt_gate_seg_stopping() {
    [[ -e "$KT_GATE_S_OUT/STOP" ]] && return 0
    (( _KT_GATE_SEGSIG )) && return 0
    _kt_gate_seg_why
    [[ "$REPLY" == stop || "$REPLY" == stale ]]
}

# the shape of a line cygwin or bash itself prints on a fork failure
# ("      0 [main] bash 4242 dofork: ...", "bash: fork: retry: ...") — never
# the continuation of a test's [FAIL] message
declare -g _KT_GATE_RAW_RE='^[0-9]+ \[[^]]+\] |(^|/)[A-Za-z0-9_.-]*sh(\.exe)?: (line [0-9]+: )?fork: '

# _kt_gate_seg_scan_log LOG — builtins only:
#   _KT_GATE_FAILS  the [FAIL] messages; a message's continuation lines (a
#                   multi-line kt_test_fail) are part of its entry, joined by
#                   newlines (review R9). The runner's list of failed FILES
#                   is left out: the names in _KT_GATE_FFILES (the summary's
#                   `file` lines; any name, spaces too), without a summary
#                   `[FAIL] NNN_<anything>.sh`.
#   _KT_GATE_WARN   the count of [WARN] lines
#   _KT_GATE_SIGHIT the first fork-failure signature (KT_ENV_FORK_FAILURE_RE)
#                   in a RAW line — never in a test's own message ([FAIL]/
#                   [PASS]/[WARN] lines and their continuations: a test may
#                   talk about fork failures, ktests 035 does), but in the
#                   runner's own "source aborted" line (review R4)
_kt_gate_seg_scan_log() {
    local raw line esc=$'\e' pre post cont=0 sumb=0 nf=${#_KT_GATE_FFILES[@]} n
    local -a L=()
    _KT_GATE_FAILS=() _KT_GATE_WARN=0 _KT_GATE_SIGHIT=""
    { mapfile -t L < "$1"; } 2>/dev/null
    for raw in "${L[@]}"; do
        line="$raw"
        while [[ "$line" == *"$esc["* ]]; do
            pre="${line%%"$esc["*}" post="${line#*"$esc["}"
            post="${post#"${post%%[a-zA-Z]*}"}"; post="${post#?}"
            line="$pre$post"
        done
        line="${line//$'\r'/}"
        line="${line#"${line%%[![:space:]]*}"}"
        [[ "$line" == 'Total tests:'* ]] && { sumb=1; cont=0; continue; }
        if [[ "$line" == '[FAIL]'* ]]; then
            cont=0
            if (( nf > 0 )); then
                [[ -n "${_KT_GATE_FFILES["${line#'[FAIL] '}"]+x}" ]] && continue
            else
                [[ "$line" =~ ^\[FAIL\]\ [0-9]{3}_.*\.sh$ ]] && continue
            fi
            (( sumb )) && continue
            _KT_GATE_FAILS+=( "$line" ); cont=1
            if [[ -z "$_KT_GATE_SIGHIT" && "$line" == '[FAIL] '*': source aborted ('* && "$line" =~ $KT_ENV_FORK_FAILURE_RE ]]; then
                _KT_GATE_SIGHIT="${BASH_REMATCH[0]}"
            fi
            continue
        fi
        if [[ "$line" == '[WARN]'* ]]; then
            _KT_GATE_WARN=$(( _KT_GATE_WARN + 1 )); cont=0; continue
        fi
        if [[ "$line" == *'[FAIL]'* || "$line" == *'[PASS]'* || "$line" == *'[WARN]'* ]]; then
            cont=0; continue
        fi
        if (( cont && ! sumb )) && [[ -n "$line" && ! "$line" =~ ^\[[A-Z]+\] && ! "$line" =~ $_KT_GATE_RAW_RE ]]; then
            n=$(( ${#_KT_GATE_FAILS[@]} - 1 ))
            _KT_GATE_FAILS[n]+=$'\n'"$line"
            continue
        fi
        cont=0
        if [[ -z "$_KT_GATE_SIGHIT" && "$line" =~ $KT_ENV_FORK_FAILURE_RE ]]; then
            _KT_GATE_SIGHIT="${BASH_REMATCH[0]}"
        fi
    done
    return 0
}

# _kt_gate_seg_attempt C A — run attempt A of cell C (0-based index into the
# spec arrays); sets _KT_GATE_A_{VERDICT,REASON,RC,T,P,F,MS,STRAYS}; rc 2 when
# the segment must stop (the cell was interrupted)
_kt_gate_seg_attempt() {
    local c=$1 a=$2 idx="${KT_GATE_S_C_IDX[$1]}" suite="${KT_GATE_S_C_SUITE[$1]}" cd m wd jr why="" t0 t1
    local sum log nrow brk=0 timedout=0 stray=0 v="" r="" tt=0 pp=0 ff=0 src="" l nenv=0 envf=""
    local -a S=()
    printf -v cd '%s/cells/%03d' "$KT_GATE_S_OUT" "$idx"
    printf -v m '%s/cells/%03d' "$KT_GATE_S_OUTM" "$idx"
    (( a > 1 )) && rm -rf -- "$cd/home" "$cd/tmp" "$cd/etc" "$cd/cwd" "$cd/ckk" 2>/dev/null
    mkdir -p -- "$cd/home" "$cd/tmp" "$cd/etc" "$cd/cwd" "$cd/ckk"
    log="$cd/log.txt" sum="$cd/summary"
    rm -f -- "$sum" 2>/dev/null
    export HOME="$cd/home" TMPDIR="$cd/tmp" TMP="$cd/tmp" TEMP="$cd/tmp"
    export USERPROFILE="$m/home" ProgramData="$m/etc" __KK_CFG_ETC="$cd/etc" KKLASS_CKK_DIR="$cd/ckk"
    export KT_SUMMARY_FILE="$sum"
    wd="$cd/cwd"
    [[ "${KT_GATE_S_C_CWD[c]}" == suite ]] && wd="$KT_GATE_S_ROOT/$suite/tests"
    local -a cmd=( "$BASH" "$KT_GATE_S_ROOT/$suite/tests/tests.sh" --mode "${KT_GATE_S_C_MODE[c]}" )
    [[ -n "$KT_GATE_S_WORKERS" ]] && cmd+=( --workers "$KT_GATE_S_WORKERS" )
    cmd+=( "${KT_GATE_S_ARGS[@]}" )
    : > "$log"
    nrow=${#KT_SUITEJOB_STRAY_ROWS[@]}
    # a timeout request of the previous cell that came after its end: done
    _kt_gate_seg_why
    [[ "$REPLY" == timeout\ * ]] && printf '%s\n' "$REPLY" > "$_KT_GATE_F_ACK"
    _kt_strays_ms "$EPOCHREALTIME"; t0=$REPLY
    printf 'run %s %s\n' "$idx" "$(( EPOCHSECONDS + KT_GATE_S_TIMEOUT ))" > "$_KT_GATE_F_CUR"
    KT_SUITEJOB_SINCE="$EPOCHREALTIME"     # this cell's stray window
    _KT_GATE_BRK=0
    if builtin cd -- "$wd" 2>/dev/null; then
        unset OLDPWD    # the cd's previous dir is not the cell's business
        kt_suitejob_run "cell $idx" "${cmd[@]}" < /dev/null >> "$log" 2>&1; jr=$?
    else
        printf 'gate: cannot cd to %s\n' "$wd" >> "$log"; jr=0; KT_SUITEJOB_RC=125
    fi
    while (( jr == 1 )); do
        _kt_gate_seg_why; why="$REPLY"
        case "$why" in "timeout $idx"|stop|stale|signal) break ;; esac
        # not for this cell (a late USR1 for the previous one): keep waiting
        printf '%s\n' "$why" > "$_KT_GATE_F_ACK"
        _KT_GATE_BRK=0
        wait "$KT_SUITEJOB_PID"; KT_SUITEJOB_RC=$?
        if (( _KT_GATE_BRK )); then jr=1; else jr=0; KT_SUITEJOB_PID=""; fi
    done
    if (( jr == 1 )); then
        # the watchdog's (or a signal's) request broke the wait: stop the cell
        printf '%s\n' "$why" > "$_KT_GATE_F_ACK"
        kt_suitejob_signal 143 >> "$log" 2>&1
        brk=1
        [[ "$why" == "timeout $idx" ]] && timedout=1
    fi
    _kt_strays_ms "$EPOCHREALTIME"; t1=$REPLY
    printf 'idle\n' > "$_KT_GATE_F_CUR"
    # a request that came as the cell ended (read AFTER `idle`: the watchdog
    # signals only while a cell runs, review R8): acknowledge it — a stop
    # then ends the segment after this cell
    _kt_gate_seg_why
    case "$REPLY" in "timeout $idx"|stop|stale) printf '%s\n' "$REPLY" > "$_KT_GATE_F_ACK" ;; esac
    builtin cd -- "$KT_GATE_S_OUT" 2>/dev/null
    unset KT_SUMMARY_FILE
    _KT_GATE_A_RC=$KT_SUITEJOB_RC
    _KT_GATE_A_MS=$(( t1 - t0 ))
    # strays of this attempt (window = its start)
    kt_suitejob_strays "cell $idx" >> "$cd/strays.txt" 2>&1 || stray=1
    _KT_GATE_A_STRAYS=$(( ${#KT_SUITEJOB_STRAY_ROWS[@]} - nrow ))
    _KT_GATE_A_STRAYROWS=( "${KT_SUITEJOB_STRAY_ROWS[@]:nrow}" )
    # results: the summary first (its failed files, its ENV files), then the log
    _KT_GATE_FFILES=()
    { mapfile -t S < "$sum"; } 2>/dev/null
    if [[ "${S[0]:-}" =~ ^([0-9]+)\ ([0-9]+)\ ([0-9]+)\ (-?[0-9]+)$ ]]; then
        tt=${BASH_REMATCH[1]} pp=${BASH_REMATCH[2]} ff=${BASH_REMATCH[3]}
        for l in "${S[@]:1}"; do
            case "$l" in
                "error "*) [[ -z "$src" ]] && src="${l#error }" ;;
                "file "*) _KT_GATE_FFILES["${l#file }"]=1 ;;
                "env "*) nenv=$(( nenv + 1 )); [[ -z "$envf" ]] && envf="${l#env }" ;;
            esac
        done
    else
        src=none
    fi
    _kt_gate_seg_scan_log "$log"
    _KT_GATE_A_T=$tt _KT_GATE_A_P=$pp _KT_GATE_A_F=$ff
    if (( brk && ! timedout )); then
        v=INTERRUPTED
        case "$why" in
            stop) r="the gate was stopped" ;;
            stale) r="the launcher is gone (heartbeat stale)" ;;
            *) r="the segment got a signal" ;;
        esac
    elif (( stray )); then v=STRAY; r="$_KT_GATE_A_STRAYS stray process(es), stopped"
    elif (( timedout )); then v=TIMEOUT; r="timeout ${KT_GATE_S_TIMEOUT}s, group stopped"
    elif [[ "$src" == no-test-files ]]; then v=NOTRUN; r="no test files"
    elif [[ -n "$src" ]]; then
        # the runner did not finish (review R5): a fork failure in its raw
        # output, or no summary and rc 125-127 (it could not even start), is
        # the machine — ENV, re-run once
        v=CRASH
        if [[ "$src" == none ]]; then r="no summary from the runner (rc $_KT_GATE_A_RC)"; else r="runner: error $src (rc $_KT_GATE_A_RC)"; fi
        if [[ -n "$_KT_GATE_SIGHIT" ]]; then v=ENV; r="crash with a fork failure: $_KT_GATE_SIGHIT; $r"
        elif [[ "$src" == none ]] && (( _KT_GATE_A_RC >= 125 && _KT_GATE_A_RC <= 127 )); then v=ENV; r="the runner could not start; $r"; fi
    elif (( _KT_GATE_A_RC != 0 || ff > 0 || pp < tt )); then
        v=FAIL
        # ENV: the RUNNER saw a file die of a fork failure (`env` lines of the
        # summary), or a raw fork-failure line is in the log (review R4)
        if (( nenv > 0 )); then v=ENV; r="fork failure in $nenv file(s) (runner): $envf"
        elif [[ -n "$_KT_GATE_SIGHIT" ]]; then v=ENV; r="fork failure: $_KT_GATE_SIGHIT"; fi
    else
        v=PASS
    fi
    _KT_GATE_A_VERDICT=$v _KT_GATE_A_REASON="$r"
    printf '%s\n' "${_KT_GATE_FAILS[@]}" > "$cd/fails.txt"
    [[ "$v" == INTERRUPTED ]] && return 2
    return 0
}

# _kt_gate_seg_result C ATTEMPTS ATT1 — write cells/NNN/result
_kt_gate_seg_result() {
    local c=$1 idx="${KT_GATE_S_C_IDX[$1]}" f
    printf -v f '%s/cells/%03d/log.txt' "$KT_GATE_S_OUT" "$idx"
    _kt_gate_put "${f%/log.txt}/result" "idx=$idx" "bash_version=$_KT_GATE_VER" "bash_path=$KT_GATE_S_BASH" \
        "mode=${KT_GATE_S_C_MODE[c]}" "cwd=${KT_GATE_S_C_CWD[c]}" "suite=${KT_GATE_S_C_SUITE[c]}" \
        "repeat=${KT_GATE_S_C_REP[c]}" "verdict=$_KT_GATE_A_VERDICT" "rc=$_KT_GATE_A_RC" \
        "total=$_KT_GATE_A_T" "passed=$_KT_GATE_A_P" "failed=$_KT_GATE_A_F" "warn=$_KT_GATE_WARN" \
        "fail_lines=${#_KT_GATE_FAILS[@]}" "strays=$_KT_GATE_A_STRAYS" "attempts=$2" \
        "duration_ms=$_KT_GATE_C_MS" "log=${f#"$KT_GATE_S_OUT"/}" "reason=${_KT_GATE_A_REASON//$'\n'/ }" \
        "attempt1=$3"
}

# _kt_gate_seg_emit C — the cell's progress line(s) into seg-N.lines
_kt_gate_seg_emit() {
    local c=$1 idx="${KT_GATE_S_C_IDX[$1]}" counts extra="" l n i i3
    printf -v i3 %03d "$idx"
    local -a out=()
    _KT_GATE_CMODE="${KT_GATE_S_C_MODE[c]}" _KT_GATE_CCWD="${KT_GATE_S_C_CWD[c]}" _KT_GATE_CSUITE="${KT_GATE_S_C_SUITE[c]}"
    counts="$_KT_GATE_A_P/$_KT_GATE_A_T"
    if [[ "$_KT_GATE_A_VERDICT" != PASS ]]; then
        printf -v extra '  log=cells/%03d/log.txt' "$idx"
    fi
    [[ -n "$_KT_GATE_A_REASON" ]] && extra+="  ($_KT_GATE_A_REASON)"
    [[ -n "$_KT_GATE_ATT1" ]] && extra+="  (attempt 1: ${_KT_GATE_ATT1%% *}, re-run once)"
    _kt_gate_line "$idx" "$_KT_GATE_A_VERDICT" "$counts" "$_KT_GATE_WARN" "$_KT_GATE_C_MS" "$extra"
    out+=( "$REPLY" )
    case "$_KT_GATE_A_VERDICT" in
        FAIL|ENV)
            # the messages with their continuation lines, 5 lines in all
            local shown=0 total=0 e
            local -a ml=()
            n=${#_KT_GATE_FAILS[@]}
            for (( i = 0; i < n; i++ )); do
                mapfile -t ml <<< "${_KT_GATE_FAILS[i]}"
                for e in "${ml[@]}"; do
                    total=$(( total + 1 ))
                    (( shown < 5 )) && { out+=( "        ${e:0:200}" ); shown=$(( shown + 1 )); }
                done
            done
            (( total > shown )) && out+=( "        ($n [FAIL] message(s), $total lines, first 5 shown: cells/$i3/fails.txt)" ) ;;
        STRAY)
            for (( i = 0; i < ${#_KT_GATE_A_STRAYROWS[@]} && i < 5; i++ )); do out+=( "        stray: ${_KT_GATE_A_STRAYROWS[i]:0:200}" ); done ;;
        CRASH)
            local -a L=()
            { mapfile -t L < "$KT_GATE_S_OUT/cells/$i3/log.txt"; } 2>/dev/null
            n=${#L[@]}
            for (( i = n > 3 ? n - 3 : 0; i < n; i++ )); do out+=( "        log: ${L[i]:0:200}" ); done ;;
    esac
    printf '%s\n' "${out[@]}" >> "$_KT_GATE_F_LINES"
}

# _kt_gate_seg_cell C — a cell: attempt 1, an ENV retry, result, line,
# sandbox removal. rc 2: the segment must stop
_kt_gate_seg_cell() {
    local c=$1 idx="${KT_GATE_S_C_IDX[$1]}" cd a=1 att=1 rc
    printf -v cd '%s/cells/%03d' "$KT_GATE_S_OUT" "$idx"
    mkdir -p -- "$cd"
    _KT_GATE_ATT1=""
    _kt_gate_seg_attempt "$c" 1; rc=$?
    _KT_GATE_C_MS=$_KT_GATE_A_MS
    if (( rc == 0 )) && [[ "$_KT_GATE_A_VERDICT" == ENV ]] && ! _kt_gate_seg_stopping; then
        _KT_GATE_ATT1="ENV rc=$_KT_GATE_A_RC total=$_KT_GATE_A_T passed=$_KT_GATE_A_P failed=$_KT_GATE_A_F ms=$_KT_GATE_A_MS ($_KT_GATE_A_REASON)"
        mv -f -- "$cd/log.txt" "$cd/log.1.txt" 2>/dev/null
        mv -f -- "$cd/summary" "$cd/summary.1" 2>/dev/null
        mv -f -- "$cd/fails.txt" "$cd/fails.1.txt" 2>/dev/null
        att=2
        _kt_gate_seg_attempt "$c" 2; rc=$?
        _KT_GATE_C_MS=$(( _KT_GATE_C_MS + _KT_GATE_A_MS ))
    fi
    _kt_gate_seg_result "$c" "$att" "$_KT_GATE_ATT1"
    _kt_gate_seg_emit "$c"
    if [[ "$_KT_GATE_A_VERDICT" == PASS ]] && (( ! KT_GATE_S_KEEP )); then
        rm -rf -- "$cd/home" "$cd/tmp" "$cd/etc" "$cd/cwd" "$cd/ckk" 2>/dev/null
    fi
    return "$rc"
}

# _kt_gate_seg_wd_start — start the watchdog: an EXEC'd bash (survives a tree
# kill of this one, G0); _KT_GATE_WD = its pid
_kt_gate_seg_wd_start() {
    ( exec "$BASH" "$KT_GATE_S_SELF" --watchdog "$_KT_GATE_SPEC" "$$" "$_KT_GATE_SEG_START" ) < /dev/null &
    _KT_GATE_WD=$!
}

# _kt_gate_seg_wd_check — before the first cell and between cells (review
# R6): a watchdog (the one in seg-N.wdpid — maybe the launcher's rescue — or
# this segment's own) must be alive and have announced itself; else it is
# started again, once. rc 1: no watchdog — the segment must not run a cell.
_kt_gate_seg_wd_check() {
    local i j p
    _kt_strays_nap_open
    for (( i = 0; i < 2; i++ )); do
        for (( j = 0; j < 50; j++ )); do
            p=""; { read -r p < "$_KT_GATE_F_WDPID"; } 2>/dev/null
            if [[ "$p" =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null; then _kt_strays_nap_close; return 0; fi
            kill -0 "$_KT_GATE_WD" 2>/dev/null || break      # ours is gone: no point waiting
            _kt_strays_nap 0.1
        done
        (( _KT_GATE_WD_RESPAWN++ >= 1 )) && break
        printf '[WARN] segment %s: its watchdog is gone - started again\n' "$KT_GATE_S_SEG" >> "$_KT_GATE_F_LINES"
        rm -f -- "$_KT_GATE_F_WDPID"
        _kt_gate_seg_wd_start
    done
    _kt_strays_nap_close
    return 1
}

kt_gate_segment_main() {
    local spec="$1" c ran=0 status=done n f idx k nb
    [[ "${KT_GATE_S_VERSION:-}" == 1 && -d "${KT_GATE_S_OUT:-}" ]] || { printf 'gate segment: bad spec %s\n' "$spec" >&2; return 3; }
    n=$KT_GATE_S_SEG
    _KT_GATE_SPEC="$spec"
    _KT_GATE_SEG_START=$EPOCHREALTIME
    _KT_GATE_VER="${BASH_VERSION%%(*}"
    _KT_GATE_F_LINES="$KT_GATE_S_OUT/seg-$n.lines" _KT_GATE_F_CUR="$KT_GATE_S_OUT/seg-$n.cur"
    _KT_GATE_F_WHY="$KT_GATE_S_OUT/seg-$n.why" _KT_GATE_F_ACK="$KT_GATE_S_OUT/seg-$n.ack"
    _KT_GATE_F_RES="$KT_GATE_S_OUT/seg-$n.result" _KT_GATE_F_WDPID="$KT_GATE_S_OUT/seg-$n.wdpid"
    _KT_GATE_BRK=0 _KT_GATE_SEGSIG=0 _KT_GATE_WD_RESPAWN=0
    local sid="?" wp="?"
    { read -r sid < "/proc/$$/sid"; read -r wp < "/proc/$$/winpid"; } 2>/dev/null
    # pid winpid session start: for the launcher (tree-kill tests, a rescue
    # watchdog) and the watchdog (whose session to stop)
    printf '%s %s %s %s\n' "$$" "$wp" "$sid" "$_KT_GATE_SEG_START" > "$KT_GATE_S_OUT/seg-$n.pid"
    printf 'gate segment %s: bash %s pid %s session %s, %s cell(s)\n' "$n" "$BASH_VERSION" "$$" \
        "$sid" "${#KT_GATE_S_C_IDX[@]}"
    _kt_gate_seg_env
    printf 'idle\n' > "$_KT_GATE_F_CUR"
    : > "$_KT_GATE_F_LINES"
    trap _kt_gate_seg_usr1 USR1
    trap '_KT_GATE_SEGSIG=143; _kt_gate_seg_usr1' TERM
    trap '_KT_GATE_SEGSIG=130; _kt_gate_seg_usr1' INT
    trap '_KT_GATE_SEGSIG=129; _kt_gate_seg_usr1' HUP
    KT_SUITEJOB_BEFORE="(the segment's start)"
    kt_suitejob_init "$_KT_GATE_SEG_START"
    _kt_gate_seg_wd_start
    for (( c = 0; c < ${#KT_GATE_S_C_IDX[@]}; c++ )); do
        if _kt_gate_seg_stopping; then status=stopped; break; fi
        if ! _kt_gate_seg_wd_check; then
            status=no-watchdog
            printf '[WARN] segment %s: no watchdog (it could not be started again) - no further cell runs\n' "$n" >> "$_KT_GATE_F_LINES"
            break
        fi
        _kt_gate_seg_cell "$c"; k=$?
        ran=$(( ran + 1 ))
        (( k == 2 )) && { status=stopped; break; }
    done
    # no cell runs any more: the watchdog sends no USR1 (they only break a
    # cell's wait) and a pending request is acknowledged, so the naps of the
    # final stray check are never cut short (review R8)
    printf 'final\n' > "$_KT_GATE_F_CUR"
    _kt_gate_seg_why
    [[ -n "$REPLY" && "$REPLY" != signal ]] && printf '%s\n' "$REPLY" > "$_KT_GATE_F_ACK"
    # the final check: anything of this segment's cells still alive (window
    # = the segment's start; attributed to the cell running when it started)
    KT_SUITEJOB_SINCE="$_KT_GATE_SEG_START"; KT_SUITEJOB_CUR=""
    nb=${#KT_SUITEJOB_STRAY_ROWS[@]}
    if ! kt_suitejob_strays "the segment's end" >> "$KT_GATE_S_OUT/seg-$n.strays.txt" 2>&1; then
        for (( c = 0; c < ran; c++ )); do
            idx="${KT_GATE_S_C_IDX[c]}"
            [[ -n "${KT_SUITEJOB_STRAY_LABELS["cell $idx"]+x}" ]] || continue
            printf -v f '%s/cells/%03d/result' "$KT_GATE_S_OUT" "$idx"
            _kt_gate_readkv "$f" || continue
            [[ "${_KT_GATE_KV[verdict]}" == STRAY || "${_KT_GATE_KV[verdict]}" == INTERRUPTED ]] && continue
            sed -i "s|^verdict=.*|verdict=STRAY|; s|^reason=.*|reason=stray process(es) found by the segment's final check, stopped|" "$f"
            _KT_GATE_CMODE="${KT_GATE_S_C_MODE[c]}" _KT_GATE_CCWD="${KT_GATE_S_C_CWD[c]}" _KT_GATE_CSUITE="${KT_GATE_S_C_SUITE[c]}"
            _kt_gate_line "$idx" STRAY "${_KT_GATE_KV[passed]}/${_KT_GATE_KV[total]}" "${_KT_GATE_KV[warn]:-0}" \
                "${_KT_GATE_KV[duration_ms]:-0}" "  (found by the segment's final check, stopped)"
            printf '%s\n' "$REPLY" >> "$_KT_GATE_F_LINES"
        done
        printf '[WARN] segment %s final check: %s\n' "$n" "${KT_SUITEJOB_STRAY_ROWS[*]:nb}" >> "$_KT_GATE_F_LINES"
    fi
    if [[ "$status" == stopped ]]; then
        _kt_gate_seg_why
        [[ "$REPLY" == stale ]] && printf 'segment %s: the launcher is gone (heartbeat stale)\n' "$n" >> "$KT_GATE_S_OUT/INTERRUPTED"
        (( _KT_GATE_SEGSIG )) && printf 'segment %s: signal (exit %s)\n' "$n" "$_KT_GATE_SEGSIG" >> "$KT_GATE_S_OUT/INTERRUPTED"
    fi
    _kt_gate_put "$_KT_GATE_F_RES" "status=$status" "cells_run=$ran" "cells=${#KT_GATE_S_C_IDX[@]}" \
        "bash_version=$_KT_GATE_VER" "strays_final=$(( ${#KT_SUITEJOB_STRAY_ROWS[@]} - nb ))"
    kill -TERM "$_KT_GATE_WD" 2>/dev/null
    wait "$_KT_GATE_WD" 2>/dev/null
    return 0
}

# _kt_gate_spec_native — the spec's mixed paths (C:/...) in this runtime's
# spelling, one cygpath for all three; KT_GATE_S_OUTM keeps the mixed OUT
_kt_gate_spec_native() {
    local -a L=()
    KT_GATE_S_OUTM="$KT_GATE_S_OUT"
    if command -v cygpath >/dev/null 2>&1; then
        mapfile -t L < <(cygpath -u -- "$KT_GATE_S_OUT" "$KT_GATE_S_ROOT" "$KT_GATE_S_SELF" 2>/dev/null)
        if (( ${#L[@]} == 3 )); then
            KT_GATE_S_OUT="${L[0]%/}" KT_GATE_S_ROOT="${L[1]%/}" KT_GATE_S_SELF="${L[2]}"
        fi
    fi
}

# ===========================================================================
# WATCHDOG (`gate.sh --watchdog SPEC MAINPID SEGSTART`: exec'd by the segment,
# or started by the launcher as a rescue when the segment's went silent)
# ===========================================================================

kt_gate_watchdog() {
    local main="$1" since="$2" n="$KT_GATE_S_SEG" o="$KT_GATE_S_OUT" miss=0 why="" new ack cur sid=""
    local mark="$o/seg-$n.mark.$$" fwhy="$o/seg-$n.why" fack="$o/seg-$n.ack" fcur="$o/seg-$n.cur" res="$o/seg-$n.result"
    local wdhb="$o/seg-$n.wdhb"
    trap 'rm -f -- "$mark"; exit 0' TERM
    trap '' INT HUP USR1
    [[ -e "$res" ]] && exit 0
    { read -r _ _ sid _ < "$o/seg-$n.pid"; } 2>/dev/null
    printf '%s\n' "$$" > "$o/seg-$n.wdpid"
    _kt_strays_nap_open
    : > "$mark"
    while :; do
        _kt_strays_nap 1
        : > "$wdhb"                         # alive (the launcher and the segment look)
        [[ -e "$res" ]] && { rm -f -- "$mark"; exit 0; }
        if ! kill -0 "$main" 2>/dev/null; then
            [[ -e "$res" ]] || _kt_gate_wd_killed "$since" "$sid"
            rm -f -- "$mark"
            exit 0
        fi
        if [[ "$o/hb" -nt "$mark" ]]; then : > "$mark"; miss=0; else miss=$(( miss + 1 )); fi
        cur=""; { IFS= read -r cur < "$fcur"; } 2>/dev/null
        new=""
        if [[ -e "$o/STOP" ]]; then
            new=stop
        elif (( miss >= KT_GATE_S_HB_TICKS )); then
            new=stale
        elif [[ "$cur" =~ ^run\ ([0-9]+)\ ([0-9]+)$ ]] && (( EPOCHSECONDS >= BASH_REMATCH[2] )); then
            new="timeout ${BASH_REMATCH[1]}"
        fi
        if [[ -n "$new" && "$new" != "$why" && "$why" != stop && "$why" != stale ]]; then
            why="$new"
            printf '%s\n' "$why" > "$fwhy"
        fi
        # USR1 only breaks a cell's `wait`: only while a cell runs, a timeout
        # only for the cell that still runs (review R8); repeated until acked
        [[ -n "$why" && "$cur" == "run "* ]] || continue
        [[ "$why" == timeout\ * && "$cur" != "run ${why#timeout } "* ]] && continue
        ack=""; { IFS= read -r ack < "$fack"; } 2>/dev/null
        [[ "$ack" != "$why" ]] && kill -USR1 "$main" 2>/dev/null
    done
}

# _kt_gate_wd_killed SINCE SID — the segment's main is gone (a tree kill):
# stop what is left of its cells (every detached process of the segment's
# session SID since its start — the cell's tree first gets TERM at its root:
# ktests.sh stops its own group), write the running cell's result and the
# segment's. One watchdog does it (a rescue may be alive too): a lock dir.
_kt_gate_wd_killed() {
    local since="$1" sid="${2:-self}" n="$KT_GATE_S_SEG" o="$KT_GATE_S_OUT" cur="" idx="" c f left=0 i3
    mkdir -- "$o/seg-$n.killed" 2>/dev/null || return 0
    [[ "$sid" =~ ^[0-9]+$ ]] || sid=self
    { IFS= read -r cur < "$o/seg-$n.cur"; } 2>/dev/null
    printf 'gate watchdog %s: the segment main is gone (cur: %s) - stopping its cells (session %s)\n' "$n" "${cur:-?}" "$sid"
    kt_strays_stop --session "$sid" --since "$since" || left=$RESULT
    (( left > 0 )) && { printf 'gate watchdog %s: %s process(es) LEFT\n' "$n" "$left"; kt_strays_print '    '; }
    if [[ "$cur" =~ ^run\ ([0-9]+) ]]; then
        idx="${BASH_REMATCH[1]}"
        printf -v f '%s/cells/%03d/result' "$o" "$idx"; printf -v i3 %03d "$idx"
        for (( c = 0; c < ${#KT_GATE_S_C_IDX[@]}; c++ )); do [[ "${KT_GATE_S_C_IDX[c]}" == "$idx" ]] && break; done
        if [[ ! -e "$f" ]] && (( c < ${#KT_GATE_S_C_IDX[@]} )); then
            _KT_GATE_VER="${BASH_VERSION%%(*}"
            _kt_gate_put "$f" "idx=$idx" "bash_version=$_KT_GATE_VER" "bash_path=$KT_GATE_S_BASH" \
                "mode=${KT_GATE_S_C_MODE[c]}" "cwd=${KT_GATE_S_C_CWD[c]}" "suite=${KT_GATE_S_C_SUITE[c]}" \
                "repeat=${KT_GATE_S_C_REP[c]}" "verdict=INTERRUPTED" "rc=" "total=0" "passed=0" "failed=0" \
                "warn=0" "fail_lines=0" "strays=$left" "attempts=1" "duration_ms=0" \
                "log=cells/$i3/log.txt" "reason=segment-killed" "attempt1="
            _KT_GATE_CMODE="${KT_GATE_S_C_MODE[c]}" _KT_GATE_CCWD="${KT_GATE_S_C_CWD[c]}" _KT_GATE_CSUITE="${KT_GATE_S_C_SUITE[c]}"
            _kt_gate_line "$idx" INTERRUPTED "-" 0 0 "  (the segment was killed; its cells stopped by the watchdog)"
            printf '%s\n' "$REPLY" >> "$o/seg-$n.lines"
        fi
    fi
    printf 'segment %s: segment-killed (the watchdog stopped its cells)\n' "$n" >> "$o/INTERRUPTED"
    _kt_gate_put "$o/seg-$n.result" "status=segment-killed" "cells_run=?" "cells=${#KT_GATE_S_C_IDX[@]}" \
        "bash_version=${BASH_VERSION%%(*}" "strays_final=$left"
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        --segment)
            [[ -r "${2:-}" ]] || { printf 'gate: --segment needs a spec file\n' >&2; exit 2; }
            source "$2" || exit 2
            _kt_gate_spec_native
            kt_gate_segment_main "$2"
            exit $?
            ;;
        --watchdog)
            [[ -r "${2:-}" ]] || exit 2
            source "$2" || exit 2
            _kt_gate_spec_native
            kt_gate_watchdog "${3:-}" "${4:-}"
            exit 0
            ;;
        *)
            kt_gate_main "$@"
            exit $?
            ;;
    esac
fi
