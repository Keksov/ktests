#!/bin/bash
# kk-test-runner.sh - Test discovery and execution engine
# Handles test file discovery, CLI parsing, sequential/parallel execution, and results aggregation
#
# Requires: kk-test-core.sh and kk-test-fixtures.sh to be sourced first

# Prevent multiple sourcing
if [[ -n "$_KK_TEST_RUNNER_SOURCED" ]]; then
    return
fi
_KK_TEST_RUNNER_SOURCED=1

# Ensure core framework is available
if [[ -z "$_KK_TEST_CORE_SOURCED" ]]; then
    echo "ERROR: kk-test-core.sh must be sourced before kk-test-runner.sh" >&2
    return 1
fi

# ============================================================================
# Global Variables
# ============================================================================

# Test execution configuration
declare -g TEST_SELECTION=""
declare -g MODE="threaded"
declare -g WORKERS=8

# Array of selected test numbers
declare -ga TESTS_TO_RUN=()

# Array of failed test file names
declare -ga FAILED_TEST_FILES=()

# ============================================================================
# Test Selection Parsing
# ============================================================================

# Parse test selection string into TESTS_TO_RUN array
# Format: "1,2,3-5,10-12" expands to [1,2,3,4,5,10,11,12]
# Usage: kk_runner_parse_selection "1,3-5"
kk_runner_parse_selection() {
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
            kk_test_warning "Invalid test selection format: '$part'"
        fi
    done
}

# ============================================================================
# CLI Argument Parsing
# ============================================================================

# Parse command line arguments for test runner
# Supports: --verbosity, -v, -n/--tests, -m/--mode, -w/--workers
# Usage: kk_runner_parse_args "$@"
kk_runner_parse_args() {
    # Defaults
    VERBOSITY="${VERBOSITY:-error}"
    TEST_SELECTION=""
    MODE="threaded"
    WORKERS=8
    
    # If VERBOSITY is already set from environment, respect it but allow override
    local env_verbosity="$VERBOSITY"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbosity=*)
                VERBOSITY="${1#*=}"
                shift
                ;;
            --verbosity|-v)
                VERBOSITY="$2"
                shift 2
                ;;
            -n|--tests)
                TEST_SELECTION="$2"
                shift 2
                ;;
            --tests=*)
                TEST_SELECTION="${1#*=}"
                shift
                ;;
            -m|--mode)
                MODE="$2"
                shift 2
                ;;
            --mode=*)
                MODE="${1#*=}"
                shift
                ;;
            -w|--workers)
                WORKERS="$2"
                shift 2
                ;;
            --workers=*)
                WORKERS="${1#*=}"
                shift
                ;;
            -h|--help)
                kk_runner_show_help
                exit 0
                ;;
            *)
                kk_test_error "Unknown option: $1"
                kk_runner_show_help
                exit 1
                ;;
        esac
    done
    
    # Validate arguments
    kk_test_validate_verbosity "$VERBOSITY" || exit 1
    kk_test_validate_mode "$MODE" || exit 1
    kk_test_validate_workers "$WORKERS" || exit 1
    
    # Update configuration
    kk_config_set "verbosity" "$VERBOSITY"
    
    # Parse test selection if provided
    if [[ -n "$TEST_SELECTION" ]]; then
        kk_runner_parse_selection "$TEST_SELECTION"
        kk_test_debug "Parsed test selection: ${TESTS_TO_RUN[*]}"
    fi
    
    # Export for subshells
    export VERBOSITY MODE WORKERS TEST_SELECTION FAILED_TEST_FILES
}

# Show usage information
kk_runner_show_help() {
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
                         Default: 8
  
  -h, --help            Show this help message

Examples:
  ./test_suite.sh                           # Run all tests sequentially
  ./test_suite.sh -v info                   # Run all tests with verbose output
  ./test_suite.sh -n 1-5                    # Run tests 1-5
  ./test_suite.sh -n 1,3,5 -m single       # Run tests 1, 3, 5 sequentially
  ./test_suite.sh -v info -m threaded -w 4 # Run all tests with 4 threads
EOF
}

# ============================================================================
# Test File Discovery
# ============================================================================

# Find test files matching patterns
# Handles Windows newline issues and numeric prefix patterns
# Usage: test_files=($(kk_runner_find_tests "/path/to/tests" "001_*.sh"))
kk_runner_find_tests() {
    local test_dir="$1"
    local pattern="${2:-[0-9][0-9][0-9]_*.sh}"
    
    if [[ ! -d "$test_dir" ]]; then
        kk_test_error "Test directory not found: $test_dir"
        return 1
    fi
    
    # Change to test directory for globbing
    local old_pwd
    old_pwd=$(pwd)
    cd "$test_dir" || return 1
    
    local test_files=()
    
    if [[ ${#TESTS_TO_RUN[@]} -gt 0 ]]; then
        # Find specific test numbers
        for num in "${TESTS_TO_RUN[@]}"; do
            shopt -s nullglob
            
            # Try various zero-padding patterns
            for pattern_var in "${num}_*.sh" "0${num}_*.sh" "00${num}_*.sh" "$(printf '%03d' "$num")_*.sh"; do
                for f in $pattern_var; do
                    [[ -f "$f" ]] && test_files+=("$f")
                done
            done
            
            shopt -u nullglob
        done
    else
        # Find all test files with 3-digit prefix
        shopt -s nullglob
        for f in [0-9][0-9][0-9]_*.sh; do
            [[ -f "$f" ]] && test_files+=("$f")
        done
        shopt -u nullglob
    fi
    
    cd "$old_pwd" || return 1
    
    # Remove duplicates and clean newlines
    local cleaned=()
    declare -A seen
    for f in "${test_files[@]}"; do
        f="${f%$'\r'}"  # Remove Windows line endings
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
# Sequential Test Execution
# ============================================================================

# Run tests sequentially in isolated subshells
# Usage: kk_runner_execute_sequential test_file1 test_file2 ...
kk_runner_execute_sequential() {
    local test_file
    local output
    local counts_line
    local t p f
    
    for test_file in "$@"; do
        [[ ! -f "$test_file" ]] && continue
        
        local clean_file="${test_file%$'\r'}"
        
        kk_test_debug "Executing: $(basename "$clean_file")"
        
        # Run test in subshell to isolate state
         output="$(
             bash -c "
                 export VERBOSITY='$VERBOSITY'
                 source '$clean_file'
                 echo __COUNTS__:\$TESTS_TOTAL:\$TESTS_PASSED:\$TESTS_FAILED
             " 2>&1 || true
         )"
         
         # Parse counters from output
         counts_line="$(printf '%s\n' "$output" | sed -e 's/\r$//' | grep '^__COUNTS__:' | tail -n 1)"
         
         if [[ -n "$counts_line" ]]; then
             IFS=':' read -r _ t p f <<<"$counts_line"
             t=${t:-0}; p=${p:-0}; f=${f:-0}
             TESTS_TOTAL=$((TESTS_TOTAL + t))
             TESTS_PASSED=$((TESTS_PASSED + p))
             TESTS_FAILED=$((TESTS_FAILED + f))
             
             # Track failed test files
             if ((f > 0)); then
                 FAILED_TEST_FILES+=("$(basename "$clean_file")")
             fi
         else
             # Test failed to report counters
             TESTS_TOTAL=$((TESTS_TOTAL + 1))
             TESTS_FAILED=$((TESTS_FAILED + 1))
             local test_name="$(basename "$clean_file")"
             kk_test_fail "$test_name"
             FAILED_TEST_FILES+=("$test_name")
         fi
         
         # Always show errors and warnings in all verbosity modes
         # Show full output on verbose or failure
         if [[ "$VERBOSITY" == "info" ]] || ((f > 0)); then
             echo "$output" | sed -e 's/\r$//' | grep -v '^__COUNTS__:' || true
         else
             # In error mode, still show [ERROR], [FAIL], [WARN], and [ASSERTION FAILED] messages
                 echo "$output" | sed -e 's/\r$//' | grep -E '^\[ERROR\]|\[FAIL\]|\[WARN\]|\[ASSERTION FAILED\]|: No such file|: command not found' | grep -v '^__COUNTS__:' || true
         fi
    done
}

# ============================================================================
# Threaded Test Execution
# ============================================================================

# Run tests with worker threads
# Usage: kk_runner_execute_threaded test_file1 test_file2 ...
kk_runner_execute_threaded() {
    local test_files=("$@")
    local num_files=${#test_files[@]}
    
    if [[ $num_files -eq 0 ]]; then
        return 0
    fi
    
    # For simplicity with many tests, fall back to sequential if too few tests or workers
    if [[ $num_files -le $WORKERS ]]; then
        kk_runner_execute_sequential "${test_files[@]}"
        return 0
    fi
    
    # Create a named pipe for worker coordination
    local fifo_dir
    fifo_dir=$(mktemp -d)
    local fifo="$fifo_dir/test_queue"
    mkfifo "$fifo" 2>/dev/null || true
    
    # Worker function to run tests
    worker_func() {
        local test_file
        while IFS= read -r test_file <&3; do
            [[ -z "$test_file" ]] && break
            
            local output counts_line t p f
            output="$(
                bash -c "
                    export VERBOSITY='$VERBOSITY'
                    source '$test_file'
                    echo __COUNTS__:\$TESTS_TOTAL:\$TESTS_PASSED:\$TESTS_FAILED
                " 2>&1 || true
            )"
            
            counts_line="$(printf '%s\n' "$output" | grep '^__COUNTS__:' | tail -n 1)"
            if [[ -n "$counts_line" ]]; then
                echo "$counts_line"
            else
                echo "__COUNTS__:1:0:1"
            fi
        done 3<&-
    }
    
    # Start workers
    local pids=()
    for ((w=0; w<WORKERS; w++)); do
        worker_func 3<"$fifo" &
        pids+=($!)
    done
    
    # Queue test files
    for test_file in "${test_files[@]}"; do
        echo "$test_file" >> "$fifo"
    done
    
    # Signal end of queue
    for ((w=0; w<WORKERS; w++)); do
        echo "" >> "$fifo"
    done
    
    # Collect results from workers
    local all_output
    for pid in "${pids[@]}"; do
        wait "$pid"
        # Results are printed to stdout by worker
    done
    
    # Cleanup
    rm -rf "$fifo_dir" 2>/dev/null || true
    
    # Fall back to sequential execution as it's more reliable in bash
    kk_runner_execute_sequential "${test_files[@]}"
}

# ============================================================================
# Main Execution
# ============================================================================

# Execute all discovered tests
# Usage: kk_runner_execute_tests "/path/to/tests"
kk_runner_execute_tests() {
    local test_dir="${1:-.}"
    
    if [[ ! -d "$test_dir" ]]; then
        kk_test_error "Test directory not found: $test_dir"
        return 1
    fi
    
    # Reset counters before execution
    kk_test_reset_counts
    FAILED_TEST_FILES=()
    
    # Find test files
    local test_files=()
    while IFS= read -r file; do
        test_files+=("$file")
    done < <(kk_runner_find_tests "$test_dir")
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        kk_test_error "No test files found in $test_dir"
        return 1
    fi
    
    # Show test execution info
    if [[ "$VERBOSITY" == "info" ]]; then
        kk_test_section "Test Execution"
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
            kk_runner_execute_sequential "${test_files[@]}"
            ;;
        threaded)
            kk_runner_execute_sequential "${test_files[@]}"  # Use sequential for now (safer)
            ;;
        *)
            kk_test_error "Unknown execution mode: $MODE"
            return 1
            ;;
    esac
}

# ============================================================================
# Backward Compatibility
# ============================================================================

# Maintain backward compatibility with original parse_args function
parse_args() {
    kk_runner_parse_args "$@"
}

# ============================================================================
# Exports for use in tests
# ============================================================================

readonly KK_TEST_RUNNER_VERSION="1.0.0"

