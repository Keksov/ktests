#!/bin/bash
# ktest_runner.sh - Test discovery and execution engine
# Handles test file discovery, CLI parsing, sequential/parallel execution, and results aggregation
#
# Requires: ktest_core.sh and ktest_fixtures.sh to be sourced first

# Prevent multiple sourcing
if [[ -n "${_KTEST_RUNNER_SOURCED:-}" ]]; then
    return
fi
declare -g _KTEST_RUNNER_SOURCED=1

# Ensure core framework is available
if [[ -z "${_KTEST_CORE_SOURCED:-}" ]]; then
    echo "ERROR: ktest_core.sh must be sourced before ktest_runner.sh" >&2
    return 1
fi

# ============================================================================
# Global Variables and Constants
# ============================================================================

# Test execution configuration
# MODE: execution mode ("threaded" for parallel, "single" for sequential)
# WORKERS: number of parallel worker threads for threaded mode
#   Default of 8 is optimal for most systems (provides ~2.2x speedup on 16-core systems)
#   For systems with fewer cores: use 2-4 workers
#   For minimal overhead: use single mode (but slower for large test suites)
declare -g TEST_SELECTION=""
declare -g MODE="threaded"
declare -g WORKERS=8

# Array of selected test numbers
declare -ga TESTS_TO_RUN=()

# Array of failed test file names
declare -ga FAILED_TEST_FILES=()
# The failed files that died of a cygwin fork failure (gate G2, review R4):
# the runner's retry rule gave up on them — no END marker, no counts line, a
# capture matching KT_ENV_FORK_FAILURE_RE after the last attempt. A subset of
# FAILED_TEST_FILES; ktests.sh writes them to KT_SUMMARY_FILE as `env NAME`.
declare -ga ENV_TEST_FILES=()

# Constants for error handling
readonly KT_ERROR_COUNTS="__COUNTS__:1:0:1"

# The cygwin fork-failure signatures (KT_ENV_FORK_FAILURE_RE) — ONE definition,
# shared with tools/timing_check.sh.
_kt_runner_dir="${BASH_SOURCE[0]%/*}"
[[ "$_kt_runner_dir" == "${BASH_SOURCE[0]}" ]] && _kt_runner_dir="."
source "$_kt_runner_dir/ktest_env_signatures.sh" || {
    echo "ERROR: Failed to load ktest_env_signatures.sh" >&2
    unset _kt_runner_dir
    return 1
}
unset _kt_runner_dir

# A bash fatal diagnostic in a file's captured output: "<file>: line N: <msg>".
# Each of these aborts the top-level command that hit it (or the shell), so the
# asserts of that command vanish (ktests fix plan T1, PLAN.md §2.3). <file> is
# whatever file the failing code lives in — the test file or a library it
# calls. 5.3.9 says "arithmetic syntax error", which "syntax error" covers.
# Groups: 2 = file, 3 = line number, 4 = the message.
declare -g KT_BASH_FATAL_DIAG_RE='^([A-Za-z]:)?([[:alnum:]/._~-][^:]*): line ([0-9]+): (.*(expression recursion level exceeded|bad array subscript|invalid variable name|circular name reference|division by 0|unbound variable|syntax error).*)$'

# Any file's END marker (whatever its nonce), possibly glued to the end of a
# line: __KT_END_<nonce>__:<src rc>:<t>:<p>:<f>:<return-trap status or x>.
# Used to keep markers out of the printed output. Group 1 = the text before it.
declare -g KT_END_MARKER_STRIP_RE='^(.*)__KT_END_[A-Za-z0-9]+__:[0-9]+:[0-9]+:[0-9]+:[0-9]+:([0-9]+|x)$'

# ============================================================================
# Helper Functions
# ============================================================================

# Parse counts line and set count_total, count_passed, count_failed
# Usage: kt_runner_parse_counts "__COUNTS__:10:8:2"
kt_runner_parse_counts() {
    local counts_line="$1"
    if [[ -n "$counts_line" ]]; then
        IFS=':' read -r _ count_total count_passed count_failed <<<"$counts_line"
        count_total=${count_total:-0}; count_passed=${count_passed:-0}; count_failed=${count_failed:-0}
    else
        count_total=1; count_passed=0; count_failed=1
    fi
}

# Add counts to global test counters
# Usage: kt_runner_add_counts 10 8 2
kt_runner_add_counts() {
    local t="$1" p="$2" f="$3"
    TESTS_TOTAL=$((TESTS_TOTAL + t))
    TESTS_PASSED=$((TESTS_PASSED + p))
    TESTS_FAILED=$((TESTS_FAILED + f))
}

# Set error counts and related variables
# Usage: kt_runner_set_error_counts
kt_runner_set_error_counts() {
    counts_line="$KT_ERROR_COUNTS"
    count_total=1
    count_passed=0
    count_failed=1
}

# Clean filename: remove Windows line endings
# Usage: clean_name=$(kt_runner_clean_filename "$filename")
kt_runner_clean_filename() {
    local filename="$1"
    echo "${filename%$'\r'}"
}

# Extract the last __COUNTS__ line from captured test output without relying on external grep.
kt_runner_find_last_counts_line() {
    local output="$1"
    local line=""
    local counts=""

    if [[ -n "$output" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=${line%$'\r'}
            if [[ "$line" =~ ^__COUNTS__: ]]; then
                counts="$line"
            fi
        done < <(printf '%s' "$output")
    fi

    printf '%s' "$counts"
}

# Extract the first __COUNTS__ line from a result file without relying on external grep.
kt_runner_find_first_counts_in_file() {
    local result_file="$1"
    local line=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        if [[ "$line" =~ ^__COUNTS__: ]]; then
            printf '%s' "$line"
            return 0
        fi
    done < "$result_file"

    return 1
}

# Print output lines except internal __COUNTS__ and END markers. An END marker
# glued to a test's last line (printed without a newline) is cut off the line.
kt_runner_print_output_without_counts() {
    local output="$1"
    local line=""

    if [[ -n "$output" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=${line%$'\r'}
            if [[ "$line" == *__KT_END_* && "$line" =~ $KT_END_MARKER_STRIP_RE ]]; then
                line="${BASH_REMATCH[1]}"
                [[ -z "$line" ]] && continue
            fi
            if [[ ! "$line" =~ ^__COUNTS__: ]]; then
                printf '%s\n' "$line"
            fi
        done < <(printf '%s' "$output")
    fi
}

# Scan one file's captured output in a single pass.
# Usage: kt_runner_scan_capture "$output" "$nonce"
# Sets: _kt_scan_counts  the LAST __COUNTS__ line ("" if none). A normal run
#                        prints two (the wrapper's and kt_test_init's EXIT
#                        trap's), so count lines are never assumed unique;
#       _kt_scan_end     "1" when this attempt's END marker was printed, else "";
#       _kt_scan_end_rc/_t/_p/_f  the marker's source rc and counters;
#       _kt_scan_end_trc the status the wrapper's RETURN trap saw when the
#                        outer source returned, "x" when it did not fire;
#       _kt_scan_ndiag   the number of bash fatal diagnostics (KT_BASH_FATAL_DIAG_RE);
#       _kt_scan_diag    the first one, as "<file basename>:<line>: <message>".
# Only the marker carrying THIS attempt's nonce counts: a nested runner inside
# a test prints its own markers with other nonces. The marker may sit at the
# end of a line (the test's last output had no newline).
kt_runner_scan_capture() {
    local output="$1" nonce="$2" line=""
    local end_re="__KT_END_${nonce}__:([0-9]+):([0-9]+):([0-9]+):([0-9]+):([0-9]+|x)$"
    _kt_scan_counts=""; _kt_scan_end=""
    _kt_scan_end_rc=0; _kt_scan_end_t=0; _kt_scan_end_p=0; _kt_scan_end_f=0; _kt_scan_end_trc=x
    _kt_scan_ndiag=0; _kt_scan_diag=""

    [[ -n "$output" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        if [[ "$line" == __COUNTS__:* ]]; then
            _kt_scan_counts="$line"
        elif [[ -n "$nonce" && "$line" == *"__KT_END_${nonce}__:"* && "$line" =~ $end_re ]]; then
            _kt_scan_end=1
            _kt_scan_end_rc="${BASH_REMATCH[1]}"; _kt_scan_end_t="${BASH_REMATCH[2]}"
            _kt_scan_end_p="${BASH_REMATCH[3]}"; _kt_scan_end_f="${BASH_REMATCH[4]}"
            _kt_scan_end_trc="${BASH_REMATCH[5]}"
        elif [[ "$line" == *": line "* && "$line" =~ $KT_BASH_FATAL_DIAG_RE ]]; then
            _kt_scan_ndiag=$(( _kt_scan_ndiag + 1 ))
            if [[ -z "$_kt_scan_diag" ]]; then
                _kt_scan_diag="${BASH_REMATCH[2]##*/}:${BASH_REMATCH[3]}: ${BASH_REMATCH[4]}"
            fi
        fi
    done < <(printf '%s' "$output")
    return 0
}

# Judge a file from its scan and fold an abort into its counts.
# Usage: kt_runner_judge_capture "basename.sh" child_rc
# Reads the kt_runner_scan_capture results and counts_line; sets _kt_abort_cause.
# A file is ABORTED (ktests fix plan T1, PLAN.md §2) when:
#   - its END marker is missing: the shell exited mid-file (exit N, set -u,
#     ${v:?}, set -e, a replaced EXIT trap ...);
#   - its source returned rc >= 2 (an inline syntax error, a file-scope
#     `return N`). rc 1 alone is the ordinary status of a trailing false-y
#     command (`[[ … ]] && …`) and is no verdict;
#   - a file-scope `return` (round 3, T2/DT2): source rc < 2 and the status
#     the wrapper's RETURN trap saw when the outer source returned differs
#     from the source rc. A file that falls off its end gives both the status
#     of its last command; `return N` gives the status of the command BEFORE
#     it. Blind (no verdict) when the trap did not fire — the file installed
#     its own RETURN trap — and for `cmd || return N` with cmd's status N,
#     or a bare `return`;
#   - at END, TESTS_TOTAL > TESTS_PASSED + TESTS_FAILED: a test was started and
#     never closed — its block was aborted. One-sided on purpose: a test that
#     passes twice (p > t) is legal;
#   - its output carries a bash fatal diagnostic (KT_BASH_FATAL_DIAG_RE).
# An aborted file counts one more test, failed: counts_line becomes
# __COUNTS__:t+1:p:f+1 (t:p:f from the last counts line, 0:0:0 without one)
# and "[FAIL] <file>: source aborted (<cause>)" is appended to output_content —
# before the threaded runner writes its result file, whose collector reads the
# FIRST counts line and fails a file only on f > 0.
kt_runner_judge_capture() {
    local base="$1" child_rc="$2" cause=""
    local t=0 p=0 f=0

    if [[ -z "$_kt_scan_end" ]]; then
        cause="shell exited mid-file (child rc=$child_rc)"
    else
        if (( 10#$_kt_scan_end_rc >= 2 )); then
            cause="source returned rc=$_kt_scan_end_rc"
        elif [[ "$_kt_scan_end_trc" != x ]] && (( 10#$_kt_scan_end_trc != 10#$_kt_scan_end_rc )); then
            cause="file-scope return (source rc=$_kt_scan_end_rc after status $_kt_scan_end_trc)"
        fi
        if (( 10#$_kt_scan_end_t > 10#$_kt_scan_end_p + 10#$_kt_scan_end_f )); then
            cause+="${cause:+; }test aborted mid-block"
        fi
    fi
    if (( _kt_scan_ndiag > 0 )); then
        cause+="${cause:+; }bash error at $_kt_scan_diag"
        if (( _kt_scan_ndiag > 1 )); then
            cause+=" (+$(( _kt_scan_ndiag - 1 )) more)"
        fi
    fi
    _kt_abort_cause="$cause"
    [[ -z "$cause" ]] && return 0

    if [[ "$counts_line" =~ ^__COUNTS__:([0-9]+):([0-9]+):([0-9]+) ]]; then
        t="${BASH_REMATCH[1]}"; p="${BASH_REMATCH[2]}"; f="${BASH_REMATCH[3]}"
    fi
    counts_line="__COUNTS__:$(( 10#$t + 1 )):$(( 10#$p )):$(( 10#$f + 1 ))"
    output_content+="${output_content:+$'\n'}[FAIL] $base: source aborted ($cause)"
    return 0
}

# Show usage information
kt_runner_show_help() {
    cat <<'EOF'
Test Runner Usage: test_suite.sh [OPTIONS]

Options:
   -v, --verbosity LEVEL  Set verbosity level: "info" (verbose) or "error" (quiet)
                          Default: error
   
   -n, --tests SELECTION  Run specific tests by number or range
                          Examples: "1" "1,3,5" "1-5" "1-3,5,7-9"
   
   -m, --mode MODE        Execution mode: "threaded" or "single"
                          Default: threaded
   
   -w, --workers NUM      Number of worker threads in threaded mode
                          Default: 8 (optimal for most systems)
                          Recommended: 2-8 (higher values show diminishing returns)
   
   -h, --help            Show this help message

   Examples:
   ./test_suite.sh                           # Run all tests in threaded mode (8 workers)
   ./test_suite.sh -v info                   # Run all tests with verbose output
   ./test_suite.sh -n 1-5                    # Run tests 1-5 in threaded mode
   ./test_suite.sh -n 1,3,5 -m single       # Run tests 1, 3, 5 sequentially
   ./test_suite.sh -v info -m threaded -w 4 # Run all tests with 4 threads
   ./test_suite.sh -m threaded -w 2         # Run with 2 workers (resource-limited system)
EOF
}

# ============================================================================
# Test Selection Parsing
# ============================================================================

# Parse test selection string into TESTS_TO_RUN array
# Format: "1,2,3-5,10-12" expands to [1,2,3,4,5,10,11,12]
# Usage: kt_runner_parse_selection "1,3-5"
kt_runner_parse_selection() {
    local selection="$1"
    TESTS_TO_RUN=()
    
    local parts
    IFS=',' read -ra parts <<<"$selection"
    
    for part in "${parts[@]}"; do
        part="${part// /}"  # Remove whitespace
        
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # Range expansion: "3-5" -> [3,4,5]
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            for ((i=start; i<=end; i++)); do
                TESTS_TO_RUN+=("$i")
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            # Single test number
            TESTS_TO_RUN+=("$part")
        else
            kt_test_warning "Invalid test selection format: '$part'"
        fi
    done
}

# ============================================================================
# CLI Argument Parsing
# ============================================================================

# Parse command line arguments for test runner
# Supports: --verbosity, -v, -n/--tests, -m/--mode, -w/--workers
# Usage: kt_runner_parse_args "$@"
kt_runner_parse_args() {
    # Defaults
    VERBOSITY="${VERBOSITY:-error}"
    TEST_SELECTION=""
    MODE="threaded"
    WORKERS=8
    _KT_ASSERT_QUIET_MODE="${_KT_ASSERT_QUIET_MODE:-normal}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbosity=*)
                VERBOSITY="${1#*=}"
                shift
                ;;
            --verbosity|-v)
                if [[ $# -lt 2 ]]; then
                    kt_test_error "Option $1 requires a value"
                    kt_runner_show_help
                    exit 1
                fi
                VERBOSITY="$2"
                shift 2
                ;;
            -n|--tests)
                if [[ $# -lt 2 ]]; then
                    kt_test_error "Option $1 requires a value"
                    kt_runner_show_help
                    exit 1
                fi
                TEST_SELECTION="$2"
                shift 2
                ;;
            --tests=*)
                TEST_SELECTION="${1#*=}"
                shift
                ;;
            -m|--mode)
                if [[ $# -lt 2 ]]; then
                    kt_test_error "Option $1 requires a value"
                    kt_runner_show_help
                    exit 1
                fi
                MODE="$2"
                shift 2
                ;;
            --mode=*)
                MODE="${1#*=}"
                shift
                ;;
            -w|--workers)
                if [[ $# -lt 2 ]]; then
                    kt_test_error "Option $1 requires a value"
                    kt_runner_show_help
                    exit 1
                fi
                WORKERS="$2"
                shift 2
                ;;
            --workers=*)
                WORKERS="${1#*=}"
                shift
                ;;
            -h|--help)
                kt_runner_show_help
                exit 0
                ;;
            *)
                kt_test_error "Unknown option: $1"
                kt_runner_show_help
                exit 1
                ;;
        esac
    done
    
    # Validate arguments
    kt_test_validate_verbosity "$VERBOSITY" || exit 1
    kt_test_validate_mode "$MODE" || exit 1
    kt_test_validate_workers "$WORKERS" || exit 1
    
    # Update configuration
    kt_config_set "verbosity" "$VERBOSITY"
    
    # Parse test selection if provided
    if [[ -n "$TEST_SELECTION" ]]; then
        kt_runner_parse_selection "$TEST_SELECTION"
        kt_test_debug "Parsed test selection: ${TESTS_TO_RUN[*]}"
    fi

    # No `export` here (round 4, T7/DT7): on bash 5.2 it made a prefix assignment
    # (`MODE=single kt_runner_parse_args`) permanent. Children get these values
    # explicitly: the single-test wrapper passes VERBOSITY and both quiet modes,
    # the threaded runner exports in its own subshell.
}



# ============================================================================
# Test File Discovery
# ============================================================================

# Find test files matching patterns
# Handles Windows newline issues and numeric prefix patterns
# Usage: test_files=($(kt_runner_find_tests "/path/to/tests" "001_*.sh"))
kt_runner_find_tests() {
    local test_dir="$1"
    local pattern="${2:-[0-9][0-9][0-9]_*.sh}"
    
    if [[ ! -d "$test_dir" ]]; then
        kt_test_error "Test directory not found: $test_dir"
        return 1
    fi
    
    # Change to test directory for globbing
    local old_pwd
    old_pwd=$(pwd)
    cd "$test_dir" || return 1
    
    local test_files=()
    shopt -s nullglob  # Enable nullglob once for entire function
    
    if [[ ${#TESTS_TO_RUN[@]} -gt 0 ]]; then
        # Find specific test numbers
        for num in "${TESTS_TO_RUN[@]}"; do
            # Try various zero-padding patterns
            for pattern_var in "${num}_*.sh" "0${num}_*.sh" "00${num}_*.sh" "$(printf '%03d' "$num")_*.sh"; do
                for f in $pattern_var; do
                    [[ -f "$f" ]] && test_files+=("$f")
                done
            done
        done
    else
        # Find all test files with 3-digit prefix
        for f in [0-9][0-9][0-9]_*.sh; do
            [[ -f "$f" ]] && test_files+=("$f")
        done
    fi
    
    shopt -u nullglob  # Disable nullglob
    cd "$old_pwd" || return 1
    
    # Remove duplicates and clean newlines
    local cleaned=()
    declare -A seen
    for f in "${test_files[@]}"; do
        f=$(kt_runner_clean_filename "$f")
        if [[ ! -v seen["$f"] ]]; then
            seen["$f"]=1
            cleaned+=("$f")
        fi
    done
    
    # Print files with full paths
    for f in "${cleaned[@]}"; do
        echo "$test_dir/$f"
    done
}

# ============================================================================
# Common Test Execution Utilities
# ============================================================================

# The run's isolation folder (kbool `uses` U41, review R6). ktests.sh calls
# kt_runner_iso_begin once before running a suite (with the suite's files) and
# kt_runner_iso_end from its EXIT trap. A test file's HOME is
# $KT_ISO_ROOT/<file name>: all of them are created by ONE mkdir here (HOME is
# expected to be an existing folder — kcl tpath tests that), so a file costs no
# process of its own (review R6 measured 60-195 ms per file for a mkdir + rm
# each). Without a run folder (the runner functions called directly) a file's
# HOME is a path that does not exist (kbool only probes it with -f).
# kt_runner_iso_begin [FILE...] — remove stale kt_iso.<pid>[.*] folders of
# runners that are gone (one killed before its EXIT trap leaves at most one
# folder), then create and export KT_ISO_ROOT=${TMPDIR:-/tmp}/kt_iso.<this pid>
# with one empty folder per FILE name. rc 0 always (if mkdir fails the HOMEs
# are missing paths, still isolated).
# Owner marker (review R6): the folder holds .kt_owner = kt_runner_iso_owner.
# A dead-looking folder whose marker is another bash install's — or that has
# none (a legacy one, or one whose marker is not written yet) — is removed only
# once it is older than a day: the processes of another MSYS runtime sharing
# this TMPDIR are invisible to `kill -0` here, so its LIVE run (and the results
# dir inside) would be swept. The age is read by ONE `find -mmin` per sweep,
# only when such a folder is met.
kt_runner_iso_begin() {
    local tmp="${TMPDIR:-/tmp}" d pid f own mark aged=0
    local -a dirs=()
    local -A __kt_old=()
    kt_runner_iso_owner; own="$REPLY"
    for d in "$tmp"/kt_iso.*; do
        [[ -d "$d" && ! -L "$d" ]] || continue
        pid="${d##*/kt_iso.}"
        pid="${pid%%.*}"
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        [[ "$pid" == "$$" ]] && continue
        kill -0 "$pid" 2>/dev/null && continue
        mark=""
        [[ -f "$d/.kt_owner" ]] && { IFS= read -r mark < "$d/.kt_owner"; } 2>/dev/null
        if [[ "$mark" != "$own" ]]; then
            if (( ! aged )); then
                aged=1
                while IFS= read -r f; do
                    __kt_old["${f##*/}"]=1
                done < <(command find "$tmp/" -maxdepth 1 -name 'kt_iso.*' -mmin +1440 2>/dev/null)
            fi
            [[ -n "${__kt_old["${d##*/}"]+x}" ]] || continue
        fi
        rm -rf -- "$d"
    done
    export KT_ISO_ROOT="$tmp/kt_iso.$$"
    dirs=("$KT_ISO_ROOT")
    for f in "$@"; do dirs+=("$KT_ISO_ROOT/${f##*/}"); done
    mkdir -p -- "${dirs[@]}" 2>/dev/null || :
    printf '%s\n' "$own" > "$KT_ISO_ROOT/.kt_owner" 2>/dev/null || :
    return 0
}

# kt_runner_iso_owner — REPLY = the owner marker for kt_iso.* folders: the
# source of the `/` mount, i.e. the pid namespace (on MSYS the install's
# Windows folder, e.g. C:/bin/msys64 vs C:/bin/Git — two runtimes whose pids
# cannot see each other). Nothing else (review round 2, N3): $BASH differs for
# /bin/bash and /usr/bin/bash of ONE runtime, and the version adds nothing.
# "none" without a readable /proc/mounts. No fork. rc 0.
kt_runner_iso_owner() {
    local a b c root=""
    if [[ -r /proc/mounts ]]; then
        while read -r a b c; do
            [[ "$b" == / ]] && { root="$a"; break; }
        done < /proc/mounts
    fi
    REPLY="${root:-none}"
    return 0
}

# kt_runner_group_stop PID [GRACE] — stop the process group PID leads (a
# background job started under `set -m`: the subshell, xargs, the workers,
# their test files) with kt_runner_group_end, then reap PID (review R1) — but
# only once it is gone: a leader that ignores even KILL (cygwin: blocked in a
# FIFO open) would hang `wait`, and the trap that called this, for ever
# (critic P3b F11). A non-numeric or empty PID is a no-op; rc 0. GRACE in
# tenths of a second, default 30 (3 s). A caller that stops a group whose
# shell stops a group of its own passes a longer GRACE (ktests.sh: 50) than
# the inner one (the threaded runner: 30), or it would KILL that shell
# mid-stop.
kt_runner_group_stop() {
    local p="${1:-}" g="${2:-30}"
    [[ -n "$p" && "$p" != *[!0-9]* ]] || return 0
    kt_runner_group_end "$p" "$g" ""
    kill -0 "$p" 2>/dev/null || wait "$p" 2>/dev/null
    return 0
}
# kt_runner_group_end PGID GRACE [SELF] — end process group PGID and every
# process that descends from it outside it; SELF (a pid in the group: the
# watchdog) is spared and never signalled by pid. Never waits for a child;
# rc 0. KT_GROUP_END_STATS = "rounds=… scan_ms=… kill_rounds=… members=[…]
# outside=…" (diagnostics).
#   1. Snapshot (/proc, no fork): the group's members and their DESCENDANTS
#      OUTSIDE the group by the ppid chain — a test file's `timeout N cmd`
#      (GNU timeout makes its own process group), a `set -m` subgroup (critic
#      P3b F8) — each with its start time.
#   2. TERM + CONT the group ONCE (review round 2, N1: a STOPPED group keeps
#      the TERM pending). No re-send (supervisor 2026-10-16): a second TERM
#      cuts a test's cleanup short (a trapped TERM inside its EXIT trap exits
#      bash at once).
#   3. Wait without forking (read -t on a pty master) until the members are
#      gone; descendants that appear meanwhile are tracked too. Only then do
#      the descendants still alive get their TERM+CONT, ONCE, with at least
#      1 s before the KILL: a member may stop them itself (the run's shell
#      stops its worker group — our descendants), and a TERM from here as
#      well cut the threaded test files' cleanups short (P3b rs probe).
#   4. After GRACE, KILL what is left — the group, its members by pid, the tracked
#      descendants that are still the process first seen (same start time, or
#      still in the process group it had then: an exec on the Git runtime
#      changes the start time) — at most 10 rounds 0.1 s apart.
# Why "gone" is checked this way (the P3 master-sweep flake, 042/044): on the
# Git (cygwin) runtime a group signal sent while a member is still in its exec
# handover (a `sleep` forked moments before) is LOST for that member (probe:
# 20 of 20 such `sleep`s outlived the TERM, in the right group, their parent
# gone; 4 of 10 10 ms after the fork, 0 from 50 ms; a forked child that does
# not exec: 0 of 15; bash 5.3's msys runtime 0 of 20) — it is KILLed after
# GRACE. Under load such a member is also INVISIBLE to `kill -0 -- -PGID` for
# tens of ms (probe: 37 ms while `kill -0 <pid>` and its /proc stat already
# showed it), and on 5.3 /proc's listing missed one for a moment: so the
# members come from /proc as well, and the group counts as gone only when all
# views are empty twice, 0.1 s apart.
kt_runner_group_end() {
    local P="${1:-}" g="${2:-30}" self="${3:-}" __kt_gm="" __kt_e=0 __kt_k=0 __kt_n=0 __kt_dt=0
    local __kt_t __kt_end __kt_fd="" __kt_q __kt_st=0 __kt_t0 __kt_out __kt_mem
    local -A __kt_ds=()
    [[ -n "$P" && "$P" != *[!0-9]* ]] || return 0
    [[ -n "$g" && "$g" != *[!0-9]* ]] || g=30
    KT_GROUP_END_STATS=""
    __kt_t0="${EPOCHREALTIME/./}"
    kt_runner_group_scan "$P" "$self"
    __kt_st=$(( ${EPOCHREALTIME/./} - __kt_t0 ))
    __kt_out=${#__kt_ds[@]} __kt_mem="$__kt_gm"
    if ! kill -TERM -- "-$P" 2>/dev/null; then
        [[ "$P" != "$self" ]] && kill -TERM "$P" 2>/dev/null
    fi
    kill -CONT -- "-$P" 2>/dev/null || kill -CONT "$P" 2>/dev/null
    # a fork-free 0.1 s delay: read -t on a pty master that never has data
    exec {__kt_fd}<>/dev/ptmx 2>/dev/null || __kt_fd=""
    __kt_end=$(( ${EPOCHREALTIME/./} + g * 100000 ))
    while :; do
        __kt_n=$(( __kt_n + 1 ))
        __kt_t0="${EPOCHREALTIME/./}"
        kt_runner_group_scan "$P" "$self"
        __kt_st=$(( __kt_st + ${EPOCHREALTIME/./} - __kt_t0 ))
        for __kt_q in "${!__kt_ds[@]}"; do
            kill -0 "$__kt_q" 2>/dev/null || unset "__kt_ds[$__kt_q]"
        done
        if [[ -z "$__kt_gm" ]] \
            && { [[ -n "$self" ]] || ! kill -0 -- "-$P" 2>/dev/null; } \
            && { [[ "$P" == "$self" ]] || ! kill -0 "$P" 2>/dev/null; }; then
            # the members are gone — twice, 0.1 s apart (with SELF in the
            # group, kill -0 on the group always succeeds: /proc decides)
            if (( ++__kt_e >= 2 )); then
                (( ${#__kt_ds[@]} == 0 )) && break
                # the descendants outside the group get their TERM only now,
                # ONCE, with at least 1 s before the KILL: one that a member
                # still running would stop itself (the run's shell stops its
                # worker group, whose test files are our descendants) must not
                # get a second TERM — it would cut a test's EXIT-trap cleanup
                # short (P3b rs probe, threaded mode)
                if (( ! __kt_dt )); then
                    __kt_dt=1
                    for __kt_q in "${!__kt_ds[@]}"; do
                        kill -TERM "$__kt_q" 2>/dev/null
                        kill -CONT "$__kt_q" 2>/dev/null
                    done
                    __kt_t="${EPOCHREALTIME/./}"
                    (( __kt_end < __kt_t + 1000000 )) && __kt_end=$(( __kt_t + 1000000 ))
                fi
            fi
        else
            __kt_e=0
        fi
        if (( ${#__kt_ds[@]} > 0 || __kt_e < 2 )); then
            __kt_t="${EPOCHREALTIME/./}"
            if (( __kt_t >= __kt_end )); then
                # at most 10 KILL rounds, and never more than 3 s past the grace
                (( __kt_k++ >= 10 || __kt_t >= __kt_end + 3000000 )) && break
                [[ -z "$self" ]] && kill -KILL -- "-$P" 2>/dev/null
                [[ -n "$__kt_gm" ]] && kill -KILL $__kt_gm 2>/dev/null
                for __kt_q in "${!__kt_ds[@]}"; do
                    # only the process first seen (kt_runner_proc_same)
                    kt_runner_proc_same "$__kt_q" "${__kt_ds[$__kt_q]}" "$P" && kill -KILL "$__kt_q" 2>/dev/null
                done
            fi
        fi
        if [[ -n "$__kt_fd" ]]; then
            read -r -t 0.1 -u "$__kt_fd" _ 2>/dev/null
            (( $? > 128 )) || sleep 0.1
        else
            sleep 0.1
        fi
    done
    [[ -n "$__kt_fd" ]] && exec {__kt_fd}>&-
    KT_GROUP_END_STATS="rounds=$__kt_n scan_ms=$(( __kt_st / 1000 )) kill_rounds=$__kt_k members=[$__kt_mem] outside=$__kt_out"
    return 0
}
# kt_runner_group_scan PGID SELF — helper of kt_runner_group_end, which owns
# __kt_gm and the assoc array __kt_ds. One pass over /proc, no fork: __kt_gm =
# the live members of PGID except SELF; every process outside PGID whose
# parent is a member or an already tracked process (repeated down the chain)
# is added to __kt_ds (pid -> "start time:pgid"); a parent tracked from an
# earlier scan adopts children only while kt_runner_proc_same says it is still
# that process (pids wrap and are reused). /proc/<pid>/pgid and ppid cost
# ~30 us each on cygwin, /proc/<pid>/stat ~16 ms (it queries Windows): stat
# is read only for a member (zombies dropped), once for a new descendant and
# once per scan for a tracked parent.
# Off cygwin (no /proc/<pid>/pgid) both stay empty and the caller relies on
# kill -0 alone.
kt_runner_group_scan() {
    local __kt_f __kt_q __kt_g __kt_p __kt_l __kt_c=1
    local -A __kt_par=() __kt_in=() __kt_mb=() __kt_ok=()
    local -a __kt_x
    __kt_gm=""
    for __kt_f in /proc/[0-9]*/pgid; do
        __kt_q="${__kt_f#/proc/}"; __kt_q="${__kt_q%/pgid}"
        { read -r __kt_g < "$__kt_f"; } 2>/dev/null || continue
        { read -r __kt_p < "/proc/$__kt_q/ppid"; } 2>/dev/null || continue
        __kt_par[$__kt_q]="$__kt_p"
        [[ "$__kt_g" == "$1" ]] || continue
        __kt_in[$__kt_q]=1; __kt_mb[$__kt_q]=1
        [[ "$__kt_q" == "${2:-}" ]] && continue
        __kt_l=""; { IFS= read -r __kt_l < "/proc/$__kt_q/stat"; } 2>/dev/null
        __kt_x=( ${__kt_l##*) } )
        [[ "${__kt_x[0]:-}" == Z ]] && continue
        __kt_gm+="$__kt_q "
    done
    for __kt_q in "${!__kt_ds[@]}"; do __kt_in[$__kt_q]=1; done
    while (( __kt_c )); do
        __kt_c=0
        for __kt_q in "${!__kt_par[@]}"; do
            [[ -n "${__kt_in[$__kt_q]+x}" ]] && continue
            __kt_p="${__kt_par[$__kt_q]}"
            [[ "$__kt_p" != 1 && -n "${__kt_in[$__kt_p]+x}" ]] || continue
            # a parent tracked from an earlier scan must still be the process
            # recorded then (cygwin pids wrap and are reused — critic P3b r2
            # N3): checked once per scan; a reused one is dropped, its
            # children are not adopted
            if [[ -z "${__kt_mb[$__kt_p]+x}" && -z "${__kt_ok[$__kt_p]+x}" && -n "${__kt_ds[$__kt_p]+x}" ]]; then
                if kt_runner_proc_same "$__kt_p" "${__kt_ds[$__kt_p]}" "$1"; then
                    __kt_ok[$__kt_p]=1
                else
                    unset "__kt_ds[$__kt_p]" "__kt_in[$__kt_p]"
                    continue
                fi
            fi
            __kt_in[$__kt_q]=1; __kt_ok[$__kt_q]=1; __kt_c=1
            [[ "$__kt_q" == "$BASHPID" || "$__kt_q" == "$$" ]] && continue
            kt_runner_proc_start "$__kt_q"
            [[ -n "$REPLY" ]] && __kt_ds[$__kt_q]="$REPLY"
        done
    done
    __kt_gm="${__kt_gm% }"
    return 0
}
# kt_runner_proc_same PID RECORD PGID — rc 0 when PID is still the process
# recorded as RECORD ("start time:pgid", from kt_runner_proc_start): the same
# start time, or still in the recorded process group, or in PGID (on the Git
# runtime an exec changes the start time, not the group). rc 1 when it is
# gone, a zombie, or another process with a reused pid. No fork.
kt_runner_proc_same() {
    kt_runner_proc_start "$1"
    [[ -n "$REPLY" ]] || return 1
    [[ "${REPLY%%:*}" == "${2%%:*}" || "${REPLY#*:}" == "${2#*:}" || "${REPLY#*:}" == "$3" ]]
}
# kt_runner_proc_start PID — REPLY = "<start time>:<pgid>" of PID (fields 22
# and 5 of /proc/PID/stat), "" when it is gone or a zombie. No fork. rc 0.
kt_runner_proc_start() {
    local __kt_l=""
    local -a __kt_x
    REPLY=""
    { IFS= read -r __kt_l < "/proc/$1/stat"; } 2>/dev/null || return 0
    __kt_x=( ${__kt_l##*) } )
    [[ "${__kt_x[0]:-}" == Z ]] && return 0
    REPLY="${__kt_x[19]:-}:${__kt_x[2]:-}"
    return 0
}
# kt_runner_group_members PGID [STATE] — REPLY = the pids /proc shows in process
# group PGID (zombies excluded; with STATE, e.g. T, only those in that state),
# space-separated; "" without /proc. No fork. rc 0.
# Reads /proc/<pid>/pgid (cygwin: ~30 us) and /proc/<pid>/stat (~16 ms: it
# queries Windows) only for a match.
kt_runner_group_members() {
    local __kt_f __kt_g __kt_l __kt_out=""
    local -a __kt_x
    for __kt_f in /proc/[0-9]*/pgid; do
        { read -r __kt_g < "$__kt_f"; } 2>/dev/null || continue
        [[ "$__kt_g" == "$1" ]] || continue
        __kt_f="${__kt_f%/pgid}"
        __kt_l=""; { IFS= read -r __kt_l < "$__kt_f/stat"; } 2>/dev/null
        __kt_x=( ${__kt_l##*) } )
        [[ "${__kt_x[0]:-}" == Z ]] && continue
        [[ -n "${2:-}" && "${__kt_x[0]:-}" != "$2" ]] && continue
        __kt_out+="${__kt_f#/proc/} "
    done
    REPLY="${__kt_out% }"
    return 0
}

# The group's watchdog (review R1): a runner killed with SIGKILL runs no trap,
# and since its workers live in their own process group a group-wide kill of
# the runner no longer reaches them. So the runner holds the ONLY writer of a
# FIFO whose reader is a watchdog inside the worker group: when the runner dies
# the reader sees EOF and ends its own group (kt_runner_group_end); on the normal path the
# runner writes a line and the watchdog just exits. One mkfifo per group; no
# polling. Without a FIFO (mkfifo failed) there is no watchdog.
# kt_runner_group_open FIFO — create FIFO, open it read-write on a new fd of
# this shell; REPLY = the fd, or "" (rc 1) when that is not possible.
kt_runner_group_open() {
    local __kt_fd
    REPLY=""
    mkfifo -- "$1" 2>/dev/null || return 1
    exec {__kt_fd}<>"$1" || return 1
    REPLY="$__kt_fd"
    return 0
}
# kt_runner_group_watchdog FIFO FD [GRACE] — the FIRST command in the group's
# subshell: ignore SIGTTOU/SIGTTIN, open the FIFO's read end, close the
# inherited writer FD, start the watchdog on that read end. rc 0.
# - TTOU/TTIN (review round 2, N1): the group is a BACKGROUND process group; on
#   a `stty tostop` terminal its first write would stop it. Ignored, the write
#   just proceeds (and the test files inherit the ignore).
# - The read end is opened HERE, before the watchdog is spawned (N4): the open
#   cannot block, the inherited read-write FD is a writer. A watchdog that
#   opened the FIFO by path itself could do so after the runner had closed its
#   writer and then block in open() forever. The watchdog only reads the fd.
# - On EOF (the runner died without its trap) the watchdog ends its group the
#   way kt_runner_group_stop does (critic P3b F3; it used to TERM once, no
#   CONT, no KILL: a lost TERM or a TERM-ignoring member outlived it, a
#   Ctrl-Z'ed group stayed frozen): it ignores TERM itself from then on, runs
#   kt_runner_group_end on its group with itself as SELF (TERM+CONT once,
#   fork-free wait, KILL after GRACE tenths of a second, default 30), exits.
#   While it waits in `read` a TERM ends it as any member.
kt_runner_group_watchdog() {
    local __kt_fd="${2:-}" __kt_r __kt_g="${3:-30}" __kt_lp="$BASHPID"
    trap '' TTOU TTIN
    [[ -n "$__kt_fd" && "$__kt_fd" != *[!0-9]* ]] || return 0
    if ! exec {__kt_r}<"$1"; then
        exec {__kt_fd}>&-
        return 0
    fi 2>/dev/null
    exec {__kt_fd}>&-
    {
        # Ctrl-Z (TSTP to the group) must not stop the watchdog: a run that is
        # SIGKILLed while paused is then still ended (critic P3b F3)
        trap '' TSTP
        IFS= read -r -u "$__kt_r" __kt_l && exit 0
        trap '' TERM
        kt_runner_group_end "$__kt_lp" "$__kt_g" "$BASHPID"
        exit 0
    } >/dev/null 2>&1 &
    exec {__kt_r}<&-
    return 0
}
# kt_runner_group_suspend PID — the SIGTSTP trap of a shell that waits on the
# background group PID leads (review round 2, N6). Ctrl-Z stops the terminal's
# FOREGROUND group only; the run groups are background ones and kept running.
# So: pass TSTP to the group (a group shell that leads a group of its own does
# the same in turn), stop this shell, and on SIGCONT continue the group. The
# caller sets a flag in the trap and `wait`s again: the trap interrupted it.
kt_runner_group_suspend() {
    local p="${1:-}" __kt_r
    if [[ -n "$p" && "$p" != *[!0-9]* ]]; then
        kill -TSTP -- "-$p" 2>/dev/null || kill -TSTP "$p" 2>/dev/null
    fi
    kill -STOP "$BASHPID"
    if [[ -n "$p" && "$p" != *[!0-9]* ]]; then
        kill -CONT -- "-$p" 2>/dev/null || kill -CONT "$p" 2>/dev/null
        # a group CONT can be LOST for a member on the Git (cygwin) runtime
        # under load (044 N6 flake, probe n6.sh: the worker group's leader
        # stayed T, everything else ran on, the run never ended; a CONT by pid
        # ended it): CONT by pid whatever /proc still shows stopped (<= 10
        # rounds 0.1 s apart; a CONT to a running process does nothing)
        for (( __kt_r = 0; __kt_r < 10; __kt_r++ )); do
            kt_runner_group_members "$p" T
            [[ -z "$REPLY" ]] && break
            kill -CONT $REPLY 2>/dev/null
            sleep 0.1
        done
    fi
    return 0
}
# kt_runner_group_close FD — the normal end: release the watchdog, close FD.
kt_runner_group_close() {
    local __kt_fd="${1:-}"
    [[ -n "$__kt_fd" && "$__kt_fd" != *[!0-9]* ]] || return 0
    printf 'done\n' >&"$__kt_fd" 2>/dev/null
    exec {__kt_fd}>&-
    return 0
}

# kt_runner_iso_end — remove the run's isolation folder (the EXIT trap). Only
# THIS process's kt_iso.<pid> (round 5, DT9): ktests.sh traps signals before
# kt_runner_iso_begin, and an inherited KT_ISO_ROOT is never removed.
kt_runner_iso_end() {
    [[ -n "${KT_ISO_ROOT:-}" && "${KT_ISO_ROOT##*/}" == "kt_iso.$$" ]] && rm -rf -- "$KT_ISO_ROOT"
    return 0
}

# Execute a single test and return output and counts
# Usage: kt_runner_execute_single_test "/path/to/test.sh"
# Sets: output_content, counts_line, count_total, count_passed, count_failed
kt_runner_execute_single_test() {
    local test_file="$1"
    count_env=0

    [[ ! -f "$test_file" ]] && {
        output_content=""
        kt_runner_set_error_counts
        return 1
    }
    
    local clean_file=$(kt_runner_clean_filename "$test_file")
    
    kt_test_debug "Executing: $(basename "$clean_file")"
    
    # Show test file name in info mode
    if [[ "$VERBOSITY" == "info" ]]; then
        echo "[TEST] $(basename "$clean_file")"
    fi
    
    # Run test in subshell to isolate state.
    # Pass all values (including file paths) through the ENVIRONMENT rather than
    # splicing them into the bash -c script text, and keep the script body
    # single-quoted. This way a test path containing a quote or space cannot
    # break out of the generated shell code (the old form interpolated
    # '$clean_file' / '$KTESTS_LIB_DIR' into a double-quoted body).
    #
    # END marker (ktests fix plan T1): right after the `source` the wrapper
    # prints __KT_END_<nonce>__:<source rc>:<t>:<p>:<f>. The nonce is fresh per
    # attempt and handed over in the environment (then unset, so the test file
    # cannot echo it); only the marker with THIS nonce counts. A missing marker
    # means the shell exited mid-file — the counts line can still be there,
    # printed by kt_test_init's EXIT trap with the counts collected so far.
    # No EXIT trap is added to the test's shell: a test's own EXIT trap
    # replaces the framework's, and that case is a missing marker too.
    #
    # File-scope return (round 3, T2/DT2): a RETURN trap set around the
    # `source` records `$?` at trap entry when it fires for the OUTER source
    # (${#BASH_SOURCE[@]} == 0; a nested source fires at depth 1, a function
    # under set -T deeper) — the 6th END field, "x" if it did not fire. It is
    # removed right after the source. `$BASH_COMMAND` cannot be used: in the
    # trap it is always the wrapper's `source`. No fork; ~23 µs per nested
    # source and ~8.5 µs per function return under set -T (critic C2).
    #
    # Retry iff the attempt left NO END marker, NO counts line, AND its capture
    # is empty or shows a cygwin fork failure (KT_ENV_FORK_FAILURE_RE): under
    # heavy parallel load a worker's subprocess can die or fail to fork before
    # it prints anything — the source of intermittent suite-level failures in
    # threaded mode. A file that printed counts or its marker, or printed other
    # output and then died, is deterministic and is judged at once.
    #
    # Config isolation (kbool `uses` decision U41, 2026-10-09): every file runs
    # with KBOOL_CONFIG, KBOOL_HOME, USERPROFILE, ProgramData and PROGRAMDATA
    # unset, and HOME plus kbool's /etc hook (__KK_CFG_ETC = $HOME/etc/kbool,
    # never created) pointed at an empty folder of this file alone — a
    # developer's ~/.kbool/config, /etc/kbool, $ProgramData/kbool or exported
    # KBOOL_CONFIG cannot change what a test sees. A test may still install a
    # config of its own (export KBOOL_CONFIG / HOME ...); a standalone
    # `bash tests/X.sh` reads the environment as it is. BASH_ENV is emptied for
    # the file's shell and unset inside it (kbool `uses` U4 final review R6): a
    # developer's BASH_ENV would run in it and in every bash the test starts.
    # HOME = $KT_ISO_ROOT/<file name>, created empty for the whole suite by one
    # mkdir in kt_runner_iso_begin (ktests.sh) and removed by its EXIT trap — no
    # process per file (U3 review R6). Without that folder (the runner functions
    # called directly) HOME is a path that does not exist: kbool only probes it
    # with -f, so it holds no config either.
    local base="${clean_file##*/}"
    local __kt_iso="${KT_ISO_ROOT:-}/$base"
    if [[ -z "${KT_ISO_ROOT:-}" || ! -d "$__kt_iso" ]]; then
        __kt_iso="${TMPDIR:-/tmp}/kt_iso.${BASHPID}.none/home.${RANDOM}${RANDOM}"
    fi
    local __kt_attempt=0
    local __kt_max_attempts=3
    local __kt_nonce=""
    local __kt_child_rc=0
    counts_line=""
    while (( __kt_attempt < __kt_max_attempts )); do
        __kt_nonce="${BASHPID}x${RANDOM}${RANDOM}x${EPOCHREALTIME//[!0-9]/}"
        __kt_child_rc=0
        output_content="$(
            VERBOSITY="$VERBOSITY" \
            KK_OUTPUT_COUNTS=1 \
            _KT_ASSERT_QUIET_MODE="$_KT_ASSERT_QUIET_MODE" \
            _KTEST_QUIET_MODE="$_KTEST_QUIET_MODE" \
            KT_TESTS_DIR="$(dirname "$clean_file")" \
            KTESTS_LIB_DIR="$KTESTS_LIB_DIR" \
            KTEST_SOURCE_PATH="$KTESTS_LIB_DIR/ktest_source.sh" \
            KT_CLEAN_FILE="$clean_file" \
            KT_END_NONCE="$__kt_nonce" \
            HOME="$__kt_iso" \
            __KK_CFG_ETC="$__kt_iso/etc/kbool" \
            BASH_ENV="" \
            bash -c '
                unset KBOOL_CONFIG KBOOL_HOME USERPROFILE ProgramData PROGRAMDATA KT_ISO_ROOT BASH_ENV
                export VERBOSITY KK_OUTPUT_COUNTS _KT_ASSERT_QUIET_MODE _KTEST_QUIET_MODE KT_TESTS_DIR KTESTS_LIB_DIR KTEST_SOURCE_PATH
                _KT_END_NONCE="$KT_END_NONCE"; unset KT_END_NONCE
                source "$KTEST_SOURCE_PATH"
                _KT_RT_RC=x
                trap "_KT_RT_X=\$?; if (( \${#BASH_SOURCE[@]} == 0 )); then _KT_RT_RC=\$_KT_RT_X; fi" RETURN
                source "$KT_CLEAN_FILE"
                _KT_SRC_RC=$?
                trap - RETURN
                echo "__KT_END_${_KT_END_NONCE}__:$_KT_SRC_RC:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED:$_KT_RT_RC"
                # Always output counts (needed by runner for result tracking)
                echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
            ' "$clean_file" 2>&1
        )" || __kt_child_rc=$?
        kt_runner_scan_capture "$output_content" "$__kt_nonce"
        counts_line="$_kt_scan_counts"
        [[ -n "$_kt_scan_end" || -n "$counts_line" ]] && break
        [[ -z "$output_content" || "$output_content" =~ $KT_ENV_FORK_FAILURE_RE ]] || break
        __kt_attempt=$(( __kt_attempt + 1 ))
        # Brief backoff to let transient resource pressure (e.g. fork limits) ease.
        (( __kt_attempt < __kt_max_attempts )) && sleep 0.1
    done
    # the retry rule gave up on a fork failure: the file is ENV (count_env=1,
    # the caller lists it in ENV_TEST_FILES). Only then — a file that ran to
    # its END and failed is a verdict of the test, whatever its messages say.
    if [[ -z "$_kt_scan_end" && -z "$counts_line" && -n "$output_content" \
          && "$output_content" =~ $KT_ENV_FORK_FAILURE_RE ]]; then
        count_env=1
    fi

    # Fold an abort verdict (missing END, source rc, unclosed test, bash fatal
    # diagnostic) into counts_line and output_content.
    kt_runner_judge_capture "$base" "$__kt_child_rc"

    # A fixture dir of this file still present after its shell exited means
    # kt_test_init's EXIT trap did not run — the test replaced it with its own
    # `trap … EXIT` (round 3, T5/DT5) or the shell was killed. Remove it and
    # say so; the file's verdict is not changed. Fixture dirs are per run,
    # `<Name>.<file>.<pid>` (round 6, S2): only one whose owner is gone is
    # removed (kt_fixture_stale_dir) — a concurrent run of the same file (two
    # runs of one suite) keeps its live dir; the legacy `<Name>.<file>` too.
    # The dir's owner mark, the sibling `<dir>.owner`, goes with it.
    local __kt_fx __kt_tdir="${clean_file%/*}" __kt_fb="${base%.sh}"
    [[ "$__kt_tdir" == "$clean_file" ]] && __kt_tdir="."
    for __kt_fx in "$__kt_tdir/.tmp/"*".$__kt_fb" "$__kt_tdir/.tmp/"*".$__kt_fb."[0-9]*; do
        [[ -d "$__kt_fx" && ! -L "$__kt_fx" ]] || continue
        if [[ "$__kt_fx" != *".$__kt_fb" ]]; then
            kt_fixture_stale_dir "$__kt_fx" "${__kt_fx%".$__kt_fb."*}.$__kt_fb." || continue
        fi
        rm -rf -- "$__kt_fx" "$__kt_fx.owner"
        output_content+="${output_content:+$'\n'}[WARN] $base: fixture dir .tmp/${__kt_fx##*/} left behind (own EXIT trap?) - removed by the runner; register cleanup with kt_fixture_cleanup_register, never trap EXIT"
    done
    # A private `.tmp/<file name>` (a hand-made mkdir, round 5 T11/DT11) left
    # by this file: removed the same way, with its own WARN.
    # Guarded (review R2): a file named `.sh` / `..sh` has the name "" / "." —
    # that is `.tmp/` itself, never a private dir; a symlink is not followed.
    local __kt_pn="${base%.sh}"
    __kt_fx="$__kt_tdir/.tmp/$__kt_pn"
    if [[ -n "$__kt_pn" && "$__kt_pn" != . && "$__kt_pn" != .. && "$__kt_pn" != */* \
          && -d "$__kt_fx" && ! -L "$__kt_fx" ]]; then
        rm -rf -- "$__kt_fx"
        output_content+="${output_content:+$'\n'}[WARN] $base: private dir .tmp/${base%.sh} left behind - removed by the runner; use kt_fixture_tmpdir_create (removed at teardown)"
    fi

    # Parse counters (a file without a counts line was folded to 1:0:1 above)
    kt_runner_parse_counts "$counts_line"
}

# Filter test output based on verbosity level
# Usage: kt_runner_filter_output "full_output_text" "counts_line" count_failed
# Outputs filtered content to stdout
kt_runner_filter_output() {
    local output="$1"
    local counts_line="$2"
    local failed_count="$3"
    
    # Always show errors and warnings in all verbosity modes
    # Show full output on verbose or failure
    if [[ "$VERBOSITY" == "info" ]] || ((failed_count > 0)); then
        kt_runner_print_output_without_counts "$output"
    else
        # In error mode, still show [ERROR], [FAIL], [WARN], [ASSERTION FAILED], SCRIPT ERROR, and other error messages
        # For SCRIPT ERROR blocks, show the entire block until we hit __COUNTS__ or a blank line followed by non-error output
        # A bash fatal diagnostic (KT_BASH_FATAL_DIAG_RE) is always shown; END markers never are.
        local lines=()
        local in_error_block=0
        while IFS= read -r line; do
            if [[ "$line" == *__KT_END_* && "$line" =~ $KT_END_MARKER_STRIP_RE ]]; then
                line="${BASH_REMATCH[1]}"
                [[ -z "$line" ]] && continue
            fi
            if [[ "$line" == *": line "* && "$line" =~ $KT_BASH_FATAL_DIAG_RE ]]; then
                lines+=("$line")
            elif [[ "$line" == *"SCRIPT ERROR"* ]]; then
                in_error_block=1
                lines+=("$line")
            elif [[ "$line" =~ ^__COUNTS__: ]]; then
                # COUNTS line marks the end of error output
                in_error_block=0
            elif [[ $in_error_block -eq 1 ]]; then
                lines+=("$line")
            elif [[ "$line" == "["* ]] || [[ "$line" == *": No such file" ]] || [[ "$line" == *": command not found" ]]; then
                if [[ ! "$line" =~ ^__COUNTS__: ]]; then
                    lines+=("$line")
                fi
            fi
        done < <(printf '%s\n' "$output" | sed -e 's/\r$//')
        if (( ${#lines[@]} > 0 )); then
            printf '%s\n' "${lines[@]}"
        fi
    fi
}

# ============================================================================
# Sequential Test Execution
# ============================================================================

# Run tests sequentially in isolated subshells
# Usage: kt_runner_execute_sequential test_file1 test_file2 ...
kt_runner_execute_sequential() {
    local test_file

    for test_file in "$@"; do
        # Execute test and get results. A missing file is counted 1:0:1 and
        # listed as FAILED, as in threaded mode (round 3, T4b).
        kt_runner_execute_single_test "$test_file"
        
        # Update global counters
        kt_runner_add_counts "$count_total" "$count_passed" "$count_failed"
        
        # Track failed test files
        if ((count_failed > 0)); then
            local clean_file=$(kt_runner_clean_filename "$test_file")
            FAILED_TEST_FILES+=("$(basename "$clean_file")")
            (( count_env )) && ENV_TEST_FILES+=("$(basename "$clean_file")")
        fi
        
        # Filter and display output
        kt_runner_filter_output "$output_content" "$counts_line" "$count_failed"
    done
}

# ============================================================================
# Threaded Test Execution
# ============================================================================

# Run tests with worker threads
# Usage: kt_runner_execute_threaded test_file1 test_file2 ...
kt_runner_execute_threaded() {
    local test_files=("$@")
    local num_files=${#test_files[@]}
    
    if [[ $num_files -eq 0 ]]; then
        return 0
    fi
    
    # For very small number of tests, use sequential to avoid overhead
    if [[ $num_files -le 1 ]]; then
        kt_runner_execute_sequential "${test_files[@]}"
        return 0
    fi

    # The results dir (ktests round 5, T9/DT9) lives in this run's isolation
    # folder kt_iso.<pid> when ktests.sh made one, else it is named
    # kt_iso.<pid>.results.* — either way the dead-pid sweep of the next
    # kt_runner_iso_begin removes it after a SIGKILL. The run folder is taken
    # only when it is THIS process's (never an inherited KT_ISO_ROOT).
    local results_dir __kt_rbase="${TMPDIR:-/tmp}/kt_iso.$$.results"
    if [[ -n "${KT_ISO_ROOT:-}" && "${KT_ISO_ROOT##*/}" == "kt_iso.$$" && -d "$KT_ISO_ROOT" ]]; then
        __kt_rbase="$KT_ISO_ROOT/results"
    fi
    results_dir=$(mktemp -d "$__kt_rbase.XXXXXX") || {
        kt_test_error "Failed to create temporary directory for threaded execution"
        kt_runner_execute_sequential "${test_files[@]}"
        return $?
    }
    # a results dir outside a run folder carries the owner marker itself (R6)
    if [[ "$__kt_rbase" != "${KT_ISO_ROOT:-}/results" ]]; then
        kt_runner_iso_owner; printf '%s\n' "$REPLY" > "$results_dir/.kt_owner" 2>/dev/null || :
    fi

    # TERM/INT/HUP while the workers run: stop the worker process group, remove
    # the results dir and exit 128+N — the exit runs the caller's EXIT trap
    # (bash 5.2 runs no EXIT trap on a signal by itself). The caller's own
    # traps are restored on return. The workers run in a BACKGROUND process
    # group this shell `wait`s on (review R1): a trap is deferred while a
    # foreground child runs, so a TERM to this pid alone used to wait for the
    # whole suite; `wait` returns at once on a trapped signal.
    local __kt_old_traps __kt_wpid="" __kt_jc=0 __kt_wfd="" __kt_susp=0 __kt_wrc=0
    __kt_old_traps="$(trap -p TERM INT HUP TSTP)"
    trap '__kt_susp=1; kt_runner_group_suspend "$__kt_wpid"' TSTP
    trap 'kt_runner_group_stop "$__kt_wpid"; rm -rf -- "$results_dir"; exit 143' TERM
    trap 'kt_runner_group_stop "$__kt_wpid"; rm -rf -- "$results_dir"; exit 130' INT
    trap 'kt_runner_group_stop "$__kt_wpid"; rm -rf -- "$results_dir"; exit 129' HUP
    
    # Actual number of workers to use
    local num_workers=$WORKERS
    [[ $num_workers -gt $num_files ]] && num_workers=$num_files

    # The worker function, the exports the workers need and the spawn all live
    # in ONE subshell (round 3, T3/DT3): the caller keeps its values, export
    # attributes and functions — on 5.2.37 an `export` of a name given as a
    # prefix assignment (`VERBOSITY=error kt_runner_execute_threaded …`) used
    # to outlive the call. The collector below reads only the result files.
    # set -m only around the spawn: the subshell leads its own process group
    # (kt_runner_group_stop kills it with xargs, the workers and their test
    # files); stdin is /dev/null as for any background job.
    kt_runner_group_open "$results_dir/.kt_watch" && __kt_wfd="$REPLY"
    [[ $- == *m* ]] && __kt_jc=1
    set -m
    (
        kt_runner_group_watchdog "$results_dir/.kt_watch" "$__kt_wfd"
        # Execute a single test and save its results
        run_test() {
            local test_file="$1"
            local result_file="$2"

            # Use common execution function
            kt_runner_execute_single_test "$test_file"

            # Save results to file (a fork-failure death: a marker beside it)
            {
                echo "$counts_line"
                echo "$output_content"
            } > "$result_file"
            (( count_env )) && : > "$result_file.env"
        }

        export -f run_test kt_test_debug kt_runner_execute_single_test kt_test_reset_counts kt_runner_clean_filename kt_runner_parse_counts kt_runner_set_error_counts kt_runner_find_last_counts_line kt_runner_scan_capture kt_runner_judge_capture kt_fixture_stale_dir kt_fixture_owner_mark
        # KT_ERROR_COUNTS: a missing file's counts line in a worker (T4)
        export results_dir VERBOSITY _KT_ASSERT_QUIET_MODE _KTEST_QUIET_MODE KTESTS_LIB_DIR KT_ENV_FORK_FAILURE_RE KT_BASH_FATAL_DIAG_RE KT_ERROR_COUNTS

        # Run tests in parallel using xargs or manual background processes
        if command -v xargs &>/dev/null; then
            # Use xargs for better parallelization if available
            # BASH_ENV="": a developer's BASH_ENV runs in no worker (U41 R6 of
            # the kbool `uses` U4 final review; each file's shell drops it too)
            printf '%s\n' "${test_files[@]}" | BASH_ENV="" xargs -P "$num_workers" -I {} bash -c '
                run_test "$1" "$2/$(basename "$1").result"
            ' _ {} "$results_dir"
        else
            # Manual parallel execution using background processes. The
            # watchdog is a running job too (+1), and a bare `wait` would wait
            # for it: wait for the workers by pid.
            local __kt_cap=$num_workers __kt_wp=()
            [[ -n "$__kt_wfd" ]] && __kt_cap=$(( num_workers + 1 ))
            for ((i=0; i<num_files; i++)); do
                # Limit number of concurrent jobs
                while [[ $(jobs -r | wc -l) -ge $__kt_cap ]]; do
                    sleep 0.01
                done

                run_test "${test_files[$i]}" "$results_dir/${i}.result" &
                __kt_wp+=($!)
            done
            wait "${__kt_wp[@]}"
        fi
    ) < /dev/null &
    __kt_wpid=$!
    (( __kt_jc )) || set +m
    # a TSTP trap interrupts the wait: wait again after the resume (N6)
    while :; do
        __kt_susp=0
        wait "$__kt_wpid"; __kt_wrc=$?
        (( __kt_susp )) || break
    done
    kt_runner_group_close "$__kt_wfd"
    # the worker group must be empty too (round 5, P3b): a test file's leaked
    # background process is named and stopped (strays.sh, sourced by ktests.sh)
    if declare -F kt_strays_group_settle >/dev/null; then kt_strays_group_settle "$__kt_wpid" "${SUITE_NAME:-run} (threaded workers)" || :; fi

    # Collect and aggregate results
    local total_t=0 total_p=0 total_f=0
    for result_file in "$results_dir"/*.result; do
        [[ ! -f "$result_file" ]] && continue

        # Reset per-iteration so the else-branch and the filter call below never
        # see a previous iteration's failure count.
        local t=0 p=0 f=0
        local counts_line
        counts_line=$(kt_runner_find_first_counts_in_file "$result_file")

        if [[ -n "$counts_line" ]]; then
            kt_runner_parse_counts "$counts_line"
            t=$count_total; p=$count_passed; f=$count_failed
            total_t=$((total_t + t))
            total_p=$((total_p + p))
            total_f=$((total_f + f))
        else
            # Test failed to report counters
            t=1; f=1
            total_t=$((total_t + 1))
            total_f=$((total_f + 1))
        fi

        # Track failed test files. Result files are named two ways: the xargs
        # path names them "<basename>.result", the manual-background path uses
        # "<index>.result". Handle both so the failed-file list is populated in
        # threaded mode (it silently was not before).
        if ((f > 0)); then
            local failed_name="${result_file##*/}"
            failed_name="${failed_name%.result}"
            if [[ "$failed_name" =~ ^[0-9]+$ ]] && [[ $failed_name -lt ${#test_files[@]} ]]; then
                failed_name="$(basename "${test_files[$failed_name]}")"
            fi
            FAILED_TEST_FILES+=("$failed_name")
            [[ -e "$result_file.env" ]] && ENV_TEST_FILES+=("$failed_name")
        fi

        # Show output with filtering
        local output_content
        output_content=$(cat "$result_file")
        kt_runner_filter_output "$output_content" "$counts_line" "$f"
    done

    # A file without a result file (review R6: its worker died, or the results
    # dir was removed under the run) is 1:0:1 and FAILED by name, as a missing
    # test file is — never a silently lower total. xargs names the files
    # <basename>.result, the manual path <index>.result.
    local __kt_i __kt_b
    for (( __kt_i = 0; __kt_i < num_files; __kt_i++ )); do
        __kt_b="${test_files[$__kt_i]##*/}"
        [[ -f "$results_dir/$__kt_b.result" || -f "$results_dir/$__kt_i.result" ]] && continue
        total_t=$((total_t + 1)); total_f=$((total_f + 1))
        FAILED_TEST_FILES+=("$__kt_b")
        kt_runner_filter_output "[FAIL] $__kt_b: no result file (its worker died or the results dir was removed during the run)" "" 1
    done

    # Update global counters
    kt_runner_add_counts "$total_t" "$total_p" "$total_f"
    
    # Cleanup, then the caller's TERM/INT/HUP traps back (trap - first: a
    # signal the caller never trapped is default again)
    rm -rf -- "$results_dir"
    trap - TERM INT HUP TSTP
    eval "$__kt_old_traps"
}

# ============================================================================
# Main Execution
# ============================================================================

# Execute all discovered tests
# Usage: kt_runner_execute_tests "/path/to/tests"
kt_runner_execute_tests() {
    local test_dir="${1:-.}"
    local filter="${2:-}"

    if [[ ! -d "$test_dir" ]]; then
        kt_test_error "Test directory not found: $test_dir"
        return 1
    fi

    # Reset counters before execution
    kt_test_reset_counts
    FAILED_TEST_FILES=() ENV_TEST_FILES=()

    # Find test files. A non-empty filter must apply to what actually RUNS —
    # previously the filter only shaped the displayed list while execution
    # re-discovered everything, so a custom filter silently ran all tests.
    local test_files=()
    if [[ -n "$filter" ]]; then
        while IFS= read -r file; do
            test_files+=("$file")
        done < <(kt_runner_find_tests "$test_dir" | grep "$filter")
    else
        while IFS= read -r file; do
            test_files+=("$file")
        done < <(kt_runner_find_tests "$test_dir")
    fi
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        kt_test_error "No test files found in $test_dir"
        return 1
    fi
    
    # Show test execution info
    if [[ "$VERBOSITY" == "info" ]]; then
        kt_test_section "Test Execution"
        echo "Found ${#test_files[@]} test file(s)"
        echo "Mode: $MODE"
        if [[ "$MODE" == "threaded" ]]; then
            echo "Workers: $WORKERS"
        fi
        echo ""
    fi
    
    # Execute tests
    case "$MODE" in
        single)
            kt_runner_execute_sequential "${test_files[@]}"
            ;;
        threaded)
            kt_runner_execute_threaded "${test_files[@]}"
            ;;
        *)
            kt_test_error "Unknown execution mode: $MODE"
            return 1
            ;;
    esac
}

# ============================================================================
# Backward Compatibility
# ============================================================================

# Maintain backward compatibility with original parse_args function
parse_args() {
    kt_runner_parse_args "$@"
}

# ============================================================================
# Exports for use in tests
# ============================================================================

readonly KT__RUNNER_VERSION="1.0.0"