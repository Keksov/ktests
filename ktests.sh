#!/bin/bash
# ktests.sh - Common test framework runner
# Usage: ktests.sh SCRIPT_DIR [SUITE_NAME] [TEST_FILTER] [OPTIONS]
# Parameters:
#   SCRIPT_DIR    - Directory containing test files (usually $SCRIPT_DIR from caller)
#   SUITE_NAME    - Name of the test suite (for display)
#   TEST_FILTER   - Optional grep pattern to filter test files (default: '/[0-9][0-9][0-9]_')
#   OPTIONS       - Additional options passed to kt_runner_parse_args

set -o pipefail

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

# Show test execution info
kt_test_section "Starting $SUITE_NAME"

# Find test files
test_files=()
while IFS= read -r file; do
    test_files+=("$file")
done < <(kt_runner_find_tests "$SCRIPT_DIR" | grep "$TEST_FILTER")

if [[ ${#test_files[@]} -eq 0 ]]; then
    kt_test_error "No test files found in $SCRIPT_DIR matching pattern: $TEST_FILTER"
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
trap 'kt_runner_iso_end' EXIT
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

# Exit with the run's code
exit $__kt_run_rc
