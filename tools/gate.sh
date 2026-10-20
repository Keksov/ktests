#!/usr/bin/env bash
# gate.sh — the phase gate (ktests/GATE_PLAN.md): run test suites under one or
# more bash runtimes, every suite as a hermetic CELL of its own, and report a
# line per cell, a summary per runtime and one machine line.
#
#   gate.sh [options] SUITE... [-- ARGS...]
#   gate.sh [options] --changed [SUITE...] [-- ARGS...]
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
#   --mode threaded|single|both  the runner mode of the cells (default
#                   threaded; both = a cell per mode)
#   --workers N     the runner's --workers
#   --cwd neutral|suite|both     the cell's working dir: an empty dir of its
#                   own (default), the suite's tests/ dir, or a cell for each
#   --repeat N      every cell N times (1-9999; the repeat# is a column, the
#                   line shows SUITE#R). A runtime's cells run in the order
#                   repeat > suite > mode > cwd.
#   --timeout SEC   per cell (default 1800): the cell's group is stopped,
#                   verdict TIMEOUT
#   --rerun-failed N  (DG7, default 0 = off) after a cell FAILs (not ENV,
#                   TIMEOUT, STRAY, CRASH): exactly its failed files (the
#                   summary's `file NNN_Name.sh` lines; `-n` by their numbers,
#                   appended after ARGS — the runner takes the last -n), same
#                   mode and cwd, each attempt in a fresh sandbox of its own
#                   (cells/NNN/rerun-R/), up to N times. A rerun in which every
#                   selected test passes -> FLAKY (never PASS); a rerun that
#                   leaves a process -> STRAY; else the cell stays FAIL. A
#                   failed file without a number: no rerun (reason). The
#                   cell's counts and [FAIL] lines stay those of its FULL run.
#   --changed       (DG6) select the suites the UNCOMMITTED changes touch —
#                   `git status --porcelain -uall` (staged, unstaged,
#                   untracked) of the root and of every submodule in
#                   .gitmodules, plus the files of a submodule whose commit
#                   differs from the one the root's HEAD records: a path under
#                   kkore/ kklass/ ktests/ tests/ or kbool.sh -> all suites;
#                   kcl/tests/... -> kcl; kcl/DIR/... -> kcl/DIR (*.md too);
#                   a unit file (kcl/DIR/X.sh with `kk.unit`; a deleted one
#                   too) -> kcl as well; the units of DIR are TOUCHED by a
#                   change in kcl/DIR outside DIR/tests/ that is not *.md, a
#                   unit whose unit file has `kk.uses [--optional] U` for a
#                   touched or affected U is AFFECTED (transitively), and the
#                   suite of every affected unit and every suite with another
#                   script using one (a test file, a bench.sh its tests run:
#                   any kcl/DIR/**.sh that is no unit file) is selected; other
#                   paths select nothing. Named SUITEs are added (union). The
#                   selection and each suite's reason are printed before the
#                   first cell (and go to summary.json). Nothing changed — or
#                   nothing the changes select — and no SUITE named: `[WARN]
#                   nothing changed` (or `... select no suite`), exit 0, no
#                   OUT, no cell, no machine line. The root must be the top of
#                   a git work tree (else rc 2).
#   --compare LAST|DIR|FILE.tsv  compare this run's cells.tsv with another
#                   run's: DIR = DIR/cells.tsv, else the file — missing,
#                   empty, not a gate cells.tsv, a garbled row (field count,
#                   counts not numbers of <= 18 digits) -> usage error, rc 2.
#                   LAST = the newest FINISHED run with a cells.tsv under the
#                   DEFAULT OUT root PRIVATE_TEMP/kt-gate — ONE root for both
#                   runtimes (see --out) —, by its
#                   marker's start stamp, a tie by the dir name (the later
#                   wins); an unreadable candidate is skipped (a note), none
#                   left -> `[WARN] --compare LAST: no base (...)` and the
#                   run goes on without a compare. Read before anything runs
#                   (pure bash, by the header's column names). Over the keys
#                   (bash version, mode, cwd, suite) THIS run plans — over
#                   --repeat the largest total and the smallest passed — the
#                   changed total/passed, keys added / not run here (SKIPPED,
#                   INTERRUPTED, never started) / not run in the base, or
#                   `totals unchanged`; the per-bash sums over those keys; a
#                   base key this run does not plan is no change ("N base
#                   key(s) not in this run", `base_only`). One summary line
#                   (+ up to 20 detail lines; all in OUT/compare.txt), a
#                   `compare` object in summary.json. Informational: the exit
#                   status is the run's.
#   --parallel      the segments of all runtimes at the same time (one bash:
#                   no effect); the launcher relays their lines as they come.
#                   CAVEAT (DG3): the runtimes then fork against each other —
#                   the source of the 2026-09 timing flakes; for orientation
#                   runs, never for a phase gate.
#   --fail-fast     stop after the first hard failure (FAIL, TIMEOUT, STRAY,
#                   CRASH; not ENV, not FLAKY): the cell that runs ends, every
#                   cell not started yet — in every runtime — is SKIPPED (a
#                   result each, `reason=--fail-fast: after cell I VERDICT`,
#                   one `gate fail-fast:` line per runtime); verdict FAIL,
#                   exit 1.
#   --warm          (DG4) one .ckk dir per segment (OUT/seg-N.ckk), shared by
#                   its cells (KKLASS_CKK_DIR), removed at the segment's end
#                   unless --keep; default: a cold .ckk per cell
#   --root DIR      the tree to test (default: the one holding this ktests)
#   --out DIR       the run's directory: a new one (made with an atomic mkdir)
#                   or an existing EMPTY one (dot names count; claimed with an
#                   exclusive marker). Default PRIVATE_TEMP/kt-gate/STAMP-PID,
#                   PRIVATE_TEMP = TMPDIR when set, else %LOCALAPPDATA%/Temp
#                   (else `cygpath -F 28`/Temp), in the C:/ form: the same
#                   root from a 5.2 and a 5.3 launcher (MSYS2's /tmp,
#                   C:/bin/msys64/tmp, is writable by every user: never by
#                   default); only there old runs are rotated (see OUT). It
#                   must be PRIVATE (the segments source OUT/seg-N.spec):
#                   your temp or scratch dir — inside the tree under test a
#                   `[WARN]` (a project folder is usually writable by others)
#   --keep          keep the sandbox of PASSED cells too (others always kept)
#   --nohup         no parent watch (see PROCESSES): for a run detached on
#                   purpose. Implied when SIGHUP is ignored on entry
#                   (`nohup gate.sh …`).
#   Ctrl-Z (TSTP) is not supported: a `[WARN]`, ignored.
#
# Output (stdout; every line also appended to OUT/progress.txt — a background
# run is watched with `tail OUT/progress.txt`):
#   gate STAMP root=ROOT out=OUT            header: start, tree, run dir
#   gate repos: NAME SHA[+dirty] ...        the root repo and its submodules
#   gate bashes: / cells: / options: / changed: / compare: base   (the setup)
#   [ i/N] VER MODE CWD SUITE[#R] VERDICT PASSED/TOTAL [warn=W] DUR [log=...] [(why)]
#           [FAIL] ...                      the first 5 lines of the [FAIL]
#                                           messages (with their continuations)
#   gate VER: C cells  P PASS  F FAIL  L FLAKY  E ENV  T TIMEOUT  S STRAY  X CRASH  Y NOTRUN  tests p/t  DUR [K skipped ...]
#   gate compare BASE: totals unchanged (VER p/t, ...) | N change(s) (...)
#   gate VERDICT  out=OUT
#   __GATE__:VERDICT:cells:pass:fail:flaky:env:timeout:stray:passed_tests:total_tests
# `fail` in the machine line counts FAIL and CRASH cells; cells = cells
# planned; NOTRUN, SKIPPED, INTERRUPTED and never started cells are in none
# of the fields, so pass + fail + ... can be less than cells.
# Reports (DG8), written by the launcher at the end — also of an interrupted
# run, with what finished — before the verdict line:
#   OUT/cells.tsv     a header and one row per PLANNED cell (a cell never
#                     started: verdict UNSTARTED), tab-separated, columns idx
#                     bash_version bash_path mode cwd suite repeat verdict rc
#                     total passed failed warn fail_lines strays attempts
#                     duration_ms log reruns rerun_pass flaky reason; no
#                     value holds a tab/newline/CR (each one a space), an empty
#                     value is `-`; flaky = the files that passed in the rerun,
#                     joined by `/`. --compare reads it.
#   OUT/summary.json  {gate:{started, finished, root, out, argv, repos:{NAME:
#                     {sha, dirty}}, options}, changed (with --changed),
#                     bashes:[{version, path, runtime}], totals:{VERSION:{cells,
#                     PASS, FAIL, FLAKY, ENV, TIMEOUT, STRAY, CRASH, NOTRUN,
#                     INTERRUPTED, SKIPPED, UNSTARTED, passed_tests,
#                     total_tests, duration_ms}}, cells:[{the tsv columns
#                     (numbers as numbers, flaky an array), attempt1, ckk,
#                     fails: the first 5 [FAIL] lines}], compare (with
#                     --compare), machine, exit, verdict} — printf and one
#                     JSON string escape (quote, backslash, every control
#                     character; UTF-8 passed through); never read by gate.
#
# Verdict of a cell (worst wins): STRAY (it left a process: found, stopped)
# · TIMEOUT (stopped at --timeout) · NOTRUN (the suite has no test file:
# summary `error no-test-files`; not a failure) · CRASH (no summary file
# from the runner, or one that says `error REASON`: the runner itself did
# not finish) · FAIL · ENV · FLAKY (--rerun-failed) · PASS. ENV refines CRASH
# and FAIL — the machine, not the test: a FAIL whose failed files ALL died
# of a fork failure — the summary's `env NAME` lines (the RUNNER saw it), or
# a RAW fork-failure line (KT_ENV_FORK_FAILURE_RE in a line that is no test
# message: never in [FAIL]/[PASS]/[WARN] lines or their continuations — a
# test may talk about fork failures; the runner's own "source aborted" line
# counts) that belongs to the file (it precedes the file's next tagged
# message); one real failure next to them keeps FAIL ("+ fork failure in
# ..." in the reason; G4 review R2); without a list of failed files any such
# line; a CRASH with such a raw line, or without a summary at rc 125-127.
# An ENV cell is re-run ONCE in a fresh sandbox, the second run decides, both
# attempts are kept. INTERRUPTED: the cell was stopped by a stop of the gate;
# SKIPPED: not run (--fail-fast) — neither is a verdict of the suite.
# `warn=N` (the log's [WARN] lines) is a column, not a verdict.
# Gate VERDICT: PASS, FAIL, ENV, FLAKY or INTERRUPTED.
# Exit status: 0 every cell PASS (or NOTRUN, at least one PASS; also
# --changed with nothing to run) · 1 any FAIL/TIMEOUT/STRAY/CRASH (also with
# --fail-fast), a segment that died or lost its watchdog, or every cell
# NOTRUN (`[WARN] nothing ran`) · 2 usage · 3 no hard failure, ENV left after
# the retry · 4 no hard failure and no ENV, some FLAKY · 128+N interrupted by
# signal N (143 also for a lost parent), after the running cell was stopped.
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
#   progress.txt, argv.txt, hb, STOP, INTERRUPTED, FINISHED, cells.tsv,
#   summary.json, compare.txt (--compare), FAILFAST (+ FAILFAST.lock: one
#   writer; --fail-fast: the first
#   hard failure; segments stop before their next cell),
#   seg-N.{spec,log,lines,cur,why,ack,pid,wdpid,wdhb,result,strays.txt}
#   (+ seg-N.ckk with --warm), cells/NNN/{result,log.txt,summary,fails.txt,
#   strays.txt} (+ log.1.txt, summary.1, fails.1.txt of an ENV first
#   attempt; rerun-R/ of a --rerun-failed attempt: its own sandbox, log.txt,
#   summary, fails.txt) and the sandbox dirs. A cell's `result` is KEY=VALUE
#   lines: idx bash_version bash_path mode cwd suite repeat verdict rc total
#   passed failed warn fail_lines strays attempts duration_ms log reason
#   attempt1 reruns rerun_pass flaky ckk (the source of cells.tsv).
#   Rotation ONLY under the default root PRIVATE_TEMP/kt-gate (an
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

# the header comment only, up to its first non-comment line (G4 review R9)
kt_gate_usage() { sed -n '2,${/^#/!q;s/^# \{0,1\}//;p;}' "$_KT_GATE_SELF"; }

_kt_gate_usage_error() {
    printf 'gate: %s\n' "$1" >&2
    printf 'gate: usage: gate.sh [options] SUITE... [-- ARGS...]   (gate.sh --help)\n' >&2
    exit 2
}

# kt_gate_parse ARGS... — the CLI into _KT_GATE_* (usage errors exit 2)
kt_gate_parse() {
    _KT_GATE_BASHES=() _KT_GATE_SUITES_ARG=() _KT_GATE_ARGS=()
    _KT_GATE_MODES=( threaded ) _KT_GATE_WORKERS="" _KT_GATE_CWDS=( neutral ) _KT_GATE_TIMEOUT=1800
    _KT_GATE_ROOT_ARG="" _KT_GATE_OUT_ARG="" _KT_GATE_KEEP=0 _KT_GATE_NOHUP=0
    _KT_GATE_REPEAT=1 _KT_GATE_RERUN=0 _KT_GATE_COMPARE="" _KT_GATE_CHANGED=0 _KT_GATE_PARALLEL=0
    _KT_GATE_FAILFAST=0 _KT_GATE_WARM=0
    local o eq
    while (( $# > 0 )); do
        eq=0
        if [[ "$1" == --?*=* ]]; then
            set -- "${1%%=*}" "${1#*=}" "${@:2}"; eq=1
        fi
        o="$1"
        case "$o" in
            --bash|--mode|--workers|--cwd|--timeout|--root|--out|--repeat|--rerun-failed|--compare)
                (( $# >= 2 )) || _kt_gate_usage_error "$o needs a value"
                case "$o" in
                    --bash) [[ -n "$2" ]] || _kt_gate_usage_error "--bash needs a path"; _KT_GATE_BASHES+=( "$2" ) ;;
                    --mode)
                        case "$2" in
                            threaded|single) _KT_GATE_MODES=( "$2" ) ;;
                            both) _KT_GATE_MODES=( threaded single ) ;;
                            *) _kt_gate_usage_error "--mode must be threaded, single or both, got \"$2\"" ;;
                        esac ;;
                    --cwd)
                        case "$2" in
                            neutral|suite) _KT_GATE_CWDS=( "$2" ) ;;
                            both) _KT_GATE_CWDS=( neutral suite ) ;;
                            *) _kt_gate_usage_error "--cwd must be neutral, suite or both, got \"$2\"" ;;
                        esac ;;
                    --workers) [[ "$2" =~ ^[1-9][0-9]*$ ]] || _kt_gate_usage_error "--workers needs a number >= 1, got \"$2\""
                               _KT_GATE_WORKERS="$2" ;;
                    --timeout) [[ "$2" =~ ^[1-9][0-9]*$ ]] || _kt_gate_usage_error "--timeout needs whole seconds >= 1, got \"$2\""
                               _KT_GATE_TIMEOUT="$2" ;;
                    --repeat) [[ "$2" =~ ^[1-9][0-9]{0,3}$ ]] || _kt_gate_usage_error "--repeat needs a number 1-9999, got \"$2\""
                              _KT_GATE_REPEAT=$(( 10#$2 )) ;;
                    --rerun-failed) [[ "$2" =~ ^[0-9]{1,2}$ ]] || _kt_gate_usage_error "--rerun-failed needs a number 0-99, got \"$2\""
                                    _KT_GATE_RERUN=$(( 10#$2 )) ;;
                    --compare) [[ -n "$2" ]] || _kt_gate_usage_error "--compare needs LAST, a run dir or a cells.tsv"
                               _KT_GATE_COMPARE="$2" ;;
                    --root) _KT_GATE_ROOT_ARG="$2" ;;
                    --out) _KT_GATE_OUT_ARG="$2" ;;
                esac
                shift 2 ;;
            --keep|--nohup|--changed|--parallel|--fail-fast|--warm)
                (( eq )) && _kt_gate_usage_error "$o takes no value"
                case "$o" in
                    --keep) _KT_GATE_KEEP=1 ;;
                    --nohup) _KT_GATE_NOHUP=1 ;;
                    --changed) _KT_GATE_CHANGED=1 ;;
                    --parallel) _KT_GATE_PARALLEL=1 ;;
                    --fail-fast) _KT_GATE_FAILFAST=1 ;;
                    --warm) _KT_GATE_WARM=1 ;;
                esac
                shift ;;
            --segment|--watchdog)
                _kt_gate_usage_error "$o is internal (the launcher starts it)" ;;
            -h|--help) kt_gate_usage; exit 0 ;;
            --) shift; _KT_GATE_ARGS=( "$@" ); break ;;
            -*) _kt_gate_usage_error "unknown option $o" ;;
            *) _KT_GATE_SUITES_ARG+=( "$o" ); shift ;;
        esac
    done
    (( ${#_KT_GATE_SUITES_ARG[@]} > 0 || _KT_GATE_CHANGED )) || _kt_gate_usage_error "no suite given (name suites, or all, or --changed)"
    return 0
}

# _kt_gate_ptmp -> REPLY: the user-PRIVATE temp dir, in the mixed C:/ form
# (G4 review R13): TMPDIR when set (as given: the caller's choice, made on
# use as before), else %LOCALAPPDATA%/Temp,
# else the Windows per-user local app data folder (`cygpath -F 28`, also
# without any environment: a cross-runtime start)/Temp; /tmp only when none
# exists. Never MSYS2's /tmp unasked (C:/bin/msys64/tmp: every user may
# write there, and the segments SOURCE OUT/seg-N.spec). The same rule in both
# runtimes, so a 5.2 and a 5.3 launcher share ONE default root (LAST, rotation)
_kt_gate_ptmp() {
    local v c
    if [[ -n "${TMPDIR:-}" ]]; then _kt_gate_mpath "${TMPDIR%/}"; return 0; fi
    for v in "${LOCALAPPDATA:+$LOCALAPPDATA/Temp}"; do
        [[ -n "$v" ]] || continue
        c="$v"
        [[ "$v" == [A-Za-z]:* && -n "$_KT_GATE_CYGPATH" ]] && c="$(cygpath -u -- "$v" 2>/dev/null)"
        if [[ -n "$c" && -d "$c" && -w "$c" ]]; then _kt_gate_mpath "${c%/}"; return 0; fi
    done
    if [[ -n "$_KT_GATE_CYGPATH" ]]; then
        v="$(cygpath -m -F 28 2>/dev/null)"
        if [[ -n "$v" ]]; then
            c="$(cygpath -u -- "$v/Temp" 2>/dev/null)"
            if [[ -n "$c" && -d "$c" && -w "$c" ]]; then REPLY="${v%/}/Temp"; return 0; fi
        fi
    fi
    _kt_gate_mpath /tmp
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
    declare -gA _KT_GATE_WANT=()
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
            for id in "${_KT_GATE_ALL_IDS[@]}"; do _KT_GATE_WANT["$id"]=1; done
            continue
        fi
        m=()
        for id in "${_KT_GATE_ALL_IDS[@]}"; do [[ "$id" == "$a" ]] && m=( "$id" ); done
        if (( ${#m[@]} == 0 )); then
            for id in "${_KT_GATE_ALL_IDS[@]}"; do [[ "${id##*/}" == "$a" ]] && m+=( "$id" ); done
        fi
        case ${#m[@]} in
            0) _kt_gate_usage_error "unknown suite \"$a\" (suites under $_KT_GATE_ROOT: ${_KT_GATE_ALL_IDS[*]})" ;;
            1) _KT_GATE_WANT["${m[0]}"]=1 ;;
            *) _kt_gate_usage_error "ambiguous suite \"$a\": ${m[*]}" ;;
        esac
    done
    kt_gate_select
    return 0
}

# kt_gate_select — _KT_GATE_SEL = the ids in _KT_GATE_WANT, in discovery order
kt_gate_select() {
    local id
    _KT_GATE_SEL=()
    for id in "${_KT_GATE_ALL_IDS[@]}"; do [[ -n "${_KT_GATE_WANT["$id"]+x}" ]] && _KT_GATE_SEL+=( "$id" ); done
    return 0
}

# ---------------------------------------------------------------------------
# --changed (DG6, GATE_PLAN 4.5): the suites the uncommitted changes touch
# ---------------------------------------------------------------------------

# _kt_gate_git_list DIR PREFIX ARGS... — append to _KT_GATE_CHG_PATHS the
# NUL-separated paths `git -C DIR ARGS...` prints, each as PREFIX/PATH; for
# `status --porcelain -z` (STATUS=1) the XY columns are dropped and a rename's
# old path is taken too. rc 1 when git fails.
_kt_gate_git_list() {
    local d="$1" pre="$2" st="$3" e i ren=0
    shift 3
    local -a E=()
    git -C "$d" "$@" > "$_KT_GATE_CHG_TMP" 2>/dev/null || return 1
    mapfile -d '' -t E < "$_KT_GATE_CHG_TMP"
    for (( i = 0; i < ${#E[@]}; i++ )); do
        e="${E[i]}"
        [[ -n "$e" ]] || continue
        if (( st )); then
            if (( ren )); then ren=0
            else
                [[ "${e:0:2}" == *[RC]* ]] && ren=1     # X or Y: a rename/copy, staged or in the worktree (R4)
                e="${e:3}"
            fi
        fi
        _KT_GATE_CHG_PATHS+=( "${pre:+$pre/}$e" )
    done
    return 0
}

# _kt_gate_chg_index — the kcl unit index, one grep over ROOT/kcl (*.sh):
# _KT_GATE_U_DIR[UNIT]=DIR and _KT_GATE_U_FILE[UNIT] for every kcl/DIR/X.sh
# (top level of DIR) with a `kk.unit UNIT` line; _KT_GATE_F_UNIT[FILE]=UNIT;
# _KT_GATE_F_USES[FILE]=" U1 U2 " = the literal unit names of FILE's
# `kk.uses [--optional] U...` lines (any file under kcl; words up to `||`,
# `;`, `#`, a redirection, anything with a $ or a quote)
_kt_gate_chg_index() {
    local line f t w old="$PWD" uses
    local -a W=()
    declare -gA _KT_GATE_U_DIR=() _KT_GATE_U_FILE=() _KT_GATE_F_UNIT=() _KT_GATE_F_USES=()
    [[ -d "$_KT_GATE_ROOT/kcl" ]] || return 0
    builtin cd -- "$_KT_GATE_ROOT" 2>/dev/null || return 0
    LC_ALL=C grep -rE --include='*.sh' -e '^[[:space:]]*kk\.(unit|uses)[[:space:]]' -- kcl > "$_KT_GATE_CHG_TMP" 2>/dev/null
    builtin cd -- "$old" 2>/dev/null
    while IFS= read -r line; do
        f="${line%%:*}" t="${line#*:}"
        t="${t%$'\r'}"
        if [[ "$t" =~ ^[[:space:]]*kk\.unit[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*) ]]; then
            w="${BASH_REMATCH[1]}"
            [[ "$f" =~ ^kcl/[^/]+/[^/]+\.sh$ && -z "${_KT_GATE_F_UNIT["$f"]+x}" ]] || continue
            _KT_GATE_F_UNIT["$f"]="$w"
            if [[ -z "${_KT_GATE_U_FILE["$w"]+x}" ]]; then
                _KT_GATE_U_FILE["$w"]="$f"; f="${f#kcl/}"; _KT_GATE_U_DIR["$w"]="${f%%/*}"
            fi
        elif [[ "$t" =~ ^[[:space:]]*kk\.uses[[:space:]]+(.*)$ ]]; then
            read -r -a W <<< "${BASH_REMATCH[1]}"
            uses=""
            for w in "${W[@]}"; do
                [[ "$w" == --* ]] && continue
                [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]] || break
                uses+=" $w"
            done
            [[ -n "$uses" ]] && _KT_GATE_F_USES["$f"]="${_KT_GATE_F_USES["$f"]:- }${uses# } "
        fi
    done < "$_KT_GATE_CHG_TMP"
    return 0
}

# _kt_gate_chg_pick ID WHY — select suite ID (when it is one) for WHY (the
# first reason is kept)
# the root documents a suite runs (path -> "SUITE|why"; G4 review R5: a
# change of the kbool README must reach kkore/tests/015_DocExamples)
declare -gA _KT_GATE_DOC_MAP=( [README.md]="kkore|doc examples (kkore 015 runs its doctest blocks)" )

# _kt_gate_was_unit PATH — rc 0 when the HEAD version of the (deleted) file
# PATH (root-relative; in a submodule: that repo's HEAD) has a kk.unit line
_kt_gate_was_unit() {
    local p="$1" repo="$_KT_GATE_ROOT" rel="$1" sub
    for sub in "${!_KT_GATE_CHG_ISSUB[@]}"; do
        [[ "$p" == "$sub/"* ]] && { repo="$_KT_GATE_ROOT/$sub"; rel="${p#"$sub"/}"; break; }
    done
    git -C "$repo" show "HEAD:$rel" 2>/dev/null | LC_ALL=C grep -qE '^[[:space:]]*kk\.unit[[:space:]]'
}

_kt_gate_chg_pick() {
    [[ -n "${_KT_GATE_IS_ID["$1"]+x}" ]] || return 1
    [[ -n "${_KT_GATE_CHG_WHY["$1"]+x}" ]] || _KT_GATE_CHG_WHY["$1"]="$2"
    return 0
}

# kt_gate_changed — DG6 / GATE_PLAN 4.5. The changed paths: `git status
# --porcelain -z -uall` (staged, unstaged, untracked) in the root repo and in
# each submodule of .gitmodules; a submodule whose COMMIT differs from the
# one the root's HEAD records adds the files of that diff. Then:
#   kkore/ kklass/ ktests/ tests/ kbool.sh .gitmodules (or a submodule diff
#   that cannot be read)                       -> all suites
#   a root document a suite tests (_KT_GATE_DOC_MAP: README.md -> kkore, its
#   015_DocExamples runs the doctest blocks)  -> that suite
#   kcl/tests/...                              -> kcl
#   kcl/DIR/...                                -> kcl/DIR (when it is a suite;
#                                                 *.md too: doc tests)
#   a unit file (kcl/DIR/X.sh with kk.unit; a deleted kcl/DIR/X.sh whose
#   HEAD version has a kk.unit line too)       -> kcl as well; a deleted
#   top-level script without one ("deleted script") selects its suite only
#   the units of DIR are TOUCHED by a change in kcl/DIR outside DIR/tests/
#   that is not *.md; a unit whose unit file has `kk.uses U` for a touched
#   (or so affected) unit is AFFECTED, transitively; every affected unit's
#   suite is selected, and every suite with another script (a test file, a
#   bench.sh its tests run: any kcl/DIR/**.sh that is no unit file) that
#   has `kk.uses U` for an affected unit
#   anything else (kcl/README.md, docs/, ...) -> no suite
# Sets _KT_GATE_CHG_PATHS, _KT_GATE_CHG_ALL (why), _KT_GATE_CHG_WHY[ID],
# _KT_GATE_CHG_LINES (what the launcher prints). Usage error when git or the
# root repo is missing.
kt_gate_changed() {
    local r="$_KT_GATE_ROOT" p k v sub rec id u f d i n added l
    local -a subs=()
    declare -gA _KT_GATE_CHG_WHY=() _KT_GATE_IS_ID=()
    local -A touch=() aff=() affwhy=()
    _KT_GATE_CHG_PATHS=() _KT_GATE_CHG_ALL="" _KT_GATE_CHG_LINES=()
    command -v git >/dev/null 2>&1 || _kt_gate_usage_error "--changed needs git"
    _kt_gate_is_toplevel "$r" || _kt_gate_usage_error "--changed: $r is not the top of a git work tree"
    _KT_GATE_CHG_TMP="${_KT_GATE_PTMP:-${TMPDIR:-/tmp}}/kt-gate-changed.$$"
    for id in "${_KT_GATE_ALL_IDS[@]}"; do _KT_GATE_IS_ID["$id"]=1; done
    _kt_gate_git_list "$r" "" 1 status --porcelain -z -uall --ignore-submodules=dirty \
        || _kt_gate_usage_error "--changed: git status failed in $r (or ${_KT_GATE_CHG_TMP%/*} is not writable)"
    if [[ -f "$r/.gitmodules" ]]; then
        while IFS=' =' read -r k v; do
            [[ "$k" == path ]] && { v="${v# }"; subs+=( "${v% }" ); }
        done < <(sed 's/^[[:space:]]*//; s/[[:space:]]*=[[:space:]]*/ = /' "$r/.gitmodules")
    fi
    local -A issub=()
    declare -gA _KT_GATE_CHG_ISSUB=()
    for sub in "${subs[@]}"; do issub["$sub"]=1; _KT_GATE_CHG_ISSUB["$sub"]=1; done
    # a submodule entry of the root's status = its commit moved: the files of
    # that diff (the root's HEAD records REC, the submodule is at HEAD)
    local -a rootp=( "${_KT_GATE_CHG_PATHS[@]}" )
    _KT_GATE_CHG_PATHS=()
    for p in "${rootp[@]}"; do
        if [[ -n "${issub["$p"]+x}" ]]; then
            rec="$(git -C "$r" rev-parse -q --verify "HEAD:$p" 2>/dev/null)"
            if [[ -z "$rec" ]] || ! _kt_gate_git_list "$r/$p" "$p" 0 diff --name-only -z "$rec" HEAD; then
                _KT_GATE_CHG_PATHS+=( "$p/" )
                [[ -n "$_KT_GATE_CHG_ALL" ]] || _KT_GATE_CHG_ALL="$p: its new commits cannot be listed"
            fi
        else
            _KT_GATE_CHG_PATHS+=( "$p" )
        fi
    done
    for sub in "${subs[@]}"; do
        [[ -e "$r/$sub/.git" ]] || continue     # not checked out (git would walk up to the root)
        _kt_gate_git_list "$r/$sub" "$sub" 1 status --porcelain -z -uall --ignore-submodules=dirty \
            || _kt_gate_usage_error "--changed: git status failed in $r/$sub"
    done
    rm -f -- "$_KT_GATE_CHG_TMP" 2>/dev/null
    if (( ${#_KT_GATE_CHG_PATHS[@]} == 0 )); then
        _KT_GATE_CHG_LINES+=( "gate changed: nothing changed (git status: the root and ${#subs[@]} submodule(s) are clean)" )
        return 0
    fi
    # all?
    for p in "${_KT_GATE_CHG_PATHS[@]}"; do
        [[ -n "$_KT_GATE_CHG_ALL" ]] && break
        case "$p" in
            kkore/*|kklass/*|ktests/*|tests/*|kbool.sh|kkore|kklass|ktests|tests|.gitmodules)
                _KT_GATE_CHG_ALL="$p (kkore/ kklass/ ktests/ tests/ kbool.sh .gitmodules select all)" ;;
        esac
    done
    if [[ -n "$_KT_GATE_CHG_ALL" ]]; then
        for id in "${_KT_GATE_ALL_IDS[@]}"; do _KT_GATE_CHG_WHY["$id"]="all"; done
        _KT_GATE_CHG_LINES+=( "gate changed: ${#_KT_GATE_CHG_PATHS[@]} path(s): all ${#_KT_GATE_ALL_IDS[@]} suites, for $_KT_GATE_CHG_ALL" )
        return 0
    fi
    _kt_gate_chg_index
    rm -f -- "$_KT_GATE_CHG_TMP" 2>/dev/null
    local -a none=()
    for p in "${_KT_GATE_CHG_PATHS[@]}"; do
        if [[ "$p" == kcl/tests/* ]]; then
            _kt_gate_chg_pick kcl "changed: $p"
            continue
        fi
        if [[ "$p" =~ ^kcl/([^/]+)/(.+)$ ]]; then
            d="${BASH_REMATCH[1]}" f="${BASH_REMATCH[2]}"
            _kt_gate_chg_pick "kcl/$d" "changed: $p" || none+=( "$p" )
            # a deleted top-level script of DIR: a unit file only when its HEAD
            # version says kk.unit (G4 review R9) — else it selects its suite only
            local del=0
            if [[ "$f" != */* && "$f" == *.sh && ! -e "$r/$p" && -z "${_KT_GATE_F_UNIT["$p"]+x}" ]]; then
                if _kt_gate_was_unit "$p"; then del=1
                else
                    [[ "${_KT_GATE_CHG_WHY["kcl/$d"]:-}" == "changed: $p" ]] && _KT_GATE_CHG_WHY["kcl/$d"]="deleted script: $p"
                    continue
                fi
            fi
            if [[ "$f" != tests/* && "$f" != *.md ]]; then
                touch["$d"]="$p"
            fi
            # a unit file (its header), or a deleted one
            if [[ -n "${_KT_GATE_F_UNIT["$p"]+x}" ]] || (( del )); then
                _kt_gate_chg_pick kcl "unit file changed: $p"
                # a deleted unit file: its unit is the file stem (U33)
                u="${f%.sh}"
                if [[ ! -e "$r/$p" && -z "${_KT_GATE_U_DIR["$u"]+x}" ]]; then
                    _KT_GATE_U_DIR["$u"]="$d" _KT_GATE_U_FILE["$u"]="$p"
                fi
            fi
            continue
        fi
        if [[ -n "${_KT_GATE_DOC_MAP["$p"]+x}" ]]; then
            l="${_KT_GATE_DOC_MAP["$p"]}"
            _kt_gate_chg_pick "${l%%|*}" "${l#*|}: $p" && continue
        fi
        none+=( "$p" )
    done
    # the touched units, then everything whose unit file uses an affected unit
    for u in "${!_KT_GATE_U_DIR[@]}"; do
        d="${_KT_GATE_U_DIR["$u"]}"
        [[ -n "${touch["$d"]+x}" ]] && { aff["$u"]=1; affwhy["$u"]="changed: ${touch["$d"]}"; }
    done
    added=1
    while (( added )); do
        added=0
        for u in "${!_KT_GATE_U_FILE[@]}"; do
            [[ -n "${aff["$u"]+x}" ]] && continue
            f="${_KT_GATE_U_FILE["$u"]}"
            for v in ${_KT_GATE_F_USES["$f"]:-}; do
                if [[ -n "${aff["$v"]+x}" ]]; then
                    aff["$u"]=1; affwhy["$u"]="unit $u uses $v ($f)"; added=1
                    break
                fi
            done
        done
    done
    for u in "${!aff[@]}"; do
        _kt_gate_chg_pick "kcl/${_KT_GATE_U_DIR["$u"]}" "${affwhy["$u"]}"
    done
    # the other files of a suite dir that use an affected unit: test files,
    # and scripts the tests run (bench.sh: 007_Bench.sh & co. run it) — they
    # select their suite only (they are no part of the dir's units)
    for f in "${!_KT_GATE_F_USES[@]}"; do
        [[ -n "${_KT_GATE_F_UNIT["$f"]+x}" ]] && continue
        [[ "$f" =~ ^kcl/([^/]+)/ ]] || continue
        d="${BASH_REMATCH[1]}"
        for v in ${_KT_GATE_F_USES["$f"]}; do
            if [[ -n "${aff["$v"]+x}" ]]; then
                if [[ "$f" == "kcl/$d/tests/"* ]]; then _kt_gate_chg_pick "kcl/$d" "test uses $v ($f)"
                else _kt_gate_chg_pick "kcl/$d" "${f##*/} uses $v ($f)"; fi
                break
            fi
        done
    done
    n=0
    for id in "${_KT_GATE_ALL_IDS[@]}"; do [[ -n "${_KT_GATE_CHG_WHY["$id"]+x}" ]] && n=$(( n + 1 )); done
    _KT_GATE_CHG_LINES+=( "gate changed: ${#_KT_GATE_CHG_PATHS[@]} path(s) select $n suite(s)" )
    for id in "${_KT_GATE_ALL_IDS[@]}"; do
        [[ -n "${_KT_GATE_CHG_WHY["$id"]+x}" ]] && _KT_GATE_CHG_LINES+=( "gate changed:   $id  <- ${_KT_GATE_CHG_WHY["$id"]}" )
    done
    if (( ${#none[@]} > 0 )); then
        l="${none[*]:0:5}"; (( ${#none[@]} > 5 )) && l+=" ... (${#none[@]} in all)"
        _KT_GATE_CHG_LINES+=( "gate changed:   (no suite) <- $l" )
    fi
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
#   default: PRIVATE_TEMP/kt-gate/STAMP-PID (_kt_gate_ptmp; one root for both
#     runtimes, G4 review R13) made by an ATOMIC mkdir (a name
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
        p="$_KT_GATE_PTMP/kt-gate"
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
    # OUT must be private: the segment SOURCES OUT/seg-N.spec — a dir others
    # can write to (the tree: C:\projects inherits "Authenticated Users:
    # Modify") lets them run code in the gate (G4 review R11)
    _KT_GATE_OUT_WARN=""
    [[ "$_KT_GATE_OUT/" == "$_KT_GATE_ROOT/"* ]] \
        && _KT_GATE_OUT_WARN="[WARN] --out is inside the tree under test ($_KT_GATE_OUTM): the segments source OUT/seg-N.spec — use a private dir (your temp/scratch dir)"
    mkdir -p -- "$_KT_GATE_OUT/cells"
    printf '%q ' "$_KT_GATE_SELF" "${_KT_GATE_ARGV[@]}" > "$_KT_GATE_OUT/argv.txt"; echo >> "$_KT_GATE_OUT/argv.txt"
    : > "$_KT_GATE_OUT/progress.txt"
    (( _KT_GATE_DEFROOT )) && kt_gate_rotate
    return 0
}

# kt_gate_rotate — ONLY under the default root (review R3): of its
# gate-marked dirs the newest 10 stay; an older one is removed only when gate
# made it (marker v2, CREATED=1), its owner is dead (same runtime: kill -0;
# the other runtime: no fresh OUT/hb and FINISHED/INTERRUPTED or older than
# 24 h) AND it is
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
            # the other runtime's pid cannot be seen: its launcher rewrites
            # OUT/hb every 5 s while it lives — fresh (< 2 min) = alive, also
            # after an INTERRUPTED mark (it then still writes the reports; one
            # default root for both runtimes since G4 review R13)
            [[ -n "$(find "$d" -maxdepth 1 -name hb -mmin -2 2>/dev/null)" ]] && continue
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

# _kt_gate_is_toplevel DIR — rc 0 when DIR is the top of a git work tree
# (not a dir inside one): git's toplevel and DIR compared in the mixed
# spelling, case-insensitively
_kt_gate_is_toplevel() {
    local top r
    top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$top" ]] || return 1
    _kt_gate_mpath "$top"; top="${REPLY%/}"
    _kt_gate_mpath "$1"; r="${REPLY%/}"
    [[ "${top,,}" == "${r,,}" ]]
}

# kt_gate_repos — REPLY = "NAME SHA[+dirty] ..." for the root and its submodules
kt_gate_repos() {
    local r="$_KT_GATE_ROOT" sha st p k v out=""
    local -a subs=()
    _KT_GATE_REPO_N=() _KT_GATE_REPO_S=() _KT_GATE_REPO_D=()
    REPLY="(no git)"
    command -v git >/dev/null 2>&1 || return 0
    # the root itself, never a repository it merely lies in (a fixture root
    # in a test's tmp would report the enclosing repository)
    _kt_gate_is_toplevel "$r" || { REPLY="(not a git repository)"; return 0; }
    sha="$(git -C "$r" rev-parse --short HEAD 2>/dev/null)"
    [[ -n "$sha" ]] || { REPLY="(not a git repository)"; return 0; }
    st="$(git -C "$r" status --porcelain 2>/dev/null)"
    out="${r##*/} $sha${st:++dirty}"
    _KT_GATE_REPO_N+=( "${r##*/}" ); _KT_GATE_REPO_S+=( "$sha" ); _KT_GATE_REPO_D+=( "${st:+true}" )
    if [[ -f "$r/.gitmodules" ]]; then
        while IFS=' =' read -r k v; do
            [[ "$k" == path ]] && subs+=( "${v# }" )
        done < <(sed 's/^[[:space:]]*//; s/[[:space:]]*=[[:space:]]*/ = /' "$r/.gitmodules")
    fi
    for p in "${subs[@]}"; do
        p="${p% }"
        sha=""
        [[ -e "$r/$p/.git" ]] && sha="$(git -C "$r/$p" rev-parse --short HEAD 2>/dev/null)"
        _KT_GATE_REPO_N+=( "$p" ); _KT_GATE_REPO_S+=( "$sha" )
        [[ -n "$sha" ]] || { out+=" $p (none)"; _KT_GATE_REPO_D+=( "" ); continue; }
        st="$(git -C "$r/$p" status --porcelain 2>/dev/null)"
        out+=" $p $sha${st:++dirty}"
        _KT_GATE_REPO_D+=( "${st:+true}" )
    done
    for (( k = 0; k < ${#_KT_GATE_REPO_D[@]}; k++ )); do
        [[ -n "${_KT_GATE_REPO_S[k]}" && -z "${_KT_GATE_REPO_D[k]}" ]] && _KT_GATE_REPO_D[k]=false
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
    mapfile -s "${_KT_GATE_SHOWN_K[$1]:-0}" L < "$f"
    for l in "${L[@]}"; do
        [[ "$l" == *$'\n' ]] || break      # a line still being written
        _kt_gate_say "${l%$'\n'}"
        _KT_GATE_SHOWN_K[$1]=$(( ${_KT_GATE_SHOWN_K[$1]:-0} + 1 ))
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
    KT_GATE_S_NREP=$_KT_GATE_REPEAT
    KT_GATE_S_RERUN=$_KT_GATE_RERUN
    KT_GATE_S_FAILFAST=$_KT_GATE_FAILFAST
    KT_GATE_S_WARM=$_KT_GATE_WARM
    KT_GATE_S_C_IDX=() KT_GATE_S_C_SUITE=() KT_GATE_S_C_MODE=() KT_GATE_S_C_CWD=() KT_GATE_S_C_REP=()
    for (( i = 0; i < _KT_GATE_NCELLS; i++ )); do
        (( _KT_GATE_CL_K[i] == k )) || continue
        KT_GATE_S_C_IDX+=( $(( i + 1 )) ); KT_GATE_S_C_SUITE+=( "${_KT_GATE_CL_SUITE[i]}" )
        KT_GATE_S_C_MODE+=( "${_KT_GATE_CL_MODE[i]}" ); KT_GATE_S_C_CWD+=( "${_KT_GATE_CL_CWD[i]}" )
        KT_GATE_S_C_REP+=( "${_KT_GATE_CL_REP[i]}" )
    done
    declare -p KT_GATE_S_VERSION KT_GATE_S_SEG KT_GATE_S_OUT KT_GATE_S_ROOT KT_GATE_S_SELF KT_GATE_S_BASH \
        KT_GATE_S_TOTAL KT_GATE_S_SW KT_GATE_S_VW KT_GATE_S_TIMEOUT KT_GATE_S_KEEP KT_GATE_S_WORKERS KT_GATE_S_HB_TICKS \
        KT_GATE_S_LAUNCHER KT_GATE_S_ARGS KT_GATE_S_ENV KT_GATE_S_NREP KT_GATE_S_RERUN KT_GATE_S_FAILFAST KT_GATE_S_WARM \
        KT_GATE_S_C_IDX KT_GATE_S_C_SUITE KT_GATE_S_C_MODE \
        KT_GATE_S_C_CWD KT_GATE_S_C_REP > "$_KT_GATE_OUT/seg-$n.spec"
}

# kt_gate_cells — the cell table, in run order: runtime-major (DG3), then the
# repeat, the suite (discovery order), the mode, the cwd. _KT_GATE_CL_{K,
# SUITE,MODE,CWD,REP}[i] = cell i+1; _KT_GATE_NCELLS, _KT_GATE_PER (per runtime)
kt_gate_cells() {
    local k r s m c
    _KT_GATE_CL_K=() _KT_GATE_CL_SUITE=() _KT_GATE_CL_MODE=() _KT_GATE_CL_CWD=() _KT_GATE_CL_REP=()
    for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
        for (( r = 1; r <= _KT_GATE_REPEAT; r++ )); do
            for s in "${_KT_GATE_SEL[@]}"; do
                for m in "${_KT_GATE_MODES[@]}"; do
                    for c in "${_KT_GATE_CWDS[@]}"; do
                        _KT_GATE_CL_K+=( "$k" ); _KT_GATE_CL_SUITE+=( "$s" ); _KT_GATE_CL_MODE+=( "$m" )
                        _KT_GATE_CL_CWD+=( "$c" ); _KT_GATE_CL_REP+=( "$r" )
                    done
                done
            done
        done
    done
    _KT_GATE_NCELLS=${#_KT_GATE_CL_K[@]}
    _KT_GATE_PER=$(( _KT_GATE_NCELLS / ${#_KT_GATE_B_PATH[@]} ))
}

# _kt_gate_cellvars MODE CWD SUITE REP — the line globals of a cell
# (_KT_GATE_CMODE/_CCWD/_CSUITE; the suite as SUITE#REP when --repeat > 1)
_kt_gate_cellvars() {
    _KT_GATE_CMODE="$1" _KT_GATE_CCWD="$2"
    _kt_gate_hsuite "$3"; _KT_GATE_CSUITE="$REPLY"
    (( ${KT_GATE_S_NREP:-1} > 1 )) && _KT_GATE_CSUITE+="#$4"
    return 0
}

# the suite column of the human lines: at most this many characters
declare -g _KT_GATE_SUITE_MAX=40
# _kt_gate_hsuite ID -> REPLY: ID for a human line (G4 review R9): every
# control character (tab, newline, CR, ESC, ...) a `?`, longer than
# _KT_GATE_SUITE_MAX cut with `...` (cells.tsv and summary.json keep the id)
_kt_gate_hsuite() {
    REPLY="$1"
    [[ "$REPLY" == *[$'\001'-$'\037'$'\177']* ]] && REPLY="${REPLY//[$'\001'-$'\037'$'\177']/?}"
    (( ${#REPLY} > _KT_GATE_SUITE_MAX )) && REPLY="${REPLY:0:_KT_GATE_SUITE_MAX-3}..."
    return 0
}

# _kt_gate_skip_put DIR IDX VER BASH MODE CWD SUITE REP REASON — a SKIPPED
# cell's result (--fail-fast: it never ran); written by the segment or, for a
# runtime never started, by the launcher
_kt_gate_skip_put() {
    mkdir -p -- "$1"
    _kt_gate_put "$1/result" "idx=$2" "bash_version=$3" "bash_path=$4" "mode=$5" "cwd=$6" "suite=$7" \
        "repeat=$8" "verdict=SKIPPED" "rc=" "total=0" "passed=0" "failed=0" "warn=0" "fail_lines=0" \
        "strays=0" "attempts=0" "duration_ms=0" "log=" "reason=$9" "attempt1=" "reruns=0" "rerun_pass=0" \
        "flaky=" "ckk="
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

# _kt_gate_seg_start K — start the segment of runtime K (no wait); its
# per-segment launcher state in _KT_GATE_K_* arrays
_kt_gate_seg_start() {
    local k=$1 n=$(( $1 + 1 ))
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
    _KT_GATE_SHOWN_K[n]=0 _KT_GATE_K_GONE[k]=0 _KT_GATE_K_WMISS[k]=0 _KT_GATE_K_NRESC[k]=0
    _KT_GATE_K_POKED[k]=0 _KT_GATE_K_DONE[k]=0 _KT_GATE_K_STARTED[k]=1
    _kt_gate_hb
    : > "$_KT_GATE_OUT/seg-$n.log"
    _kt_gate_spawn "${_KT_GATE_B_SAME[k]}" "$_KT_GATE_OUT/seg-$n.log" "${cmd[@]}"
    _KT_GATE_K_STUB[k]=$REPLY
    _KT_GATE_SEG_T0[k]=$EPOCHREALTIME
}

# _kt_gate_seg_tick K — one launcher tick for segment K: relay its lines,
# its result, a stub gone, its watchdog's heartbeat (a rescue), an
# unanswered stop. _KT_GATE_K_DONE[K]=1 when there is nothing more to wait for
_kt_gate_seg_tick() {
    local k=$1 n=$(( $1 + 1 )) sp=""
    local res="$_KT_GATE_OUT/seg-$n.result" wdhb="$_KT_GATE_OUT/seg-$n.wdhb" lmark="$_KT_GATE_OUT/seg-$n.lmark"
    _kt_gate_relay "$n"
    [[ -e "$res" ]] && { _KT_GATE_K_DONE[k]=1; return 0; }
    if ! kill -0 "${_KT_GATE_K_STUB[k]}" 2>/dev/null; then
        # gone without a result: give its watchdog time to write one
        (( ++_KT_GATE_K_GONE[k] > 30 )) && { _KT_GATE_K_DONE[k]=1; return 0; }
    fi
    # the segment's watchdog ticks seg-N.wdhb every second: silent for
    # HB_TICKS ticks (killed, hung) -> a rescue watchdog (review R6)
    if [[ -e "$wdhb" && "$wdhb" -nt "$lmark" ]]; then
        : > "$lmark"; _KT_GATE_K_WMISS[k]=0
    elif (( ++_KT_GATE_K_WMISS[k] >= _KT_GATE_HB_TICKS && _KT_GATE_K_NRESC[k] < 3 )); then
        _kt_gate_rescue "$k" "$n" && _KT_GATE_K_NRESC[k]=$(( _KT_GATE_K_NRESC[k] + 1 ))
        _KT_GATE_K_WMISS[k]=0
    fi
    if (( _KT_GATE_STOPPED && SECONDS - _KT_GATE_STOP_T0 > _KT_GATE_STOP_WAIT )); then
        # the stop was not answered: in this runtime, ask the segment
        # itself (its USR1 trap reads the reason); then give up
        if (( _KT_GATE_B_SAME[k] && ! _KT_GATE_K_POKED[k] )); then
            _KT_GATE_K_POKED[k]=1; _KT_GATE_K_POKET[k]=$SECONDS
            { read -r sp _ < "$_KT_GATE_OUT/seg-$n.pid"; } 2>/dev/null
            printf 'stop\n' > "$_KT_GATE_OUT/seg-$n.why"
            [[ "$sp" =~ ^[0-9]+$ ]] && kill -USR1 "$sp" 2>/dev/null
            _kt_gate_say "[WARN] segment $n: no answer to the stop in ${_KT_GATE_STOP_WAIT}s - signalled it directly"
        elif (( ! _KT_GATE_K_POKED[k] || SECONDS - _KT_GATE_K_POKET[k] > _KT_GATE_STOP_WAIT )); then
            _KT_GATE_K_DONE[k]=1
        fi
    fi
    return 0
}

# _kt_gate_seg_finish K — after K is done: the lingering stub, final relay
_kt_gate_seg_finish() {
    local k=$1 n=$(( $1 + 1 )) i stub="${_KT_GATE_K_STUB[$1]}"
    # the stubs linger while the segment's last processes leave: bounded
    for (( i = 0; i < 100; i++ )); do kill -0 "$stub" 2>/dev/null || break; _kt_strays_nap 0.1; done
    kill -0 "$stub" 2>/dev/null || wait "$stub" 2>/dev/null
    _kt_gate_relay "$n"
    _KT_GATE_SEG_T1[k]=$EPOCHREALTIME
}

# kt_gate_segments_run K... — start the segments of runtimes K... (serial:
# one K; --parallel: all) and run the launcher's 1 s loop until every one is
# done: relay lines (in the order they come), heartbeat, watch the parent
kt_gate_segments_run() {
    local k tick=0 left sp i
    for k in "$@"; do _kt_gate_seg_start "$k"; done
    while :; do
        _kt_strays_nap 1
        if (( ! _KT_GATE_SIG )) && ! _kt_gate_parent_ok; then
            _kt_gate_on_sig 143 "the launcher's parent is gone"
        fi
        if (( _KT_GATE_SIG && ! _KT_GATE_STOPPED )); then
            _kt_gate_stop_request; _KT_GATE_STOP_T0=$SECONDS
        fi
        left=0
        for k in "$@"; do
            (( _KT_GATE_K_DONE[k] )) && continue
            _kt_gate_seg_tick "$k"
            (( _KT_GATE_K_DONE[k] )) || left=1
        done
        (( left )) || break
        (( ++tick % _KT_GATE_HB_EVERY == 0 )) && _kt_gate_hb
    done
    for k in "$@"; do _kt_gate_seg_finish "$k"; done
    for sp in "${_KT_GATE_RESCUES[@]}"; do
        for (( i = 0; i < 30; i++ )); do kill -0 "$sp" 2>/dev/null || break; _kt_strays_nap 0.1; done
        kill -0 "$sp" 2>/dev/null || wait "$sp" 2>/dev/null
    done
    _KT_GATE_RESCUES=()
}

# kt_gate_collect K — per-runtime counts from its cells' result files
kt_gate_collect() {
    local k=$1 n=$(( $1 + 1 )) i idx f v
    local -A c=( [PASS]=0 [FAIL]=0 [FLAKY]=0 [ENV]=0 [TIMEOUT]=0 [STRAY]=0 [CRASH]=0 [NOTRUN]=0 [INTERRUPTED]=0
                 [SKIPPED]=0 [UNSTARTED]=0 )
    local tp=0 tt=0 a b ms
    for (( i = 0; i < _KT_GATE_NCELLS; i++ )); do
        (( _KT_GATE_CL_K[i] == k )) || continue
        idx=$(( i + 1 ))
        printf -v f '%s/cells/%03d/result' "$_KT_GATE_OUT" "$idx"
        if _kt_gate_readkv "$f"; then
            v="${_KT_GATE_KV[verdict]:-CRASH}"
            [[ -n "${c[$v]+x}" && "$v" != UNSTARTED ]] || v=CRASH
            c[$v]=$(( c[$v] + 1 ))
            [[ "${_KT_GATE_KV[passed]:-}" =~ ^[0-9]+$ ]] && tp=$(( tp + _KT_GATE_KV[passed] ))
            [[ "${_KT_GATE_KV[total]:-}" =~ ^[0-9]+$ ]] && tt=$(( tt + _KT_GATE_KV[total] ))
        else
            c[UNSTARTED]=$(( c[UNSTARTED] + 1 ))
        fi
    done
    local s=""
    _kt_gate_readkv "$_KT_GATE_OUT/seg-$n.result" && s="${_KT_GATE_KV[status]:-}"
    for v in "${_KT_GATE_VERDICTS[@]}"; do
        _KT_GATE_TOT[$v]=$(( ${_KT_GATE_TOT[$v]:-0} + c[$v] ))
        _KT_GATE_KC["$k:$v"]=${c[$v]}
    done
    _KT_GATE_TOT[tp]=$(( ${_KT_GATE_TOT[tp]:-0} + tp )); _KT_GATE_TOT[tt]=$(( ${_KT_GATE_TOT[tt]:-0} + tt ))
    _KT_GATE_KC["$k:tp"]=$tp _KT_GATE_KC["$k:tt"]=$tt
    ms=0
    if [[ -n "${_KT_GATE_SEG_T0[k]:-}" ]]; then
        _kt_strays_ms "${_KT_GATE_SEG_T0[k]}"; a=$REPLY
        _kt_strays_ms "${_KT_GATE_SEG_T1[k]:-$EPOCHREALTIME}"; b=$REPLY
        ms=$(( b - a ))
    fi
    _KT_GATE_KC["$k:ms"]=$ms
    _kt_gate_hms "$ms"
    printf -v "_KT_GATE_SUMLINE[$k]" 'gate %-*s: %d cells  %d PASS  %d FAIL  %d FLAKY  %d ENV  %d TIMEOUT  %d STRAY  %d CRASH  %d NOTRUN  tests %d/%d  %s' \
        "$_KT_GATE_VW" "${_KT_GATE_B_VER[k]}" "$_KT_GATE_PER" "${c[PASS]}" "${c[FAIL]}" "${c[FLAKY]}" "${c[ENV]}" "${c[TIMEOUT]}" \
        "${c[STRAY]}" "${c[CRASH]}" "${c[NOTRUN]}" "$tp" "$tt" "$REPLY"
    (( c[INTERRUPTED] > 0 )) && _KT_GATE_SUMLINE[k]+="  ${c[INTERRUPTED]} interrupted"
    (( c[SKIPPED] > 0 )) && _KT_GATE_SUMLINE[k]+="  ${c[SKIPPED]} skipped"
    (( c[UNSTARTED] > 0 )) && _KT_GATE_SUMLINE[k]+="  ${c[UNSTARTED]} not started"
    # a segment that died (no result, or killed) or ran without a watchdog;
    # a runtime never started (a stop, --fail-fast) is none of them
    (( ${_KT_GATE_K_STARTED[k]:-0} )) || return 0
    if [[ -z "$s" ]]; then
        _KT_GATE_SEGFAIL+=( "segment $n (${_KT_GATE_B_VER[k]}) left no result: see seg-$n.log" )
    elif [[ "$s" == segment-killed ]] && (( ! _KT_GATE_SIG )); then
        _KT_GATE_SEGFAIL+=( "segment $n (${_KT_GATE_B_VER[k]}) was killed from outside: see seg-$n.log" )
    elif [[ "$s" == no-watchdog ]]; then
        _KT_GATE_SEGFAIL+=( "segment $n (${_KT_GATE_B_VER[k]}) stopped: its watchdog could not be (re)started: see seg-$n.log" )
    fi
    return 0
}

# _kt_gate_failfast_skip K — --fail-fast hit before runtime K started: every
# cell of K is SKIPPED (results written here, one line)
_kt_gate_failfast_skip() {
    local k=$1 i f why="" n=0
    { IFS= read -r why < "$_KT_GATE_OUT/FAILFAST"; } 2>/dev/null
    for (( i = 0; i < _KT_GATE_NCELLS; i++ )); do
        (( _KT_GATE_CL_K[i] == k )) || continue
        printf -v f '%s/cells/%03d' "$_KT_GATE_OUT" $(( i + 1 ))
        _kt_gate_skip_put "$f" $(( i + 1 )) "${_KT_GATE_B_VER[k]}" "${_KT_GATE_B_MIXED[k]}" "${_KT_GATE_CL_MODE[i]}" \
            "${_KT_GATE_CL_CWD[i]}" "${_KT_GATE_CL_SUITE[i]}" "${_KT_GATE_CL_REP[i]}" "--fail-fast: after $why"
        n=$(( n + 1 ))
    done
    _kt_gate_say "gate fail-fast: ${_KT_GATE_B_VER[k]}: $n cell(s) skipped (after $why)"
}

declare -ga _KT_GATE_VERDICTS=( PASS FAIL FLAKY ENV TIMEOUT STRAY CRASH NOTRUN INTERRUPTED SKIPPED UNSTARTED )
declare -ga _KT_GATE_TSV_COLS=( idx bash_version bash_path mode cwd suite repeat verdict rc total passed failed warn
    fail_lines strays attempts duration_ms log reruns rerun_pass flaky reason )

# ---------------------------------------------------------------------------
# reports (DG8, GATE_PLAN 4.4): cells.tsv, summary.json, --compare
# ---------------------------------------------------------------------------

# _kt_gate_tsv_val S -> REPLY: S without tab/newline/CR (each a space); "" -> -
_kt_gate_tsv_val() {
    REPLY="${1//[$'\t\n\r']/ }"
    [[ -n "$REPLY" ]] || REPLY=-
}

# the control characters other than \b \t \n \f \r, for their \u00XX escape
declare -ga _KT_GATE_JCTL=()
_kt_gate_jctl_init() {
    local i h c
    (( ${#_KT_GATE_JCTL[@]} )) && return 0
    for (( i = 1; i < 32; i++ )); do
        printf -v h '%02x' "$i"; printf -v c "\\x$h"
        _KT_GATE_JCTL[i]="$c"
    done
}

# _kt_gate_jutf8 S -> REPLY: S with every byte sequence that is not valid
# UTF-8 (a stray continuation byte, a truncated or overlong sequence, a
# surrogate, > U+10FFFF) replaced by U+FFFD — summary.json must decode with a
# strict UTF-8 decoder (G4 review R7). Byte-wise (LC_ALL=C), ASCII runs
# copied in one step.
_kt_gate_jutf8() {
    local LC_ALL=C
    local s="$1" o="" pre c b n j lo hi ok
    local rep=$'\xef\xbf\xbd'
    while [[ -n "$s" ]]; do
        pre="${s%%[$'\x80'-$'\xff']*}"
        o+="$pre"; s="${s:${#pre}}"
        [[ -n "$s" ]] || break
        c="${s:0:1}"; printf -v b '%d' "'$c"
        lo=128 hi=191 n=0
        if (( b >= 0xc2 && b <= 0xdf )); then n=1
        elif (( b == 0xe0 )); then n=2 lo=0xa0
        elif (( b == 0xed )); then n=2 hi=0x9f
        elif (( b >= 0xe1 && b <= 0xef )); then n=2
        elif (( b == 0xf0 )); then n=3 lo=0x90
        elif (( b >= 0xf1 && b <= 0xf3 )); then n=3
        elif (( b == 0xf4 )); then n=3 hi=0x8f
        fi
        ok=$(( n > 0 ))
        for (( j = 1; ok && j <= n; j++ )); do
            c="${s:j:1}"
            [[ -n "$c" ]] || { ok=0; break; }
            printf -v b '%d' "'$c"
            if (( j == 1 )); then (( b >= lo && b <= hi )) || ok=0
            else (( b >= 0x80 && b <= 0xbf )) || ok=0; fi
        done
        if (( ok )); then o+="${s:0:n+1}"; s="${s:n+1}"
        else o+="$rep"; s="${s:1}"; fi
    done
    REPLY="$o"
}

# _kt_gate_jstr S -> REPLY: S as a JSON string (quotes, backslashes and every
# control character escaped; valid UTF-8 passed through, an invalid byte
# sequence as U+FFFD: _kt_gate_jutf8)
_kt_gate_jstr() {
    local s="$1" i h
    if [[ "$s" == *[$'\x80'-$'\xff']* ]]; then _kt_gate_jutf8 "$s"; s="$REPLY"; fi
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    if [[ "$s" == *[$'\001'-$'\037']* ]]; then
        s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"; s="${s//$'\b'/\\b}"; s="${s//$'\f'/\\f}"
        if [[ "$s" == *[$'\001'-$'\037']* ]]; then
            _kt_gate_jctl_init
            for (( i = 1; i < 32; i++ )); do
                [[ "$s" == *"${_KT_GATE_JCTL[i]}"* ]] || continue
                printf -v h '\\u%04x' "$i"
                s="${s//"${_KT_GATE_JCTL[i]}"/$h}"
            done
        fi
    fi
    REPLY="\"$s\""
}

# _kt_gate_jnum S -> REPLY: S (decimal) when an integer, else null
_kt_gate_jnum() {
    if [[ "$1" =~ ^(-?)([0-9]+)$ ]]; then REPLY="${BASH_REMATCH[1]}$(( 10#${BASH_REMATCH[2]} ))"; else REPLY=null; fi
}

# _kt_gate_jbool N -> REPLY: true / false
_kt_gate_jbool() { if (( $1 )); then REPLY=true; else REPLY=false; fi; }

# kt_gate_rows — _KT_GATE_ROW["I:COL"] for every planned cell I (0-based):
# its result file, or (never started) the cell table with verdict UNSTARTED
kt_gate_rows() {
    local i f col k
    declare -gA _KT_GATE_ROW=()
    for (( i = 0; i < _KT_GATE_NCELLS; i++ )); do
        printf -v f '%s/cells/%03d/result' "$_KT_GATE_OUT" $(( i + 1 ))
        if _kt_gate_readkv "$f"; then
            for col in "${_KT_GATE_TSV_COLS[@]}" attempt1 ckk; do _KT_GATE_ROW["$i:$col"]="${_KT_GATE_KV[$col]:-}"; done
            [[ -n "${_KT_GATE_ROW["$i:verdict"]}" ]] || _KT_GATE_ROW["$i:verdict"]=CRASH
        else
            k=${_KT_GATE_CL_K[i]}
            for col in "${_KT_GATE_TSV_COLS[@]}" attempt1 ckk; do _KT_GATE_ROW["$i:$col"]=""; done
            _KT_GATE_ROW["$i:idx"]=$(( i + 1 )) _KT_GATE_ROW["$i:bash_version"]="${_KT_GATE_B_VER[k]}"
            _KT_GATE_ROW["$i:bash_path"]="${_KT_GATE_B_MIXED[k]}" _KT_GATE_ROW["$i:mode"]="${_KT_GATE_CL_MODE[i]}"
            _KT_GATE_ROW["$i:cwd"]="${_KT_GATE_CL_CWD[i]}" _KT_GATE_ROW["$i:suite"]="${_KT_GATE_CL_SUITE[i]}"
            _KT_GATE_ROW["$i:repeat"]="${_KT_GATE_CL_REP[i]}" _KT_GATE_ROW["$i:verdict"]=UNSTARTED
        fi
    done
}

# kt_gate_tsv — OUT/cells.tsv: the header, one row per planned cell (values
# without tab/newline/CR, "" written as -); atomically
kt_gate_tsv() {
    local i col line t="$_KT_GATE_OUT/cells.tsv.tmp.$$"
    {
        line=""; for col in "${_KT_GATE_TSV_COLS[@]}"; do line+="${line:+$'\t'}$col"; done
        printf '%s\n' "$line"
        for (( i = 0; i < _KT_GATE_NCELLS; i++ )); do
            line=""
            for col in "${_KT_GATE_TSV_COLS[@]}"; do
                _kt_gate_tsv_val "${_KT_GATE_ROW["$i:$col"]}"
                line+="${line:+$'\t'}$REPLY"
            done
            printf '%s\n' "$line"
        done
    } > "$t" && mv -f -- "$t" "$_KT_GATE_OUT/cells.tsv"
}

# _kt_gate_counted VERDICT — rc 0 when a cell with VERDICT has counts that
# --compare compares (it ran: not UNSTARTED / SKIPPED / INTERRUPTED)
_kt_gate_counted() { [[ -n "$1" && "$1" != UNSTARTED && "$1" != SKIPPED && "$1" != INTERRUPTED && "$1" != - ]]; }

# _kt_gate_cmp_add SIDE KEY VERDICT TOTAL PASSED — aggregate a row into the
# compare table of SIDE (b = the base, n = this run): per key the largest
# total and the smallest passed (over --repeat); an uncounted row only marks
# the key as seen
_kt_gate_cmp_add() {
    local s=$1 key="$2"
    if [[ -z "${_KT_GATE_CMP["$s:seen:$key"]+x}" ]]; then
        _KT_GATE_CMP["$s:seen:$key"]=1
        if [[ "$s" == b ]]; then _KT_GATE_CMP_BKEYS+=( "$key" ); else _KT_GATE_CMP_NKEYS+=( "$key" ); fi
    fi
    _kt_gate_counted "$3" || return 0
    [[ "$4" =~ ^[0-9]+$ && "$5" =~ ^[0-9]+$ ]] || return 0
    if [[ -z "${_KT_GATE_CMP["$s:t:$key"]+x}" ]]; then
        _KT_GATE_CMP["$s:t:$key"]=$(( 10#$4 )) _KT_GATE_CMP["$s:p:$key"]=$(( 10#$5 ))
    else
        (( 10#$4 > _KT_GATE_CMP["$s:t:$key"] )) && _KT_GATE_CMP["$s:t:$key"]=$(( 10#$4 ))
        (( 10#$5 < _KT_GATE_CMP["$s:p:$key"] )) && _KT_GATE_CMP["$s:p:$key"]=$(( 10#$5 ))
    fi
    return 0
}

# _kt_gate_cmp_read FILE — read a base cells.tsv (pure bash) into the b side
# of the compare table; rc 1 + REPLY = why: unreadable, empty, not a gate
# cells.tsv (a header without the key columns), a garbled row (a wrong field
# count, total/passed not a number of at most 18 digits — no overflow)
_kt_gate_cmp_read() {
    local f="$1" line i n key
    local -a H=() F=() L=()
    local -A col=()
    _KT_GATE_CMP=() _KT_GATE_CMP_BKEYS=()
    [[ -f "$f" && -r "$f" ]] || { REPLY="cannot read $f"; return 1; }
    { mapfile -t L < "$f"; } 2>/dev/null
    (( ${#L[@]} > 0 )) || { REPLY="$f is empty"; return 1; }
    line="${L[0]%$'\r'}"
    IFS=$'\x1f' read -r -a H <<< "${line//$'\t'/$'\x1f'}"
    for (( i = 0; i < ${#H[@]}; i++ )); do col["${H[i]}"]=$i; done
    for key in bash_version mode cwd suite verdict total passed; do
        [[ -n "${col[$key]+x}" ]] || { REPLY="$f is not a gate cells.tsv (no column \"$key\" in its header)"; return 1; }
    done
    for (( n = 1; n < ${#L[@]}; n++ )); do
        line="${L[n]%$'\r'}"
        [[ -n "$line" ]] || continue
        F=()
        IFS=$'\x1f' read -r -a F <<< "${line//$'\t'/$'\x1f'}"
        (( ${#F[@]} == ${#H[@]} )) || { REPLY="$f line $(( n + 1 )) is garbled (${#F[@]} fields, the header has ${#H[@]})"; return 1; }
        [[ "${F[col[total]]}" =~ ^([0-9]{1,18}|-)$ && "${F[col[passed]]}" =~ ^([0-9]{1,18}|-)$ ]] \
            || { REPLY="$f line $(( n + 1 )) is garbled (total/passed are not numbers of up to 18 digits)"; return 1; }
        key="${F[col[bash_version]]}"$'\x1f'"${F[col[mode]]}"$'\x1f'"${F[col[cwd]]}"$'\x1f'"${F[col[suite]]}"
        _kt_gate_cmp_add b "$key" "${F[col[verdict]]}" "${F[col[total]]}" "${F[col[passed]]}"
    done
    return 0
}

# kt_gate_compare_base — --compare: find the base's cells.tsv and read it
# into the compare table, before OUT is made, before any run. DIR =
# DIR/cells.tsv, else the file itself: unreadable or garbled -> usage error
# (rc 2). LAST = the newest FINISHED run with a cells.tsv under the DEFAULT
# OUT root PRIVATE_TEMP/kt-gate (_kt_gate_ptmp: the same for a 5.2 and a 5.3
# launcher, so either finds the other's runs), newest by its marker's start stamp, a tie by the
# dir name (the later name wins); a candidate that cannot be read is skipped
# (named in a note, G4 review R3); with none left the run goes on WITHOUT a
# compare: `[WARN] --compare LAST: no base (...)`
kt_gate_compare_base() {
    local c="$_KT_GATE_COMPARE" f="" d st i bi why
    local -a cst=() cdir=() skipped=() ns=() nd=()
    declare -gA _KT_GATE_CMP=()
    _KT_GATE_CMP_BKEYS=() _KT_GATE_CMP_NKEYS=() _KT_GATE_CMP_FILE="" _KT_GATE_CMP_BASE="" _KT_GATE_CMP_CH=()
    _KT_GATE_CMP_BONLY=() _KT_GATE_CMP_NOTES=()
    [[ -n "$c" ]] || return 0
    if [[ "$c" == LAST ]]; then
        local root="$_KT_GATE_PTMP/kt-gate"
        for d in "$root"/*/; do
            d="${d%/}"
            [[ -f "$d/FINISHED" && -f "$d/cells.tsv" && -f "$d/.kt_gate" ]] || continue
            st=""; { read -r _ _ _ _ st _ < "$d/.kt_gate"; } 2>/dev/null
            [[ "$st" =~ ^[0-9]{1,18}$ ]] || continue
            cst+=( "$st" ); cdir+=( "$d" )
        done
        # newest first: by start stamp, then by name (a selection: few dirs)
        while (( ${#cdir[@]} > 0 )); do
            bi=0
            for (( i = 1; i < ${#cdir[@]}; i++ )); do
                if (( 10#${cst[i]} > 10#${cst[bi]} )); then bi=$i
                elif (( 10#${cst[i]} == 10#${cst[bi]} )) && [[ "${cdir[i]}" > "${cdir[bi]}" ]]; then bi=$i; fi
            done
            d="${cdir[bi]}"
            if _kt_gate_cmp_read "$d/cells.tsv"; then f="$d/cells.tsv"; _KT_GATE_CMP_BASE="$d"; break; fi
            skipped+=( "${d##*/}: $REPLY" )
            ns=() nd=()
            for (( i = 0; i < ${#cdir[@]}; i++ )); do (( i == bi )) && continue; ns+=( "${cst[i]}" ); nd+=( "${cdir[i]}" ); done
            cst=( "${ns[@]}" ) cdir=( "${nd[@]}" )
        done
        for why in "${skipped[@]}"; do _KT_GATE_CMP_NOTES+=( "gate compare: a LAST candidate skipped (unreadable): $why" ); done
        if [[ -z "$f" ]]; then
            _kt_gate_mpath "$root"
            _KT_GATE_CMP_NOTES+=( "[WARN] --compare LAST: no base (no readable finished gate run under $REPLY) - running without a compare" )
            _KT_GATE_COMPARE="" _KT_GATE_CMP_BKEYS=()
            _KT_GATE_CMP=()
            return 0
        fi
    else
        if [[ -d "$c" ]]; then
            f="${c%/}/cells.tsv"; _KT_GATE_CMP_BASE="${c%/}"
            [[ -f "$f" ]] || _kt_gate_usage_error "--compare $c: no cells.tsv in that dir"
        else
            f="$c"; _KT_GATE_CMP_BASE="$c"
        fi
        _kt_gate_cmp_read "$f" || _kt_gate_usage_error "--compare $c: $REPLY"
    fi
    _kt_gate_mpath "$f"; _KT_GATE_CMP_FILE="$REPLY"
    _kt_gate_mpath "$_KT_GATE_CMP_BASE"; _KT_GATE_CMP_BASE="$REPLY"
    return 0
}

# kt_gate_compare — this run's rows against the base, over the keys (bash,
# mode, cwd, suite) PLANNED in this run (G4 review R6): _KT_GATE_CMP_CH (the
# changes, "KIND US VER US MODE US CWD US SUITE US BT US BP US NT US NP"
# each, US = \x1f; KIND changed / added / notrun (not run here) / notbase
# (in the base, but not run there: `-` counts, UNSTARTED, INTERRUPTED,
# SKIPPED)); the per-bash sums over the planned keys only. A base key this
# run does not plan is no change and not in the sums: _KT_GATE_CMP_BONLY
# ("VER US MODE US CWD US SUITE US BT US BP"), reported apart. The lines to
# print: _KT_GATE_CMP_OUT (all of them in OUT/compare.txt)
kt_gate_compare() {
    local i key bt bp nt np kind vv m su s c l nb=0
    local -a out=() vord=()
    local -A bsum=() nsum=() seen=()
    _KT_GATE_CMP_CH=() _KT_GATE_CMP_BONLY=()
    for (( i = 0; i < _KT_GATE_NCELLS; i++ )); do
        key="${_KT_GATE_ROW["$i:bash_version"]}"$'\x1f'"${_KT_GATE_ROW["$i:mode"]}"$'\x1f'"${_KT_GATE_ROW["$i:cwd"]}"$'\x1f'"${_KT_GATE_ROW["$i:suite"]}"
        _kt_gate_cmp_add n "$key" "${_KT_GATE_ROW["$i:verdict"]}" "${_KT_GATE_ROW["$i:total"]}" "${_KT_GATE_ROW["$i:passed"]}"
    done
    for key in "${_KT_GATE_CMP_NKEYS[@]}" "${_KT_GATE_CMP_BKEYS[@]}"; do
        [[ -n "${seen["k:$key"]+x}" ]] && continue
        seen["k:$key"]=1
        bt="${_KT_GATE_CMP["b:t:$key"]:-}" bp="${_KT_GATE_CMP["b:p:$key"]:-}"
        nt="${_KT_GATE_CMP["n:t:$key"]:-}" np="${_KT_GATE_CMP["n:p:$key"]:-}"
        if [[ -z "${_KT_GATE_CMP["n:seen:$key"]+x}" ]]; then
            _KT_GATE_CMP_BONLY+=( "$key"$'\x1f'"$bt"$'\x1f'"$bp" )
            continue
        fi
        vv="${key%%$'\x1f'*}"
        [[ -n "${seen["v:$vv"]+x}" ]] || { seen["v:$vv"]=1; vord+=( "$vv" ); }
        [[ -n "$bt" ]] && { bsum["t:$vv"]=$(( ${bsum["t:$vv"]:-0} + bt )); bsum["p:$vv"]=$(( ${bsum["p:$vv"]:-0} + bp )); }
        [[ -n "$nt" ]] && { nsum["t:$vv"]=$(( ${nsum["t:$vv"]:-0} + nt )); nsum["p:$vv"]=$(( ${nsum["p:$vv"]:-0} + np )); }
        kind=""
        if [[ -n "$bt" && -n "$nt" ]]; then
            [[ "$bt" != "$nt" || "$bp" != "$np" ]] && kind=changed
        elif [[ -n "$nt" ]]; then
            if [[ -n "${_KT_GATE_CMP["b:seen:$key"]+x}" ]]; then kind=notbase; else kind=added; fi
        elif [[ -n "$bt" ]]; then
            kind=notrun
        fi
        [[ -n "$kind" ]] && _KT_GATE_CMP_CH+=( "$kind"$'\x1f'"$key"$'\x1f'"$bt"$'\x1f'"$bp"$'\x1f'"$nt"$'\x1f'"$np" )
    done
    s=""
    for vv in "${vord[@]}"; do
        [[ -n "${bsum["t:$vv"]+x}${nsum["t:$vv"]+x}" ]] || continue
        if [[ "${bsum["p:$vv"]:-0}/${bsum["t:$vv"]:-0}" == "${nsum["p:$vv"]:-0}/${nsum["t:$vv"]:-0}" ]]; then
            s+="${s:+, }$vv ${nsum["p:$vv"]:-0}/${nsum["t:$vv"]:-0}"
        else
            s+="${s:+, }$vv ${bsum["p:$vv"]:-0}/${bsum["t:$vv"]:-0} -> ${nsum["p:$vv"]:-0}/${nsum["t:$vv"]:-0}"
        fi
    done
    nb=${#_KT_GATE_CMP_BONLY[@]}
    l="$_KT_GATE_CMP_BASE"
    [[ "$_KT_GATE_COMPARE" == LAST ]] && l="LAST ($_KT_GATE_CMP_BASE)"
    if (( ${#_KT_GATE_CMP_CH[@]} == 0 )); then
        out=( "gate compare $l: totals unchanged ($s)" )
    else
        out=( "gate compare $l: ${#_KT_GATE_CMP_CH[@]} change(s) ($s)" )
    fi
    (( nb > 0 )) && out[0]+="; $nb base key(s) not in this run, not compared"
    for c in "${_KT_GATE_CMP_CH[@]}"; do
        IFS=$'\x1f' read -r kind vv m su s bt bp nt np <<< "$c"
        l="        $vv $m $su $s  "
        case "$kind" in
            changed) l+="total $bt -> $nt  passed $bp -> $np" ;;
            added) l+="added ($np/$nt)" ;;
            notbase) l+="not run in the base (now $np/$nt)" ;;
            notrun) l+="not run here (was $bp/$bt)" ;;
        esac
        out+=( "$l" )
    done
    for c in "${_KT_GATE_CMP_BONLY[@]}"; do
        IFS=$'\x1f' read -r vv m su s bt bp <<< "$c"
        if [[ -n "$bt" ]]; then out+=( "        $vv $m $su $s  base only (was $bp/$bt): not in this run" )
        else out+=( "        $vv $m $su $s  base only (not run there): not in this run" ); fi
    done
    printf '%s\n' "${out[@]}" > "$_KT_GATE_OUT/compare.txt"
    _KT_GATE_CMP_OUT=( "${out[@]:0:21}" )
    (( ${#out[@]} > 21 )) && _KT_GATE_CMP_OUT+=( "        ... $(( ${#out[@]} - 21 )) more: $_KT_GATE_OUTM/compare.txt" )
    return 0
}

# _kt_gate_jarr NAME... -> REPLY: a JSON array of the strings
_kt_gate_jarr() {
    local a o=""
    for a in "$@"; do _kt_gate_jstr "$a"; o+="${o:+, }$REPLY"; done
    REPLY="[$o]"
}

# kt_gate_json VERDICT RC MLINE — OUT/summary.json, the ledger record (never
# read back by gate): printf + _kt_gate_jstr, atomically
kt_gate_json() {
    local v="$1" rc="$2" mline="$3" t="$_KT_GATE_OUT/summary.json.tmp.$$" i k col sep fin a x id
    local kind vv m su s bt bp nt np b1 b2 b3 b4 b5
    local -a L=() parts=()
    local -A seenv=()
    printf -v fin '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    {
        printf '{\n  "gate": {\n'
        _kt_gate_jstr "$_KT_GATE_STARTED"; printf '    "started": %s,\n' "$REPLY"
        _kt_gate_jstr "$fin"; printf '    "finished": %s,\n' "$REPLY"
        _kt_gate_jstr "$_KT_GATE_ROOTM"; printf '    "root": %s,\n' "$REPLY"
        _kt_gate_jstr "$_KT_GATE_OUTM"; printf '    "out": %s,\n' "$REPLY"
        _kt_gate_jarr "${_KT_GATE_ARGV[@]}"; printf '    "argv": %s,\n' "$REPLY"
        printf '    "repos": {'; sep=""
        for (( i = 0; i < ${#_KT_GATE_REPO_N[@]}; i++ )); do
            _kt_gate_jstr "${_KT_GATE_REPO_N[i]}"; printf '%s\n      %s: ' "$sep" "$REPLY"
            if [[ -n "${_KT_GATE_REPO_S[i]}" ]]; then
                _kt_gate_jstr "${_KT_GATE_REPO_S[i]}"; printf '{"sha": %s, "dirty": %s}' "$REPLY" "${_KT_GATE_REPO_D[i]}"
            else
                printf '{"sha": null, "dirty": null}'
            fi
            sep=","
        done
        [[ -n "$sep" ]] && printf '\n    '
        printf '},\n'
        _kt_gate_jarr "${_KT_GATE_MODES[@]}"; printf '    "options": {"modes": %s, ' "$REPLY"
        _kt_gate_jarr "${_KT_GATE_CWDS[@]}"; printf '"cwds": %s, ' "$REPLY"
        printf '"repeat": %d, "rerun_failed": %d, "timeout": %d, ' "$_KT_GATE_REPEAT" "$_KT_GATE_RERUN" "$_KT_GATE_TIMEOUT"
        _kt_gate_jnum "$_KT_GATE_WORKERS"; printf '"workers": %s, ' "$REPLY"
        _kt_gate_jbool "$_KT_GATE_PARALLEL"; b1=$REPLY; _kt_gate_jbool "$_KT_GATE_FAILFAST"; b2=$REPLY
        _kt_gate_jbool "$_KT_GATE_WARM"; b3=$REPLY; _kt_gate_jbool "$_KT_GATE_KEEP"; b4=$REPLY
        _kt_gate_jbool "$_KT_GATE_CHANGED"; b5=$REPLY
        printf '"parallel": %s, "fail_fast": %s, "warm": %s, "keep": %s, "changed": %s, ' "$b1" "$b2" "$b3" "$b4" "$b5"
        _kt_gate_jarr "${_KT_GATE_SEL[@]}"; printf '"suites": %s, ' "$REPLY"
        _kt_gate_jarr "${_KT_GATE_ARGS[@]}"; printf '"args": %s}\n  },\n' "$REPLY"
        # --changed: the paths, all (why), the suites (why)
        if (( _KT_GATE_CHANGED )); then
            _kt_gate_jarr "${_KT_GATE_CHG_PATHS[@]}"; printf '  "changed": {"paths": %s, "all": ' "$REPLY"
            if [[ -n "$_KT_GATE_CHG_ALL" ]]; then _kt_gate_jstr "$_KT_GATE_CHG_ALL"; printf '%s' "$REPLY"; else printf 'null'; fi
            printf ', "suites": {'; sep=""
            for id in "${_KT_GATE_ALL_IDS[@]}"; do
                [[ -n "${_KT_GATE_CHG_WHY["$id"]+x}" ]] || continue
                _kt_gate_jstr "$id"; printf '%s%s: ' "$sep" "$REPLY"
                _kt_gate_jstr "${_KT_GATE_CHG_WHY["$id"]}"; printf '%s' "$REPLY"; sep=", "
            done
            printf '}},\n'
        fi
        printf '  "bashes": ['; sep=""
        for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
            printf '%s\n    {' "$sep"
            _kt_gate_jstr "${_KT_GATE_B_VER[k]}"; printf '"version": %s, ' "$REPLY"
            _kt_gate_jstr "${_KT_GATE_B_MIXED[k]}"; printf '"path": %s, ' "$REPLY"
            _kt_gate_jstr "${_KT_GATE_B_RT[k]}"; printf '"runtime": %s}' "$REPLY"
            sep=","
        done
        # totals per bash (key = its version; a second --bash of the same
        # version gets " (N)", N = its position)
        printf '\n  ],\n  "totals": {'; sep=""
        for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
            x="${_KT_GATE_B_VER[k]}"
            [[ -n "${seenv["$x"]+x}" ]] && x+=" ($(( k + 1 )))"
            seenv["$x"]=1
            _kt_gate_jstr "$x"; printf '%s\n    %s: {"cells": %d' "$sep" "$REPLY" "$_KT_GATE_PER"
            for a in "${_KT_GATE_VERDICTS[@]}"; do printf ', "%s": %d' "$a" "${_KT_GATE_KC["$k:$a"]:-0}"; done
            printf ', "passed_tests": %d, "total_tests": %d, "duration_ms": %d}' "${_KT_GATE_KC["$k:tp"]:-0}" \
                "${_KT_GATE_KC["$k:tt"]:-0}" "${_KT_GATE_KC["$k:ms"]:-0}"
            sep=","
        done
        printf '\n  },\n  "cells": ['; sep=""
        for (( i = 0; i < _KT_GATE_NCELLS; i++ )); do
            printf '%s\n    {' "$sep"; sep=","
            a=""
            for col in "${_KT_GATE_TSV_COLS[@]}" attempt1 ckk; do
                x="${_KT_GATE_ROW["$i:$col"]}"
                case "$col" in
                    idx|repeat|rc|total|passed|failed|warn|fail_lines|strays|attempts|duration_ms|reruns|rerun_pass)
                        _kt_gate_jnum "$x" ;;
                    flaky)
                        parts=()
                        [[ -n "$x" ]] && IFS=/ read -r -a parts <<< "$x"
                        _kt_gate_jarr "${parts[@]}" ;;
                    *) if [[ -n "$x" ]]; then _kt_gate_jstr "$x"; else REPLY=null; fi ;;
                esac
                printf '%s"%s": %s' "$a" "$col" "$REPLY"; a=", "
            done
            # the first 5 lines of the cell's [FAIL] messages
            L=()
            printf -v x '%s/cells/%03d/fails.txt' "$_KT_GATE_OUT" $(( i + 1 ))
            { mapfile -t -n 5 L < "$x"; } 2>/dev/null
            parts=()
            for x in "${L[@]}"; do [[ -n "$x" ]] && parts+=( "$x" ); done
            _kt_gate_jarr "${parts[@]}"; printf ', "fails": %s}' "$REPLY"
        done
        printf '\n  ],\n'
        if [[ -n "$_KT_GATE_COMPARE" ]]; then
            printf '  "compare": {'
            _kt_gate_jstr "$_KT_GATE_COMPARE"; printf '"arg": %s, ' "$REPLY"
            _kt_gate_jstr "$_KT_GATE_CMP_BASE"; printf '"base": %s, ' "$REPLY"
            _kt_gate_jstr "$_KT_GATE_CMP_FILE"; printf '"file": %s, ' "$REPLY"
            _kt_gate_jbool $(( ${#_KT_GATE_CMP_CH[@]} == 0 )); printf '"unchanged": %s, "changes": [' "$REPLY"
            a=""
            for x in "${_KT_GATE_CMP_CH[@]}"; do
                IFS=$'\x1f' read -r kind vv m su s bt bp nt np <<< "$x"
                printf '%s\n    {"kind": "%s", ' "$a" "$kind"; a=","
                _kt_gate_jstr "$vv"; printf '"bash_version": %s, ' "$REPLY"
                _kt_gate_jstr "$m"; printf '"mode": %s, ' "$REPLY"
                _kt_gate_jstr "$su"; printf '"cwd": %s, ' "$REPLY"
                _kt_gate_jstr "$s"; printf '"suite": %s, ' "$REPLY"
                if [[ -n "$bt" ]]; then printf '"base": {"total": %d, "passed": %d}, ' "$bt" "$bp"; else printf '"base": null, '; fi
                if [[ -n "$nt" ]]; then printf '"new": {"total": %d, "passed": %d}}' "$nt" "$np"; else printf '"new": null}'; fi
            done
            [[ -n "$a" ]] && printf '\n  '
            printf '], "base_only": ['
            a=""
            for x in "${_KT_GATE_CMP_BONLY[@]}"; do
                IFS=$'\x1f' read -r vv m su s bt bp <<< "$x"
                printf '%s\n    {' "$a"; a=","
                _kt_gate_jstr "$vv"; printf '"bash_version": %s, ' "$REPLY"
                _kt_gate_jstr "$m"; printf '"mode": %s, ' "$REPLY"
                _kt_gate_jstr "$su"; printf '"cwd": %s, ' "$REPLY"
                _kt_gate_jstr "$s"; printf '"suite": %s, ' "$REPLY"
                if [[ -n "$bt" ]]; then printf '"base": {"total": %d, "passed": %d}}' "$bt" "$bp"; else printf '"base": null}'; fi
            done
            [[ -n "$a" ]] && printf '\n  '
            printf ']},\n'
        fi
        _kt_gate_jstr "$mline"; printf '  "machine": %s,\n' "$REPLY"
        printf '  "exit": %d,\n  "verdict": "%s"\n}\n' "$rc" "$v"
    } > "$t" && mv -f -- "$t" "$_KT_GATE_OUT/summary.json"
}

kt_gate_main() {
    local k id l s
    _KT_GATE_ARGV=( "$@" )
    kt_gate_parse "$@"
    _KT_GATE_CYGPATH=""; command -v cygpath >/dev/null 2>&1 && _KT_GATE_CYGPATH=1
    _kt_gate_rt; _KT_GATE_RT="$REPLY"
    # the private temp: mixed (one default root for both runtimes), used in
    # this runtime's spelling (cygpath -u: /c/... in both)
    _kt_gate_ptmp; _KT_GATE_PTMPM="$REPLY" _KT_GATE_PTMP="$REPLY"
    [[ -n "$_KT_GATE_CYGPATH" ]] && _KT_GATE_PTMP="$(cygpath -u -- "$REPLY" 2>/dev/null)"
    _KT_GATE_PTMP="${_KT_GATE_PTMP:-$_KT_GATE_PTMPM}"
    kt_gate_root
    kt_gate_resolve
    _KT_GATE_CHG_PATHS=() _KT_GATE_CHG_ALL="" _KT_GATE_CHG_LINES=()
    declare -gA _KT_GATE_CHG_WHY=()
    if (( _KT_GATE_CHANGED )); then
        kt_gate_changed
        for id in "${!_KT_GATE_CHG_WHY[@]}"; do _KT_GATE_WANT["$id"]=1; done
        kt_gate_select
        # explicit suites too: the union
        for id in "${_KT_GATE_SEL[@]}"; do
            [[ -n "${_KT_GATE_CHG_WHY["$id"]+x}" ]] || _KT_GATE_CHG_LINES+=( "gate changed:   $id  <- named on the command line" )
        done
        if (( ${#_KT_GATE_SEL[@]} == 0 )); then
            # nothing to run: no OUT, no cell, no machine line (documented)
            printf '%s\n' "${_KT_GATE_CHG_LINES[@]}"
            if (( ${#_KT_GATE_CHG_PATHS[@]} == 0 )); then
                printf '[WARN] nothing changed: no suite selected, no cell runs (exit 0)\n'
            else
                printf '[WARN] the changes select no suite: no cell runs (exit 0)\n'
            fi
            return 0
        fi
    fi
    kt_gate_bashes
    kt_gate_compare_base
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
    kt_gate_cells
    kt_gate_out
    _kt_gate_mpath "$_KT_GATE_SELF"; _KT_GATE_SELFM="$REPLY"
    _KT_GATE_SW=8
    for s in "${_KT_GATE_SEL[@]}"; do
        (( _KT_GATE_REPEAT > 1 )) && s+="#$_KT_GATE_REPEAT"
        (( ${#s} > _KT_GATE_SW )) && _KT_GATE_SW=${#s}
    done
    (( _KT_GATE_SW > _KT_GATE_SUITE_MAX )) && _KT_GATE_SW=$_KT_GATE_SUITE_MAX
    _KT_GATE_VW=1
    for s in "${_KT_GATE_B_VER[@]}"; do (( ${#s} > _KT_GATE_VW )) && _KT_GATE_VW=${#s}; done
    _KT_GATE_SIG=0 _KT_GATE_SIGWHY="" _KT_GATE_STOPPED=0 _KT_GATE_STOP_T0=0
    _KT_GATE_SEG_T0=() _KT_GATE_SEG_T1=() _KT_GATE_SUMLINE=() _KT_GATE_SEGFAIL=() _KT_GATE_RESCUES=()
    _KT_GATE_K_STARTED=() _KT_GATE_K_DONE=() _KT_GATE_SHOWN_K=()
    declare -gA _KT_GATE_TOT=() _KT_GATE_KC=()
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

    printf -v _KT_GATE_STARTED '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    _kt_gate_say "gate ${_KT_GATE_STARTED:0:19} root=$_KT_GATE_ROOT out=$_KT_GATE_OUTM"
    kt_gate_repos
    _kt_gate_say "gate repos: $REPLY"
    local bl=""
    for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
        bl+="${bl:+  }${_KT_GATE_B_VER[k]} ${_KT_GATE_B_MIXED[k]}"
    done
    _kt_gate_say "gate bashes: $bl"
    local mx="${#_KT_GATE_SEL[@]} suite(s)"
    (( ${#_KT_GATE_MODES[@]} > 1 )) && mx+=" x 2 modes"
    (( ${#_KT_GATE_CWDS[@]} > 1 )) && mx+=" x 2 cwds"
    (( _KT_GATE_REPEAT > 1 )) && mx+=" x $_KT_GATE_REPEAT repeats"
    _kt_gate_say "gate cells: $_KT_GATE_NCELLS = ${#_KT_GATE_B_PATH[@]} bash x $mx (${_KT_GATE_SEL[*]})  mode=${_KT_GATE_MODES[*]} cwd=${_KT_GATE_CWDS[*]} timeout=${_KT_GATE_TIMEOUT}s${_KT_GATE_WORKERS:+ workers=$_KT_GATE_WORKERS}${_KT_GATE_ARGS[*]:+ args: ${_KT_GATE_ARGS[*]}}"
    l=""
    (( _KT_GATE_PARALLEL )) && l+=" --parallel (the runtimes at the same time: cross-runtime fork contention, DG3 - for orientation, not for a phase gate)"
    (( _KT_GATE_WARM )) && l+=" --warm (one .ckk dir per runtime)"
    (( _KT_GATE_FAILFAST )) && l+=" --fail-fast"
    (( _KT_GATE_RERUN > 0 )) && l+=" --rerun-failed $_KT_GATE_RERUN"
    [[ -n "$l" ]] && _kt_gate_say "gate options:$l"
    for l in "${_KT_GATE_CHG_LINES[@]}"; do _kt_gate_say "$l"; done
    [[ -n "${_KT_GATE_OUT_WARN:-}" ]] && _kt_gate_say "$_KT_GATE_OUT_WARN"
    for l in "${_KT_GATE_CMP_NOTES[@]}"; do _kt_gate_say "$l"; done
    [[ -n "$_KT_GATE_COMPARE" ]] && _kt_gate_say "gate compare: base $_KT_GATE_CMP_FILE"
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

    if (( _KT_GATE_PARALLEL && ${#_KT_GATE_B_PATH[@]} > 1 )); then
        local -a ks=()
        for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do kt_gate_spec "$k"; ks+=( "$k" ); done
        kt_gate_segments_run "${ks[@]}"
    else
        for (( k = 0; k < ${#_KT_GATE_B_PATH[@]}; k++ )); do
            (( _KT_GATE_SIG )) && break
            if (( _KT_GATE_FAILFAST )) && [[ -e "$_KT_GATE_OUT/FAILFAST" ]]; then
                _kt_gate_failfast_skip "$k"
                continue
            fi
            kt_gate_spec "$k"
            kt_gate_segments_run "$k"
        done
    fi
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
    elif (( ${_KT_GATE_TOT[FLAKY]:-0} > 0 && ${_KT_GATE_TOT[PASS]:-0} + ${_KT_GATE_TOT[NOTRUN]:-0} + ${_KT_GATE_TOT[FLAKY]:-0} == _KT_GATE_NCELLS )); then
        v=FLAKY; rc=4
    else
        v=FAIL; rc=1
    fi
    local mline
    printf -v mline '__GATE__:%s:%d:%d:%d:%d:%d:%d:%d:%d:%d' "$v" "$_KT_GATE_NCELLS" "${_KT_GATE_TOT[PASS]:-0}" \
        $(( ${_KT_GATE_TOT[FAIL]:-0} + ${_KT_GATE_TOT[CRASH]:-0} )) "${_KT_GATE_TOT[FLAKY]:-0}" "${_KT_GATE_TOT[ENV]:-0}" \
        "${_KT_GATE_TOT[TIMEOUT]:-0}" "${_KT_GATE_TOT[STRAY]:-0}" "${_KT_GATE_TOT[tp]:-0}" "${_KT_GATE_TOT[tt]:-0}"
    # the reports — also for an interrupted run (what finished) — before the
    # verdict line: whoever sees __GATE__ finds them complete
    kt_gate_rows
    kt_gate_tsv
    if [[ -n "$_KT_GATE_COMPARE" ]]; then
        kt_gate_compare
        for l in "${_KT_GATE_CMP_OUT[@]}"; do _kt_gate_say "$l"; done
    fi
    kt_gate_json "$v" "$rc" "$mline"
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
#   _KT_GATE_ENVRAW the files such a raw line belongs to (assoc; G4 review
#                   R2): a raw line is output of the file whose next tagged
#                   message ("... (NNN_name.sh)", or the runner's "[FAIL]
#                   NNN_name.sh: source aborted") follows it — a file's
#                   output comes as one block, threaded or single;
#                   _KT_GATE_SIGFREE=1 when a raw line had no tagged message
#                   after it
_kt_gate_seg_scan_log() {
    local raw line esc=$'\e' pre post cont=0 sumb=0 nf=${#_KT_GATE_FFILES[@]} n pend=0 tagf
    local -a L=()
    _KT_GATE_FAILS=() _KT_GATE_WARN=0 _KT_GATE_SIGHIT="" _KT_GATE_SIGFREE=0
    declare -gA _KT_GATE_ENVRAW=()
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
        [[ "$line" == 'Total tests:'* ]] && { (( pend )) && _KT_GATE_SIGFREE=1; pend=0; sumb=1; cont=0; continue; }
        # a pending raw fork-failure line belongs to the next tagged message's file
        if (( pend )) && [[ "$line" == '['[A-Z]*']'* ]]; then
            tagf=""
            if [[ "$line" =~ \(([0-9]{3}_[^()]*\.sh)\)$ ]]; then tagf="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^\[FAIL\]\ ([0-9]{3}_[^:]*\.sh):\ source\ aborted ]]; then tagf="${BASH_REMATCH[1]}"; fi
            [[ -n "$tagf" ]] && { _KT_GATE_ENVRAW["$tagf"]=1; pend=0; }
        fi
        if [[ "$line" == '[FAIL]'* ]]; then
            cont=0
            if (( nf > 0 )); then
                [[ -n "${_KT_GATE_FFILES["${line#'[FAIL] '}"]+x}" ]] && continue
            else
                [[ "$line" =~ ^\[FAIL\]\ [0-9]{3}_.*\.sh$ ]] && continue
            fi
            (( sumb )) && continue
            _KT_GATE_FAILS+=( "$line" ); cont=1
            if [[ "$line" == '[FAIL] '*': source aborted ('* && "$line" =~ $KT_ENV_FORK_FAILURE_RE ]]; then
                [[ -z "$_KT_GATE_SIGHIT" ]] && _KT_GATE_SIGHIT="${BASH_REMATCH[0]}"
                [[ "$line" =~ ^\[FAIL\]\ ([0-9]{3}_[^:]*\.sh):\ source\ aborted ]] && _KT_GATE_ENVRAW["${BASH_REMATCH[1]}"]=1
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
        if [[ "$line" =~ $KT_ENV_FORK_FAILURE_RE ]]; then
            [[ -z "$_KT_GATE_SIGHIT" ]] && _KT_GATE_SIGHIT="${BASH_REMATCH[0]}"
            (( sumb )) || pend=1
        fi
    done
    (( pend )) && _KT_GATE_SIGFREE=1
    return 0
}

# _kt_gate_seg_attempt C A [REL SEL] — run attempt A of cell C (0-based index
# into the spec arrays) in OUT/REL (default cells/NNN: its sandbox dirs, log,
# summary, fails.txt, strays.txt there; a --rerun-failed attempt has
# cells/NNN/rerun-R) with `-n SEL` appended to the runner's arguments when
# SEL is given (it wins over a -n of the gate's ARGS: the runner takes the
# last); sets _KT_GATE_A_{VERDICT,REASON,RC,T,P,F,MS,STRAYS,STRAYROWS},
# _KT_GATE_FAILS, _KT_GATE_WARN, _KT_GATE_FFILES; rc 2 when the segment must
# stop (the cell was interrupted)
_kt_gate_seg_attempt() {
    local c=$1 a=$2 idx="${KT_GATE_S_C_IDX[$1]}" suite="${KT_GATE_S_C_SUITE[$1]}" cd m wd jr why="" t0 t1
    local sum log nrow brk=0 timedout=0 stray=0 v="" r="" tt=0 pp=0 ff=0 src="" l nenv=0 envf="" rel="${3:-}" sel="${4:-}" ckk
    local -a S=()
    local -A envnames=()
    [[ -n "$rel" ]] || printf -v rel 'cells/%03d' "$idx"
    cd="$KT_GATE_S_OUT/$rel" m="$KT_GATE_S_OUTM/$rel"
    (( a > 1 )) && rm -rf -- "$cd/home" "$cd/tmp" "$cd/etc" "$cd/cwd" "$cd/ckk" 2>/dev/null
    mkdir -p -- "$cd/home" "$cd/tmp" "$cd/etc" "$cd/cwd"
    # --warm: the segment's one .ckk dir, shared by its cells (DG4)
    if (( KT_GATE_S_WARM )); then ckk="$KT_GATE_S_OUT/seg-$KT_GATE_S_SEG.ckk"; else ckk="$cd/ckk"; fi
    mkdir -p -- "$ckk"
    _KT_GATE_A_CKK="${ckk#"$KT_GATE_S_OUT"/}"
    log="$cd/log.txt" sum="$cd/summary"
    rm -f -- "$sum" 2>/dev/null
    export HOME="$cd/home" TMPDIR="$cd/tmp" TMP="$cd/tmp" TEMP="$cd/tmp"
    export USERPROFILE="$m/home" ProgramData="$m/etc" __KK_CFG_ETC="$cd/etc" KKLASS_CKK_DIR="$ckk"
    export KT_SUMMARY_FILE="$sum"
    wd="$cd/cwd"
    [[ "${KT_GATE_S_C_CWD[c]}" == suite ]] && wd="$KT_GATE_S_ROOT/$suite/tests"
    local -a cmd=( "$BASH" "$KT_GATE_S_ROOT/$suite/tests/tests.sh" --mode "${KT_GATE_S_C_MODE[c]}" )
    [[ -n "$KT_GATE_S_WORKERS" ]] && cmd+=( --workers "$KT_GATE_S_WORKERS" )
    cmd+=( "${KT_GATE_S_ARGS[@]}" )
    [[ -n "$sel" ]] && cmd+=( -n "$sel" )
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
                "env "*) nenv=$(( nenv + 1 )); [[ -z "$envf" ]] && envf="${l#env }"; envnames["${l#env }"]=1 ;;
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
        # summary), or a raw fork-failure line is in the log (review R4) —
        # only when EVERY failed file is such a file (G4 review R2: a fork
        # failure in one file must not hide a real failure in another); a
        # summary without a list of failed files: the old rule
        local -A envset=()
        local nonenv="" en=""
        for l in "${!envnames[@]}" "${!_KT_GATE_ENVRAW[@]}"; do envset["$l"]=1; done
        if (( ${#_KT_GATE_FFILES[@]} > 0 )); then
            for l in "${!_KT_GATE_FFILES[@]}"; do [[ -n "${envset[$l]+x}" ]] || nonenv+="${nonenv:+, }$l"; done
            for l in "${!envset[@]}"; do en+="${en:+, }$l"; done
            if [[ -z "$nonenv" ]] && (( ${#envset[@]} > 0 )); then
                v=ENV
                if (( nenv > 0 )); then r="fork failure in $nenv file(s) (runner): $envf"; else r="fork failure: $_KT_GATE_SIGHIT"; fi
            elif (( ${#envset[@]} > 0 )) || [[ -n "$_KT_GATE_SIGHIT" ]]; then
                r="+ fork failure in ${en:-the log}${_KT_GATE_SIGHIT:+ ($_KT_GATE_SIGHIT)}; not ENV: $nonenv failed as well"
            fi
        elif (( nenv > 0 )); then v=ENV; r="fork failure in $nenv file(s) (runner): $envf"
        elif [[ -n "$_KT_GATE_SIGHIT" ]]; then v=ENV; r="fork failure: $_KT_GATE_SIGHIT"; fi
    else
        v=PASS
    fi
    _KT_GATE_A_VERDICT=$v _KT_GATE_A_REASON="$r"
    printf '%s\n' "${_KT_GATE_FAILS[@]}" > "$cd/fails.txt"
    [[ "$v" == INTERRUPTED ]] && return 2
    return 0
}

# _kt_gate_seg_rerun C — --rerun-failed N (DG7) after cell C FAILED: exactly
# its failed files (the summary's `file NNN_Name.sh` lines, `-n` by their
# numbers), same mode/cwd, each attempt in a fresh sandbox of its own
# (cells/NNN/rerun-R), up to N times. A rerun that PASSES (every selected
# test passed, rc 0) -> FLAKY (_KT_GATE_RR_PASS = R, _KT_GATE_FLAKY = the
# files); a rerun that leaves a process -> STRAY; else FAIL stays. The
# counts, the [FAIL] lines and warn of the cell stay those of its full run.
# rc 2: interrupted (the segment stops; the cell stays FAIL).
_kt_gate_seg_rerun() {
    local c=$1 idx="${KT_GATE_S_C_IDX[$1]}" n i j t sel="" rel rc=0 r why=""
    local -a names=() nums=()
    # the failed files in number order (insertion sort, few of them)
    for n in "${!_KT_GATE_FFILES[@]}"; do
        if [[ ! "$n" =~ ^([0-9]+)_ ]]; then why="no test number in \"$n\""; break; fi
        t=$(( 10#${BASH_REMATCH[1]} ))
        for (( i = ${#names[@]}; i > 0 && nums[i-1] > t; i-- )); do names[i]="${names[i-1]}"; nums[i]="${nums[i-1]}"; done
        names[i]="$n"; nums[i]=$t
    done
    (( ${#names[@]} > 0 )) || why="the summary names no failed file"
    if [[ -n "$why" ]]; then
        _KT_GATE_A_REASON+="${_KT_GATE_A_REASON:+; }no rerun: $why"
        return 0
    fi
    for (( i = 0; i < ${#nums[@]}; i++ )); do
        (( i > 0 && nums[i] == nums[i-1] )) && continue
        sel+="${sel:+,}${nums[i]}"
    done
    # the full run's state: what the cell reports
    local v0="$_KT_GATE_A_VERDICT" r0="$_KT_GATE_A_REASON" rc0="$_KT_GATE_A_RC" t0="$_KT_GATE_A_T" p0="$_KT_GATE_A_P"
    local f0="$_KT_GATE_A_F" s0="$_KT_GATE_A_STRAYS" w0="$_KT_GATE_WARN" ck0="$_KT_GATE_A_CKK"
    local -a fl0=( "${_KT_GATE_FAILS[@]}" ) sr0=( "${_KT_GATE_A_STRAYROWS[@]}" )
    local -A ff0=()
    for n in "${!_KT_GATE_FFILES[@]}"; do ff0["$n"]=1; done
    local stray=0 sn=0 last=""
    for (( r = 1; r <= KT_GATE_S_RERUN; r++ )); do
        _kt_gate_seg_stopping && break
        printf -v rel 'cells/%03d/rerun-%d' "$idx" "$r"
        _kt_gate_seg_attempt "$c" 1 "$rel" "$sel"; rc=$?
        _KT_GATE_C_MS=$(( _KT_GATE_C_MS + _KT_GATE_A_MS ))
        _KT_GATE_RR=$r
        last="$_KT_GATE_A_VERDICT $_KT_GATE_A_P/$_KT_GATE_A_T"
        if (( rc == 2 )); then break; fi
        if [[ "$_KT_GATE_A_VERDICT" == STRAY ]]; then
            stray=1; sn=$_KT_GATE_A_STRAYS; sr0+=( "${_KT_GATE_A_STRAYROWS[@]}" ); break
        fi
        if [[ "$_KT_GATE_A_VERDICT" == PASS ]] && (( _KT_GATE_A_T > 0 )); then
            _KT_GATE_RR_PASS=$r; break
        fi
        # a passed sandbox is not needed, a failed one is kept
    done
    _KT_GATE_A_RC=$rc0 _KT_GATE_A_T=$t0 _KT_GATE_A_P=$p0 _KT_GATE_A_F=$f0 _KT_GATE_WARN=$w0 _KT_GATE_A_CKK="$ck0"
    _KT_GATE_FAILS=( "${fl0[@]}" ) _KT_GATE_A_STRAYROWS=( "${sr0[@]}" )
    _KT_GATE_FFILES=()
    for n in "${!ff0[@]}"; do _KT_GATE_FFILES["$n"]=1; done
    if (( stray )); then
        _KT_GATE_A_VERDICT=STRAY _KT_GATE_A_STRAYS=$(( s0 + sn ))
        _KT_GATE_A_REASON="rerun $_KT_GATE_RR of ${names[*]}: $sn stray process(es), stopped"
    elif (( _KT_GATE_RR_PASS )); then
        _KT_GATE_A_VERDICT=FLAKY _KT_GATE_A_STRAYS=$s0
        local IFS=/
        _KT_GATE_FLAKY="${names[*]}"
        IFS=$' \t\n'
        _KT_GATE_A_REASON="rerun $_KT_GATE_RR_PASS passed: ${names[*]}"
    else
        _KT_GATE_A_VERDICT=$v0 _KT_GATE_A_STRAYS=$s0
        _KT_GATE_A_REASON="$r0${r0:+; }$_KT_GATE_RR rerun(s) of ${names[*]} failed${last:+ (last: $last)}"
        (( _KT_GATE_RR == 0 )) && _KT_GATE_A_REASON="$r0${r0:+; }no rerun (the gate is stopping)"
    fi
    return "$rc"
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
        "attempt1=$3" "reruns=$_KT_GATE_RR" "rerun_pass=$_KT_GATE_RR_PASS" "flaky=$_KT_GATE_FLAKY" \
        "ckk=$_KT_GATE_A_CKK"
}

# _kt_gate_seg_emit C — the cell's progress line(s) into seg-N.lines
_kt_gate_seg_emit() {
    local c=$1 idx="${KT_GATE_S_C_IDX[$1]}" counts extra="" l n i i3
    printf -v i3 %03d "$idx"
    local -a out=()
    _kt_gate_cellvars "${KT_GATE_S_C_MODE[c]}" "${KT_GATE_S_C_CWD[c]}" "${KT_GATE_S_C_SUITE[c]}" "${KT_GATE_S_C_REP[c]}"
    counts="$_KT_GATE_A_P/$_KT_GATE_A_T"
    if [[ "$_KT_GATE_A_VERDICT" != PASS ]]; then
        printf -v extra '  log=cells/%03d/log.txt' "$idx"
    fi
    [[ -n "$_KT_GATE_A_REASON" ]] && extra+="  ($_KT_GATE_A_REASON)"
    [[ -n "$_KT_GATE_ATT1" ]] && extra+="  (attempt 1: ${_KT_GATE_ATT1%% *}, re-run once)"
    _kt_gate_line "$idx" "$_KT_GATE_A_VERDICT" "$counts" "$_KT_GATE_WARN" "$_KT_GATE_C_MS" "$extra"
    out+=( "$REPLY" )
    case "$_KT_GATE_A_VERDICT" in
        FAIL|ENV|FLAKY)
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

# _kt_gate_seg_hard VERDICT — rc 0 for a hard failure (--fail-fast stops)
_kt_gate_seg_hard() { [[ "$1" == FAIL || "$1" == TIMEOUT || "$1" == STRAY || "$1" == CRASH ]]; }

# _kt_gate_seg_failfast IDX VERDICT — --fail-fast: mark the first hard
# failure in OUT/FAILFAST (every segment stops before its next cell)
_kt_gate_seg_failfast() {
    (( KT_GATE_S_FAILFAST )) || return 0
    _kt_gate_seg_hard "$2" || return 0
    [[ -e "$KT_GATE_S_OUT/FAILFAST" ]] && return 0
    # the FIRST writer only (G4 review R8: two --parallel segments failing at
    # once): an atomic mkdir decides, across runtimes too
    mkdir -- "$KT_GATE_S_OUT/FAILFAST.lock" 2>/dev/null || return 0
    _kt_gate_put "$KT_GATE_S_OUT/FAILFAST" "cell $1 $2 (${_KT_GATE_VER} ${KT_GATE_S_C_SUITE[$3]})"
}

# _kt_gate_seg_cell C — a cell: attempt 1, an ENV retry, a --rerun-failed
# loop, result, line, sandbox removal. rc 2: the segment must stop
_kt_gate_seg_cell() {
    local c=$1 idx="${KT_GATE_S_C_IDX[$1]}" cd a=1 att=1 rc
    printf -v cd '%s/cells/%03d' "$KT_GATE_S_OUT" "$idx"
    mkdir -p -- "$cd"
    _KT_GATE_ATT1="" _KT_GATE_RR=0 _KT_GATE_RR_PASS=0 _KT_GATE_FLAKY=""
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
    if (( rc == 0 && KT_GATE_S_RERUN > 0 )) && [[ "$_KT_GATE_A_VERDICT" == FAIL ]]; then
        _kt_gate_seg_rerun "$c"; rc=$?
    fi
    _kt_gate_seg_result "$c" "$att" "$_KT_GATE_ATT1"
    _kt_gate_seg_emit "$c"
    _kt_gate_seg_failfast "$idx" "$_KT_GATE_A_VERDICT" "$c"
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

# _kt_gate_seg_skip_rest C — --fail-fast: cells C... of this segment are
# SKIPPED (a result each, one line for all)
_kt_gate_seg_skip_rest() {
    local c why="" f n=0
    { IFS= read -r why < "$KT_GATE_S_OUT/FAILFAST"; } 2>/dev/null
    for (( c = $1; c < ${#KT_GATE_S_C_IDX[@]}; c++ )); do
        printf -v f '%s/cells/%03d' "$KT_GATE_S_OUT" "${KT_GATE_S_C_IDX[c]}"
        _kt_gate_skip_put "$f" "${KT_GATE_S_C_IDX[c]}" "$_KT_GATE_VER" "$KT_GATE_S_BASH" "${KT_GATE_S_C_MODE[c]}" \
            "${KT_GATE_S_C_CWD[c]}" "${KT_GATE_S_C_SUITE[c]}" "${KT_GATE_S_C_REP[c]}" "--fail-fast: after $why"
        n=$(( n + 1 ))
    done
    printf 'gate fail-fast: %s: %d cell(s) skipped (after %s)\n' "$_KT_GATE_VER" "$n" "$why" >> "$_KT_GATE_F_LINES"
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
        if (( KT_GATE_S_FAILFAST )) && [[ -e "$KT_GATE_S_OUT/FAILFAST" ]]; then
            _kt_gate_seg_skip_rest "$c"; status=fail-fast; break
        fi
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
            _kt_gate_cellvars "${KT_GATE_S_C_MODE[c]}" "${KT_GATE_S_C_CWD[c]}" "${KT_GATE_S_C_SUITE[c]}" "${KT_GATE_S_C_REP[c]}"
            _kt_gate_seg_failfast "$idx" STRAY "$c"
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
    # --warm: the shared .ckk dir goes with the segment (kept with --keep)
    (( KT_GATE_S_WARM && ! KT_GATE_S_KEEP )) && rm -rf -- "$KT_GATE_S_OUT/seg-$n.ckk" 2>/dev/null
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
                "log=cells/$i3/log.txt" "reason=segment-killed" "attempt1=" "reruns=0" "rerun_pass=0" "flaky=" "ckk="
            _kt_gate_cellvars "${KT_GATE_S_C_MODE[c]}" "${KT_GATE_S_C_CWD[c]}" "${KT_GATE_S_C_SUITE[c]}" "${KT_GATE_S_C_REP[c]}"
            _kt_gate_line "$idx" INTERRUPTED "-" 0 0 "  (the segment was killed; its cells stopped by the watchdog)"
            printf '%s\n' "$REPLY" >> "$o/seg-$n.lines"
        fi
    fi
    # --warm: the segment's shared .ckk goes as on the normal end (G4 review R10)
    (( KT_GATE_S_WARM && ! KT_GATE_S_KEEP )) && rm -rf -- "$o/seg-$n.ckk" 2>/dev/null
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
