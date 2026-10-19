#!/bin/bash
# ktests.sh - Common test framework runner
# Usage: ktests.sh SCRIPT_DIR [SUITE_NAME] [TEST_FILTER] [OPTIONS]
# Parameters:
#   SCRIPT_DIR    - Directory containing test files (usually $SCRIPT_DIR from caller)
#   SUITE_NAME    - Name of the test suite (for display)
#   TEST_FILTER   - Optional grep pattern to filter test files (default: '/[0-9][0-9][0-9]_')
#   OPTIONS       - Additional options passed to kt_runner_parse_args
# Environment:
#   KT_SUMMARY_FILE=PATH - write a machine summary of the run to PATH (gate G1,
#                   GATE_PLAN §4.3). Read once here and unset from the
#                   environment before anything else runs: no test file,
#                   worker or nested ktests.sh ever sees it. Written once, at
#                   exit, atomically (PATH.tmp.<pid> + mv; PATH's directory
#                   must exist). Line 1: `TOTAL PASSED FAILED RC` (RC = this
#                   runner's exit status; PASSED capped at TOTAL as the
#                   results block shows it), then one `file NAME` line per
#                   failed test file (basenames, as the results block lists
#                   them). A run that did not reach its normal end writes
#                   `0 0 0 RC` and one `error REASON` line instead:
#                   `usage` (no SCRIPT_DIR, or the option parser exited:
#                   bad option, -h), `no-test-files` (nothing matched),
#                   `interrupted` (TERM/INT/HUP, RC 128+N), `no-results` (the
#                   run ended without its results: its shell was killed from
#                   outside), `exit` (any other exit). So a MISSING file means
#                   the runner itself died (SIGKILL, a crash of bash).

set -o pipefail

# KT_SUMMARY_FILE: taken and unset before anything else (see the header)
__kt_sum_file="${KT_SUMMARY_FILE:-}"
unset KT_SUMMARY_FILE
if [[ -n "$__kt_sum_file" ]]; then
    [[ "$__kt_sum_file" == /* || "$__kt_sum_file" =~ ^[A-Za-z]:[/\\] ]] || __kt_sum_file="$PWD/$__kt_sum_file"
    __kt_sum_done=0 __kt_sum_why=usage
    # _kt_summary_write LINE... — the file: the LINEs (line 1 `T P F RC`);
    # temp + mv in PATH's dir; marks the summary as written
    _kt_summary_write() {
        local t="$__kt_sum_file.tmp.$$"
        __kt_sum_done=1
        { printf '%s\n' "$@" > "$t" && mv -f -- "$t" "$__kt_sum_file"; } 2>/dev/null || rm -f -- "$t" 2>/dev/null
        return 0
    }
    # _kt_summary_part — in the run's shell, after the results block: the
    # counts and the failed files (FAILED_TEST_FILES lives only there)
    _kt_summary_part() {
        local t="${TESTS_TOTAL:-0}" p="${TESTS_PASSED:-0}" f="${TESTS_FAILED:-0}"
        (( p > t )) && p=$t
        {
            printf '%s %s %s\n' "$t" "$p" "$f"
            (( f > 0 && ${#FAILED_TEST_FILES[@]} > 0 )) && printf 'file %s\n' "${FAILED_TEST_FILES[@]}"
        } > "${KT_ISO_ROOT:-${__kt_sum_file%/*}}/.kt_summary.$$" 2>/dev/null
        return 0
    }
    # _kt_summary_end RC — the normal end: the run's part + RC
    _kt_summary_end() {
        local part="${KT_ISO_ROOT:-${__kt_sum_file%/*}}/.kt_summary.$$"
        local -a L=()
        { mapfile -t L < "$part"; } 2>/dev/null
        rm -f -- "$part" 2>/dev/null
        if [[ "${L[0]:-}" =~ ^[0-9]+\ [0-9]+\ [0-9]+$ ]]; then
            L[0]="${L[0]} $1"
            _kt_summary_write "${L[@]}"
        else
            _kt_summary_write "0 0 0 $1" "error no-results"
        fi
    }
    # _kt_summary_atexit RC — the EXIT trap: an exit before the normal end
    _kt_summary_atexit() {
        (( __kt_sum_done )) && return 0
        _kt_summary_write "0 0 0 $1" "error ${__kt_sum_why:-exit}"
    }
    trap '_kt_summary_atexit $?' EXIT
    trap '__kt_sum_why=interrupted; exit 143' TERM
    trap '__kt_sum_why=interrupted; exit 130' INT
    trap '__kt_sum_why=interrupted; exit 129' HUP
fi

# Check required parameter
if [[ -z "$1" ]]; then
    echo "Error: SCRIPT_DIR parameter required"
    echo "Usage: ktests.sh SCRIPT_DIR [SUITE_NAME] [TEST_FILTER] [remaining_options...]"
    exit 1
fi

SCRIPT_DIR="$1"
SUITE_NAME="${2:-Test Suite}"

# Parse remaining arguments carefully
# The third argument might be TEST_FILTER (starts with /) or an option (starts with -)
# If it looks like an option, use default TEST_FILTER and pass it to kt_runner_parse_args

shift 2  # Remove SCRIPT_DIR and SUITE_NAME
remaining_args=()

# Process $1 onwards
if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
    # Third arg is not an option, assume it's TEST_FILTER
    TEST_FILTER="$1"
    shift
else
    # Third arg is an option or missing, use default TEST_FILTER
    TEST_FILTER="/[0-9][0-9][0-9]_"
fi

# Collect remaining arguments for kt_runner_parse_args
remaining_args=("$@")

# Determine ktests library directory based on current script location
KTESTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KTESTS_LIB_DIR
source "$KTESTS_LIB_DIR/ktest.sh"
# kt_strays_group_settle (round 5, P3b): the end-of-run check of the run groups
source "$KTESTS_LIB_DIR/tools/strays.sh"

# Parse remaining command line arguments
kt_runner_parse_args "${remaining_args[@]}"
[[ -n "$__kt_sum_file" ]] && __kt_sum_why=""

# Show test execution info
kt_test_section "Starting $SUITE_NAME"

# Find test files
test_files=()
while IFS= read -r file; do
    test_files+=("$file")
done < <(kt_runner_find_tests "$SCRIPT_DIR" | grep "$TEST_FILTER")

if [[ ${#test_files[@]} -eq 0 ]]; then
    kt_test_error "No test files found in $SCRIPT_DIR matching pattern: $TEST_FILTER"
    [[ -n "$__kt_sum_file" ]] && __kt_sum_why=no-test-files
    exit 1
fi

# Show test files to be executed in info mode
if [[ "$VERBOSITY" == "info" ]]; then
    echo "Found ${#test_files[@]} test file(s):"
    for f in "${test_files[@]}"; do
        echo "  - $(basename "$f")"
    done
    echo ""
fi

# The run's isolation folder (kbool `uses` U41, review R6): created once,
# removed on exit; stale ones of dead runners are swept first. TERM/INT/HUP
# exit with 128+N so the EXIT trap runs (ktests round 5, T9/DT9: bash 5.2 runs
# no EXIT trap on a signal by itself); a SIGKILLed run's folder (with its
# threaded results dir) goes to the next run's dead-pid sweep.
#
# The run itself (review R1) is a BACKGROUND job in its own process group that
# this shell `wait`s on: a trap is deferred while a foreground child runs, so a
# TERM to this pid alone used to wait for the current test file (single mode)
# or the whole suite (threaded). `wait` returns at once on a trapped signal;
# the trap stops the group (the run's shell, its current test file; in
# threaded mode the run's shell stops its own worker group the same way). A
# SIGKILLed ktests.sh runs no trap: the group's FIFO watchdog stops it then.
# Grace 5 s (kt_runner_group_stop and the watchdog): longer than the 3 s the run's shell gives
# its own worker group, so it is not KILLed in the middle of that stop.
__kt_run_pid="" __kt_run_wfd="" __kt_run_susp=0
if [[ -n "$__kt_sum_file" ]]; then
    __kt_sum_why=interrupted
    trap '__kt_sum_x=$?; kt_runner_iso_end; _kt_summary_atexit "$__kt_sum_x"' EXIT
else
    trap 'kt_runner_iso_end' EXIT
fi
trap 'kt_runner_group_stop "$__kt_run_pid" 50; exit 143' TERM
trap 'kt_runner_group_stop "$__kt_run_pid" 50; exit 130' INT
trap 'kt_runner_group_stop "$__kt_run_pid" 50; exit 129' HUP
# Ctrl-Z (review round 2, N6): stop the run group and this shell; on resume
# continue the group (kt_runner_group_suspend) and wait again
trap '__kt_run_susp=1; kt_runner_group_suspend "$__kt_run_pid"' TSTP
kt_runner_iso_begin "${test_files[@]}"

kt_runner_group_open "$KT_ISO_ROOT/.kt_watch" && __kt_run_wfd="$REPLY"
set -m
(
    kt_runner_group_watchdog "$KT_ISO_ROOT/.kt_watch" "$__kt_run_wfd" 50

    # Execute all tests (pass TEST_FILTER so execution matches the displayed set)
    kt_runner_execute_tests "$SCRIPT_DIR" "$TEST_FILTER"

    # Display final results
    echo ""
    kt_test_show_results "${FAILED_TEST_FILES[@]}"
    __kt_src=$?
    [[ -z "$__kt_sum_file" ]] || _kt_summary_part
    exit "$__kt_src"
) < /dev/null &
__kt_run_pid=$!
set +m
while :; do
    __kt_run_susp=0
    wait "$__kt_run_pid"; __kt_run_rc=$?
    (( __kt_run_susp )) || break
done
kt_runner_group_close "$__kt_run_wfd"
# Nothing of the run's group may outlive the run (round 5, P3b): a test file's
# background process (no cleanup) would stay in it after the normal end. The
# watchdog leaves by itself; whatever else is still there is named in a
# [WARN] line and stopped. No fork: /proc members (kt_runner_group_members),
# empty twice in a row, fork-free `read -t` waits (P3b review round 2, F10).
kt_strays_group_settle "$__kt_run_pid" "$SUITE_NAME" || :

# Exit with the run's code (after the summary file, when one was asked for)
[[ -z "$__kt_sum_file" ]] || _kt_summary_end "$__kt_run_rc"
exit $__kt_run_rc
