#!/bin/bash
# test-example.sh - Example test file using KK testing framework
#
# This template shows how to structure a test file using the framework.
# It demonstrates:
#   - Sourcing common.sh
#   - Using test tracking functions
#   - Using assertion helpers
#   - Fixture management
#   - Cleanup

# Source the test suite's common setup
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ============================================================================
# Test Suite Setup
# ============================================================================

# Initialize test-specific temporary directory
# This creates an isolated temp directory for this test's artifacts
init_test_tmpdir "example_001"

# Show test section header (verbose mode only)
test_section "Example Test Suite"

# ============================================================================
# Test Case 1: Basic Assertion
# ============================================================================

test_start "String equality check"

# Example test logic
result="hello"
expected="hello"

# Use assertion helpers from framework
kt_assert_equals "$expected" "$result" "Strings should match"

# ============================================================================
# Test Case 2: File System Check
# ============================================================================

test_start "Temp directory creation"

# Create a temporary file in the test directory
test_file=$(kt_fixture_tmpfile "test")

# Assert the file was created
kt_assert_file_exists "$test_file" "Temp file should exist"

# ============================================================================
# Test Case 3: Multiple Assertions
# ============================================================================

test_start "Multiple value checks"

# Test with multiple conditions
value1="42"
value2="42"
value3="hello"

kt_assert_equals "$value1" "$value2" "Numeric values should match"
kt_assert_not_equals "$value1" "$value3" "Values should not be equal"

# ============================================================================
# Test Case 4: Output Validation
# ============================================================================

test_start "Command output validation"

# Capture output from a command
output=$(echo "This is test output")

# Assert output contains expected text
kt_assert_output_contains "$output" "test" "Output should contain 'test'"
kt_assert_output_not_contains "$output" "error" "Output should not contain 'error'"

# ============================================================================
# Test Case 5: Directory Operations
# ============================================================================

test_start "Directory operations"

# Create a temporary subdirectory
test_dir=$(kt_fixture_tmpdir_create "subdir")

# Assert the directory exists
kt_assert_dir_exists "$test_dir" "Temp directory should exist"

# ============================================================================
# Test Case 6: Conditional Testing
# ============================================================================

test_start "Conditional assertions"

# Only run these if running in verbose mode
if [[ "$VERBOSITY" == "info" ]]; then
    kt_test_log "This is extra diagnostic information"
fi

# Use test_info for conditional logging in quiet mode
test_info "Test completed successfully"

# ============================================================================
# Test Case 7: Error Handling
# ============================================================================

test_start "Test failure example"

# This assertion will fail (intentionally for demo)
kt_assert_equals "expected" "actual" "This assertion demonstrates a failure"

# Continue with more tests (failures don't stop execution)

# ============================================================================
# Test Case 8: Arrays
# ============================================================================

test_start "Array operations"

# Create an array
my_array=("apple" "banana" "cherry")

# Assert array length
kt_assert_array_length "my_array" 3 "Array should have 3 elements"

# Assert array contains a value
kt_assert_array_contains "my_array" "banana" "Array should contain 'banana'"

# ============================================================================
# Test Case 9: Fixture Management
# ============================================================================

test_start "File fixture creation"

# Create a fixture file with specific content
fixture_file=$(kt_fixture_create_file "config.txt" "key=value")

# Verify the file was created
if [[ -f "$fixture_file" ]]; then
    test_pass "Fixture file created successfully"
else
    test_fail "Fixture file creation failed"
fi

# ============================================================================
# Test Cleanup Demonstration
# ============================================================================

# Register a custom cleanup handler
cleanup_demo() {
    kt_test_debug "Custom cleanup handler called"
    # Add cleanup logic here
}

# Uncomment to demonstrate cleanup handler:
# kt_fixture_cleanup_register "cleanup_demo"

# ============================================================================
# Summary
# ============================================================================

# The framework automatically:
#   - Accumulates test counts
#   - Prints formatted output
#   - Manages temporary directories
#   - Calls cleanup handlers on exit
#
# To run this test:
#   ./test-example.sh                    # Run with quiet output
#   ./test-example.sh -v info            # Run with verbose output
#   ./test-example.sh -v info -m single  # Sequential mode with verbose

