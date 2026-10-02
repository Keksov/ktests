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
    
    # Export for subshells
    export VERBOSITY MODE WORKERS TEST_SELECTION FAILED_TEST_FILES _KT_ASSERT_QUIET_MODE _KTEST_QUIET_MODE
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

# Execute a single test and return output and counts
# Usage: kt_runner_execute_single_test "/path/to/test.sh"
# Sets: output_content, counts_line, count_total, count_passed, count_failed
kt_runner_execute_single_test() {
    local test_file="$1"
    
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
    local base="${clean_file##*/}"
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
            bash -c '
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

    # Fold an abort verdict (missing END, source rc, unclosed test, bash fatal
    # diagnostic) into counts_line and output_content.
    kt_runner_judge_capture "$base" "$__kt_child_rc"

    # A fixture dir of this file still present after its shell exited means
    # kt_test_init's EXIT trap did not run — the test replaced it with its own
    # `trap … EXIT` (round 3, T5/DT5) or the shell was killed. Remove it and
    # say so; the file's verdict is not changed.
    local __kt_fx __kt_tdir="${clean_file%/*}"
    [[ "$__kt_tdir" == "$clean_file" ]] && __kt_tdir="."
    for __kt_fx in "$__kt_tdir/.tmp/"*".${base%.sh}"; do
        [[ -d "$__kt_fx" ]] || continue
        rm -rf -- "$__kt_fx"
        output_content+="${output_content:+$'\n'}[WARN] $base: fixture dir .tmp/${__kt_fx##*/} left behind (own EXIT trap?) - removed by the runner; register cleanup with kt_fixture_cleanup_register, never trap EXIT"
    done

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

    # Create temporary directory for results
    local results_dir
    results_dir=$(mktemp -d) || {
        kt_test_error "Failed to create temporary directory for threaded execution"
        kt_runner_execute_sequential "${test_files[@]}"
        return $?
    }
    
    # Actual number of workers to use
    local num_workers=$WORKERS
    [[ $num_workers -gt $num_files ]] && num_workers=$num_files

    # The worker function, the exports the workers need and the spawn all live
    # in ONE subshell (round 3, T3/DT3): the caller keeps its values, export
    # attributes and functions — on 5.2.37 an `export` of a name given as a
    # prefix assignment (`VERBOSITY=error kt_runner_execute_threaded …`) used
    # to outlive the call. The collector below reads only the result files.
    (
        # Execute a single test and save its results
        run_test() {
            local test_file="$1"
            local result_file="$2"

            # Use common execution function
            kt_runner_execute_single_test "$test_file"

            # Save results to file
            {
                echo "$counts_line"
                echo "$output_content"
            } > "$result_file"
        }

        export -f run_test kt_test_debug kt_runner_execute_single_test kt_test_reset_counts kt_runner_clean_filename kt_runner_parse_counts kt_runner_set_error_counts kt_runner_find_last_counts_line kt_runner_scan_capture kt_runner_judge_capture
        # KT_ERROR_COUNTS: a missing file's counts line in a worker (T4)
        export results_dir VERBOSITY _KT_ASSERT_QUIET_MODE _KTEST_QUIET_MODE KTESTS_LIB_DIR KT_ENV_FORK_FAILURE_RE KT_BASH_FATAL_DIAG_RE KT_ERROR_COUNTS

        # Run tests in parallel using xargs or manual background processes
        if command -v xargs &>/dev/null; then
            # Use xargs for better parallelization if available
            printf '%s\n' "${test_files[@]}" | xargs -P "$num_workers" -I {} bash -c '
                run_test "$1" "$2/$(basename "$1").result"
            ' _ {} "$results_dir"
        else
            # Manual parallel execution using background processes
            for ((i=0; i<num_files; i++)); do
                # Limit number of concurrent jobs
                while [[ $(jobs -r | wc -l) -ge $num_workers ]]; do
                    sleep 0.01
                done

                run_test "${test_files[$i]}" "$results_dir/${i}.result" &
            done
            wait
        fi
    )

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
                FAILED_TEST_FILES+=("$(basename "${test_files[$failed_name]}")")
            else
                FAILED_TEST_FILES+=("$failed_name")
            fi
        fi

        # Show output with filtering
        local output_content
        output_content=$(cat "$result_file")
        kt_runner_filter_output "$output_content" "$counts_line" "$f"
    done
    
    # Update global counters
    kt_runner_add_counts "$total_t" "$total_p" "$total_f"
    
    # Cleanup
    rm -rf "$results_dir"
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
    FAILED_TEST_FILES=()

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