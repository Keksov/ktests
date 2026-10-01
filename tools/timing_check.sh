#!/bin/bash
# timing_check.sh — run test files (or a whole suite) repeatedly under a fork
# storm and report the pass rate: the load generator for timing assertions.
#
#   timing_check.sh [options] SUITE_DIR [FILTER...]
#
#   SUITE_DIR   a suite's tests/ directory (the one holding tests.sh), or the
#               unit directory above it
#   FILTER...   runner filters (e.g. 011_T6). Each filter is run on its own, in
#               the unit's own runner, as `tests.sh FILTER --mode single
#               --verbosity info < /dev/null`. With NO filter the WHOLE suite is
#               run threaded (`tests.sh --verbosity info`), because some flakes
#               only appear with sibling test files forking next to them.
#               A filter `n:SEL` is passed as the runner's own `-n SEL` (test
#               numbers, e.g. n:33 or n:1-5) — for a suite whose tests.sh fixes
#               the name filter itself (ktests/tests does).
#
# Options:
#   --storm LIST    storm levels, comma-separated (default 0,8). 0 = idle.
#   --reps K        runs per (target, storm level) (default 5)
#   --bash PATH     the bash under test, e.g. C:/bin/msys64/usr/bin/bash.exe.
#                   The script RE-EXECUTES ITSELF under it (with its directory
#                   first on PATH, so the runner's child `bash` is the same
#                   build), so the storm, the suite and the leak check all live
#                   in one cygwin runtime (see forkstorm.sh, "RUNTIMES").
#   --grep REGEX    also print the [PASS]/[FAIL] lines matching REGEX — the
#                   measured numbers (every [FAIL] line is always printed)
#   --workers N     threaded-mode workers for the suite mode (runner default 8)
#   --timeout SEC   per-run timeout (default 900)
#   --warmup SEC    storm warm-up before the first run of a level (default 1)
#   --log FILE      also append every output line to FILE
#   --timing REGEX  the [FAIL] lines of the TIMING assertions under study; a
#                   failed run whose every [FAIL] line matches is TIMING-FAIL,
#                   any other failed run FUNC-FAIL
#   --keep-dir DIR  keep the raw output of every run that did not PASS as
#                   DIR/storm<L>_rep<R>_<target>.out (the evidence)
#
# Output: one line per run —
#   storm=8  rep=3  011_T6  VERDICT  <[FAIL] lines>  | <lines matching --grep>
# VERDICT is PASS, TIMING-FAIL, FUNC-FAIL or ENV. ENV = the run FAILED and its
# output shows a cygwin fork failure (dofork / child_copy / 0xC000012D commit
# limit / fork: retry), or the runner itself could not start (rc 125-127):
# under memory pressure a forked child can even get a corrupt copy of its
# parent and return garbage from `$( )`, so ENV wins over any [FAIL] of the
# same run, and such a run blames the machine, not the test. A run that PASSED
# despite such a message stays PASS, marked "[env noise: ...]". Then a table per (target, storm level):
# passed/runs and the T/F/E counts. Exit status 0 when every run passed, 1
# otherwise, 2 on a usage error.
#
# Examples (from the kbool root):
#   bash ktests/tools/timing_check.sh --storm 0,8,16 --reps 10 \
#        --grep 'sec1 .*sec20' kcl/tinifile              # whole suite, threaded
#   bash ktests/tools/timing_check.sh --storm 8 --reps 10 \
#        --bash C:/bin/msys64/usr/bin/bash.exe kcl/tstringlist 013_Assign
#
# Storm levels run strictly one after another and never overlap: forkstorm.sh
# refuses to start while any storm worker is alive in this runtime, and an
# EXIT/INT/TERM trap stops the current storm.

TC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TC_SELF="$TC_DIR/$(basename "${BASH_SOURCE[0]}")"

tc_usage() { sed -n '2,/^$/p' "$TC_SELF" | sed 's/^# \{0,1\}//'; }

TC_STORMS="0,8"; TC_REPS=5; TC_BASH=""; TC_GREP=""; TC_WORKERS=""
TC_TIMEOUT=900; TC_WARMUP=1; TC_LOG=""; TC_TIMING=""; TC_KEEP=""
# cygwin fork failures (seen under a system commit limit: 0xC000012D is
# STATUS_COMMITMENT_LIMIT) — a run that shows one is ENV, not a test verdict.
# ONE definition (KT_ENV_FORK_FAILURE_RE), shared with the runner's retry rule.
source "$TC_DIR/../ktest_env_signatures.sh" || { printf 'timing_check: cannot load ktest_env_signatures.sh\n' >&2; exit 2; }
TC_ARGV=( "$@" )
TC_POS=()
while (( $# > 0 )); do
    case "$1" in
        --storm)   TC_STORMS="${2:?--storm needs a list}"; shift 2 ;;
        --reps)    TC_REPS="${2:?--reps needs a number}"; shift 2 ;;
        --bash)    TC_BASH="${2:?--bash needs a path}"; shift 2 ;;
        --grep)    TC_GREP="${2:?--grep needs a regex}"; shift 2 ;;
        --workers) TC_WORKERS="${2:?--workers needs a number}"; shift 2 ;;
        --timeout) TC_TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
        --warmup)  TC_WARMUP="${2:?--warmup needs seconds}"; shift 2 ;;
        --log)     TC_LOG="${2:?--log needs a file}"; shift 2 ;;
        --timing)  TC_TIMING="${2:?--timing needs a regex}"; shift 2 ;;
        --keep-dir) TC_KEEP="${2:?--keep-dir needs a directory}"; shift 2 ;;
        -h|--help) tc_usage; exit 0 ;;
        --)        shift; TC_POS+=( "$@" ); break ;;
        -*)        printf 'timing_check: unknown option %s\n' "$1" >&2; tc_usage >&2; exit 2 ;;
        *)         TC_POS+=( "$1" ); shift ;;
    esac
done

if (( ${#TC_POS[@]} < 1 )); then tc_usage >&2; exit 2; fi
[[ "$TC_REPS" =~ ^[1-9][0-9]*$ ]] || { printf 'timing_check: --reps must be >= 1\n' >&2; exit 2; }
[[ "$TC_STORMS" =~ ^[0-9]+(,[0-9]+)*$ ]] || { printf 'timing_check: --storm must be N[,N...]\n' >&2; exit 2; }

# --- re-exec under the bash under test -------------------------------------
if [[ -n "$TC_BASH" && -z "${TC_REEXEC:-}" ]]; then
    tc_b="$TC_BASH"
    if command -v cygpath >/dev/null 2>&1; then tc_b="$(cygpath -u "$tc_b")"; fi
    [[ -x "$tc_b" ]] || { printf 'timing_check: --bash %s is not executable\n' "$TC_BASH" >&2; exit 2; }
    exec env TC_REEXEC=1 PATH="$(dirname "$tc_b"):$PATH" "$tc_b" "$TC_SELF" "${TC_ARGV[@]}"
fi

source "$TC_DIR/forkstorm.sh"

# --- the suite ---------------------------------------------------------------
TC_SUITE="${TC_POS[0]}"
if [[ -f "$TC_SUITE/tests.sh" ]]; then
    TC_SUITE="$(cd "$TC_SUITE" && pwd)"
elif [[ -f "$TC_SUITE/tests/tests.sh" ]]; then
    TC_SUITE="$(cd "$TC_SUITE/tests" && pwd)"
else
    printf 'timing_check: no tests.sh in %s or %s/tests\n' "$TC_SUITE" "$TC_SUITE" >&2
    exit 2
fi
TC_FILTERS=( "${TC_POS[@]:1}" )
TC_TARGETS=( "${TC_FILTERS[@]}" )
(( ${#TC_TARGETS[@]} == 0 )) && TC_TARGETS=( "SUITE" )
IFS=',' read -r -a TC_LEVELS <<< "$TC_STORMS"

tc_say() {
    printf '%s\n' "$1"
    if [[ -n "$TC_LOG" ]]; then printf '%s\n' "$1" >> "$TC_LOG"; fi
}

# Scratch for one run's output and the storm heartbeats: ktests/.tmp is ignored
# by git and is not /tmp (shared with other sessions on this machine).
TC_TMP="$TC_DIR/../.tmp/timing_check.$$"
mkdir -p "$TC_TMP"
TC_CHILD=""

tc_cleanup() {
    # the run in flight first (TERM reaches `timeout`, which passes it on to
    # the suite), then the storm, then the scratch
    if [[ -n "$TC_CHILD" ]]; then
        kill -TERM "$TC_CHILD" 2>/dev/null || :
        wait "$TC_CHILD" 2>/dev/null || :
        TC_CHILD=""
    fi
    if [[ -n "$KT_STORM_TAG" ]]; then kt_storm_stop || :; fi
    rm -rf "$TC_TMP"
}
trap tc_cleanup EXIT
# A trapped signal interrupts `wait` at once (it would NOT interrupt a `$( )`,
# which is why the run below is a background job plus `wait`).
trap 'tc_cleanup; exit 130' INT TERM

declare -A TC_PASS=() TC_TOTAL=() TC_NT=() TC_NF=() TC_NE=()
[[ -n "$TC_KEEP" ]] && mkdir -p "$TC_KEEP"

# tc_run TARGET LEVEL REP -> TC_ST (PASS|TIMING-FAIL|FUNC-FAIL|ENV), TC_MEAS (the lines worth printing)
tc_run() {
    local target="$1" out rc line meas="" fails="" tfails_all=""
    local -a cmd=( "$BASH" "$TC_SUITE/tests.sh" )
    if [[ "$target" == "SUITE" ]]; then
        cmd+=( --verbosity info )
        [[ -n "$TC_WORKERS" ]] && cmd+=( --workers "$TC_WORKERS" )
    elif [[ "$target" == n:* ]]; then
        cmd+=( -n "${target#n:}" --mode single --verbosity info )
    else
        cmd+=( "$target" --mode single --verbosity info )
    fi
    ( cd "$TC_SUITE" && exec timeout "$TC_TIMEOUT" "${cmd[@]}" ) < /dev/null > "$TC_TMP/run.out" 2>&1 &
    TC_CHILD=$!
    wait "$TC_CHILD"; rc=$?
    TC_CHILD=""
    out="$(< "$TC_TMP/run.out")"
    local esc=$'\e'
    while IFS= read -r line; do
        # strip ANSI colour sequences
        while [[ "$line" == *"$esc["* ]]; do
            local pre="${line%%"$esc["*}" post="${line#*"$esc["}"
            post="${post#"${post%%[a-zA-Z]*}"}"; post="${post#?}"
            line="$pre$post"
        done
        line="${line#"${line%%[![:space:]]*}"}"
        if [[ "$line" =~ ^\[FAIL\]\ [0-9]{3}_[^\ ]*\.sh$ ]]; then
            :   # the runner's list of failed FILES — the case lines carry the reason
        elif [[ "$line" == "[FAIL]"* ]]; then
            fails+="${line#\[FAIL\] }; "
            if [[ -n "$TC_TIMING" && "$line" =~ $TC_TIMING ]]; then
                [[ "$tfails_all" == "" ]] && tfails_all=1
            else
                tfails_all=0
            fi
        elif [[ -n "$TC_GREP" && "$line" == "[PASS]"* && "$line" =~ $TC_GREP ]]; then
            meas+="${line#\[PASS\] }; "
        fi
    done <<< "$out"
    # Verdict. ENV first: a run whose output carries a cygwin fork failure, or
    # whose runner could not even be started (timeout's 125/126/127), says
    # nothing about the test — under a commit limit a forked child can also get
    # a corrupt copy of its parent and return garbage from `$( )`, so ENV wins
    # over any FAIL line of the same run. Otherwise a FAIL whose every [FAIL]
    # line matches --timing is TIMING-FAIL, anything else FUNC-FAIL.
    local envhit=''
    if [[ "$out" =~ $KT_ENV_FORK_FAILURE_RE ]]; then envhit="${BASH_REMATCH[0]}"; fi
    if (( rc == 125 || rc == 126 || rc == 127 )) && [[ -z "$envhit" ]]; then envhit="runner rc=$rc"; fi
    if [[ -z "$fails" && $rc -eq 0 && -n "$envhit" ]]; then
        # every case passed although the machine printed a fork failure (the
        # runner's retry absorbed it): a PASS, with the noise on record
        TC_ST=PASS; meas="[env noise: $envhit] $meas"
    elif [[ -n "$fails" || $rc -ne 0 || -n "$envhit" ]]; then
        (( rc == 124 )) && fails+="TIMEOUT after ${TC_TIMEOUT}s; "
        [[ -z "$fails" ]] && fails="runner rc=$rc; "
        if [[ -n "$envhit" ]]; then
            TC_ST=ENV; fails="[env: $envhit] $fails"
        elif [[ -n "$TC_TIMING" && "$tfails_all" == 1 ]]; then
            TC_ST=TIMING-FAIL
        else
            TC_ST=FUNC-FAIL
        fi
    else
        TC_ST=PASS
    fi
    if [[ "$TC_ST" != PASS && -n "$TC_KEEP" ]]; then
        TC_KEPT="$TC_KEEP/storm${2}_rep${3}_${target//[^A-Za-z0-9_.-]/_}.out"
        printf '%s\n' "$out" > "$TC_KEPT"
    fi
    TC_MEAS="${fails}${meas:+| $meas}"
    TC_MEAS="${TC_MEAS%; }"
}

tc_say "# timing_check: bash ${BASH_VERSION}, suite ${TC_SUITE}, targets ${TC_TARGETS[*]}, storm ${TC_STORMS}, reps ${TC_REPS}, $(printf '%(%F %T)T' -1)"
tc_any_fail=0
for lvl in "${TC_LEVELS[@]}"; do
    if (( lvl > 0 )); then
        # heartbeats: wait (up to 120 s) until every worker has built its
        # ballast and forked once, so the first run meets a storm in steady
        # state rather than 16 shells still defining functions
        rm -rf "$TC_TMP/hb"; mkdir -p "$TC_TMP/hb"
        KT_STORM_HEARTBEAT="$TC_TMP/hb" kt_storm_start "$lvl" \
            || { tc_say "# could not start a storm of $lvl — aborting"; exit 1; }
        for (( w = 0; w < 1200; w++ )); do
            tc_hb=( "$TC_TMP/hb"/* )
            [[ -e "${tc_hb[0]}" ]] && (( ${#tc_hb[@]} >= lvl )) && break
            sleep 0.1
        done
        sleep "$TC_WARMUP"
        kt_storm_alive
        tc_say "# storm $lvl started (tag $KT_STORM_TAG, $RESULT alive, all forking after ~$(( w / 10 )).$(( w % 10 )) s)"
    fi
    for (( r = 1; r <= TC_REPS; r++ )); do
        for tgt in "${TC_TARGETS[@]}"; do
            tc_run "$tgt" "$lvl" "$r"
            key="$tgt|$lvl"
            TC_TOTAL[$key]=$(( ${TC_TOTAL[$key]:-0} + 1 ))
            case "$TC_ST" in
                PASS)        TC_PASS[$key]=$(( ${TC_PASS[$key]:-0} + 1 )) ;;
                TIMING-FAIL) TC_NT[$key]=$(( ${TC_NT[$key]:-0} + 1 )); tc_any_fail=1 ;;
                FUNC-FAIL)   TC_NF[$key]=$(( ${TC_NF[$key]:-0} + 1 )); tc_any_fail=1 ;;
                ENV)         TC_NE[$key]=$(( ${TC_NE[$key]:-0} + 1 )); tc_any_fail=1 ;;
            esac
            tc_say "$(printf 'storm=%-3s rep=%-3s %-22s %-11s  %s' "$lvl" "$r" "$tgt" "$TC_ST" "${TC_MEAS:0:800}")"
        done
    done
    if (( lvl > 0 )); then
        tc_tag="$KT_STORM_TAG"
        if kt_storm_stop; then
            kt_storm_scan "$tc_tag"
            tc_say "# storm $lvl stopped (${RESULT} process(es) left)"
        else
            tc_say "# storm $lvl did NOT stop cleanly — aborting"
            exit 1
        fi
    fi
done

tc_say "# pass rate per target and storm level: passed/runs (T = TIMING-FAIL, F = FUNC-FAIL, E = ENV)"
for tgt in "${TC_TARGETS[@]}"; do
    row="$(printf '%-22s' "$tgt")"
    for lvl in "${TC_LEVELS[@]}"; do
        key="$tgt|$lvl"
        row+="$(printf '  storm %-3s %3s/%-3s (T%s F%s E%s)' "$lvl" "${TC_PASS[$key]:-0}" "${TC_TOTAL[$key]:-0}" \
                "${TC_NT[$key]:-0}" "${TC_NF[$key]:-0}" "${TC_NE[$key]:-0}")"
    done
    tc_say "$row"
done
exit "$tc_any_fail"
