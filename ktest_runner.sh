#!/bin/bash
# ktest_runner.sh - Test discovery and execution engine
# Handles test file discovery, CLI parsing, sequential/parallel execution, and results aggregation
#
# Requires: ktest_core.sh and ktest_fixtures.sh to be sourced first

# Prevent multiple sourcing
if [[ -n "$_KTEST_RUNNER_SOURCED" ]]; then
    return
fi
declare -g _KTEST_RUNNER_SOURCED=1

# Ensure core framework is available
if [[ -z "$_KTEST_CORE_SOURCED" ]]; then
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
    
    # Run test in subshell to isolate state
    output_content="$(
        bash -c "
            export VERBOSITY='$VERBOSITY'
            export KK_OUTPUT_COUNTS=1
            export _KT_ASSERT_QUIET_MODE='$_KT_ASSERT_QUIET_MODE'
            export _KTEST_QUIET_MODE='$_KTEST_QUIET_MODE'
            export KT_TESTS_DIR='$(dirname "$clean_file")'
            export KTESTS_LIB_DIR='$KTESTS_LIB_DIR'
            export KTEST_SOURCE_PATH='$KTESTS_LIB_DIR/ktest_source.sh'
            source \"\$KTEST_SOURCE_PATH\"
            source '$clean_file'
            # Always output counts (needed by runner for result tracking)
            echo \"__COUNTS__:\$TESTS_TOTAL:\$TESTS_PASSED:\$TESTS_FAILED\"
        " 2>&1 || true
    )"
    
    # Parse counters from output
    counts_line="$(printf '%s\n' "$output_content" | sed -e 's/\r$//' | grep '^__COUNTS__:' | tail -n 1)"
    if [[ -n "$counts_line" ]]; then
        kt_runner_parse_counts "$counts_line"
    else
        kt_runner_set_error_counts
    fi
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
        echo "$output" | sed -e 's/\r$//' | grep -v '^__COUNTS__:' || true
    else
        # In error mode, still show [ERROR], [FAIL], [WARN], [ASSERTION FAILED], SCRIPT ERROR, and other error messages
        # For SCRIPT ERROR blocks, show the entire block until we hit __COUNTS__ or a blank line followed by non-error output
        local lines=()
        local in_error_block=0
        while IFS= read -r line; do
            if [[ "$line" == *"SCRIPT ERROR"* ]]; then
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
        [[ ! -f "$test_file" ]] && continue
        
        # Execute test and get results
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
    
    # Function to execute a single test and save results
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
    
    # Export function for subshells
    export -f run_test kt_test_debug kt_runner_execute_single_test kt_test_reset_counts kt_runner_clean_filename kt_runner_parse_counts
    export results_dir VERBOSITY _KT_ASSERT_QUIET_MODE _KTEST_QUIET_MODE KTESTS_LIB_DIR
    
    # Actual number of workers to use
    local num_workers=$WORKERS
    [[ $num_workers -gt $num_files ]] && num_workers=$num_files
    
    # Run tests in parallel using xargs or manual background processes
    if command -v xargs &>/dev/null; then
        # Use xargs for better parallelization if available
        printf '%s\n' "${test_files[@]}" | xargs -P "$num_workers" -I {} bash -c '
            run_test "$1" "$2/$(basename "$1").result"
        ' _ {} "$results_dir"
    else
        # Manual parallel execution using background processes
        local active_jobs=0
        for ((i=0; i<num_files; i++)); do
            # Limit number of concurrent jobs
            while [[ $(jobs -r | wc -l) -ge $num_workers ]]; do
                sleep 0.01
            done
            
            run_test "${test_files[$i]}" "$results_dir/${i}.result" &
        done
        wait
    fi
    
    # Collect and aggregate results
    local total_t=0 total_p=0 total_f=0
    for result_file in "$results_dir"/*.result; do
        [[ ! -f "$result_file" ]] && continue
        
        local counts_line
        counts_line=$(grep '^__COUNTS__:' "$result_file" | head -n 1)
        
        if [[ -n "$counts_line" ]]; then
            local t p f
            kt_runner_parse_counts "$counts_line"
            t=$count_total; p=$count_passed; f=$count_failed
            total_t=$((total_t + t))
            total_p=$((total_p + p))
            total_f=$((total_f + f))
            
            # Track failed test files
            if ((f > 0)); then
                local test_idx
                test_idx="${result_file##*/}"
                test_idx="${test_idx%.result}"
                if [[ "$test_idx" =~ ^[0-9]+$ ]] && [[ $test_idx -lt ${#test_files[@]} ]]; then
                    FAILED_TEST_FILES+=("$(basename "${test_files[$test_idx]}")")
                fi
            fi
        else
            # Test failed to report counters
            total_t=$((total_t + 1))
            total_f=$((total_f + 1))
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
    
    if [[ ! -d "$test_dir" ]]; then
        kt_test_error "Test directory not found: $test_dir"
        return 1
    fi
    
    # Reset counters before execution
    kt_test_reset_counts
    FAILED_TEST_FILES=()
    
    # Find test files
    local test_files=()
    while IFS= read -r file; do
        test_files+=("$file")
    done < <(kt_runner_find_tests "$test_dir")
    
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