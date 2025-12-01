#!/bin/bash
# Test suite runner for comprehensive testing framework validation
# Usage: ./tests.sh [OPTIONS]
# Options: see kt_runner_show_help

set -o pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load test framework
source "$(dirname "$SCRIPT_DIR")/ktest.sh"

# Parse command line arguments
kt_runner_parse_args "$@"

# Show test execution info
kt_test_section "Starting Comprehensive Test Suite"

# Find test files
test_files=()
while IFS= read -r file; do
    test_files+=("$file")
done < <(kt_runner_find_tests "$SCRIPT_DIR")

if [[ ${#test_files[@]} -eq 0 ]]; then
    kt_test_error "No test files found in $SCRIPT_DIR"
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

# Execute all tests
kt_runner_execute_tests "$SCRIPT_DIR"

# Display final results
echo ""
kt_test_show_results "${FAILED_TEST_FILES[@]}"

# Exit with appropriate code
exit $?
