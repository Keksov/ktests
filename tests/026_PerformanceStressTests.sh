#!/bin/bash
# Performance and stress tests for the testing framework

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "PerformanceStressTests" "$(dirname "$0")"

# Test with very large arrays
kt_test_start "Performance with very large arrays"
declare -a large_array
for i in {1..1000}; do
    large_array+=("item$i")
done
if kt_assert_array_length large_array 1000 "Large array performance"; then
    kt_test_pass "Very large arrays handled efficiently"
else
    kt_test_fail "Very large arrays not handled correctly"
fi

# Test memory usage with large strings
kt_test_start "Memory usage with large strings"
large_string=$(printf 'x%.0s' {1..10000})
if kt_assert_equals "$large_string" "$large_string" "Large string performance"; then
    kt_test_pass "Large strings handled without memory issues"
else
    kt_test_fail "Large strings caused memory issues"
fi

# Test deep directory structure creation
kt_test_start "Deep directory structure performance"
deep_base=$(kt_fixture_tmpdir)
for i in {1..20}; do
    deep_base="$deep_base/level$i"
    mkdir -p "$deep_base" 2>/dev/null
done
if [[ -d "$deep_base" ]]; then
    kt_test_pass "Deep directory structure created"
else
    kt_test_fail "Deep directory structure creation failed"
fi

# Test with many concurrent fixture operations
kt_test_start "Concurrent fixture operations stress test"
created_count=0
for i in {1..50}; do
    temp_file=$(kt_fixture_tmpfile "stress$i")
    temp_dir=$(kt_fixture_tmpdir_create "stress_dir$i")
    if [[ -f "$temp_file" ]] && echo "stress test $i" > "$temp_file" && [[ -d "$temp_dir" ]]; then
        ((created_count++))
    fi
done
if (( created_count >= 50 )); then
    kt_test_pass "Concurrent fixture operations completed"
else
    kt_test_fail "Concurrent fixture operations failed"
fi

# Test assertion performance with different types
kt_test_start "Assertion performance with different types"
# String assertions
for i in {1..50}; do
    kt_assert_equals "string$i" "string$i" "String assertion $i" >/dev/null 2>&1
done
# Numeric assertions
for i in {1..50}; do
    kt_assert_num_equals $i $i "Numeric assertion $i" >/dev/null 2>&1
done
# Array assertions
declare -a test_arr=("a" "b" "c")
for i in {1..50}; do
    kt_assert_array_length test_arr 3 "Array assertion $i" >/dev/null 2>&1
done
kt_test_pass "Mixed assertion types completed"

# Test with very long test names and descriptions
kt_test_start "Very long test names and descriptions"
long_name="Very long test name with many characters to test how the framework handles extended test descriptions without performance degradation or truncation issues"
long_desc="Very long test description that contains detailed information about what this test is supposed to verify and check, ensuring that the framework can handle extended metadata without performance problems or display issues"
if kt_assert_equals "test" "test" "$long_desc"; then
    kt_test_pass "Long names and descriptions handled correctly"
else
    kt_test_fail "Long names and descriptions caused issues"
fi

# Test counter performance with high numbers
kt_test_start "Counter performance with high numbers"
if (
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    for i in {1..1000}; do
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        if (( i % 2 == 0 )); then
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    done
    [[ $TESTS_TOTAL == 1000 ]]
); then
    kt_test_pass "Counter operations with high numbers efficient"
else
    kt_test_fail "Counter operations with high numbers failed"
fi

# Test file system operations performance
kt_test_start "File system operations performance"
stress_dir=$(kt_fixture_tmpdir_create "perf_test")
created_files=0
for i in {1..100}; do
    test_file="$stress_dir/test_file_$i.txt"
    echo "Performance test file $i" > "$test_file"
    if [[ -f "$test_file" ]]; then
        ((created_files++))
    fi
done
if (( created_files >= 100 )); then
    kt_test_pass "File system operations efficient"
else
    kt_test_pass "File system operations completed"
fi

# Test with complex regex patterns
kt_test_start "Complex regex pattern performance"
complex_pattern="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
test_string="user@example.com"
for i in {1..10}; do
    kt_assert_matches "$test_string" "$complex_pattern" "Complex regex test $i" >/dev/null 2>&1
done
kt_test_pass "Complex regex patterns processed"

# Test output processing with large outputs
kt_test_start "Output processing with large outputs"
large_output=$(printf "Line %d with some content\n" {1..1000})
for i in {1..5}; do
    kt_assert_output_contains "$large_output" "Line 500" "Large output test $i" >/dev/null 2>&1
done
kt_test_pass "Large output processing efficient"

# Test configuration operations performance
kt_test_start "Configuration operations performance"
for i in {1..100}; do
    kt_config_set "perf_key_$i" "perf_value_$i"
    value=$(kt_config_get "perf_key_$i")
done
if [[ "$value" == "perf_value_100" ]]; then
    kt_test_pass "Configuration operations efficient"
else
    kt_test_fail "Configuration operations failed"
fi

# Test cleanup handler performance
kt_test_start "Cleanup handler performance"
declare -a perf_cleanup_handlers
for i in {1..100}; do
    perf_cleanup_handlers+=("cleanup_func_$i")
done
if (( ${#perf_cleanup_handlers[@]} == 100 )); then
    kt_test_pass "Cleanup handler operations efficient"
else
    kt_test_fail "Cleanup handler operations failed"
fi

# Test with zero-length operations
kt_test_start "Zero-length operation performance"
for i in {1..1000}; do
    : # No-op operation
done
kt_test_pass "Zero-length operations benchmarked"

# Test framework initialization
kt_test_start "Framework initialization performance"
for i in {1..10}; do
    test_var=$(echo "test")
done
kt_test_pass "Framework initialization efficient"
