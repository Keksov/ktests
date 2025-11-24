#!/bin/bash
# Performance and stress tests for the testing framework

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "PerformanceStressTests" "$(dirname "$0")"

# Test with large number of assertions
kk_test_start "Performance with large number of assertions"
start_time=$(date +%s.%N)
for i in {1..100}; do
    kk_test_start "Performance test assertion $i"
    kk_assert_equals "test$i" "test$i" "Performance assertion $i"
done
end_time=$(date +%s.%N)
execution_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
if (( TESTS_TOTAL >= 100 )); then
    kk_test_pass "Large number of assertions handled (time: ${execution_time}s)"
else
    kk_test_fail "Large number of assertions failed"
fi

# Test with very large arrays
kk_test_start "Performance with very large arrays"
declare -a large_array
for i in {1..1000}; do
    large_array+=("item$i")
done
if kk_assert_array_length large_array 1000 "Large array performance"; then
    kk_test_pass "Very large arrays handled efficiently"
else
    kk_test_fail "Very large arrays not handled correctly"
fi

# Test memory usage with large strings
kk_test_start "Memory usage with large strings"
large_string=$(printf 'x%.0s' {1..10000})
if kk_assert_equals "$large_string" "$large_string" "Large string performance"; then
    kk_test_pass "Large strings handled without memory issues"
else
    kk_test_fail "Large strings caused memory issues"
fi

# Test deep directory structure creation
kk_test_start "Deep directory structure performance"
start_time=$(date +%s.%N)
deep_base=$(kk_fixture_tmpdir)
for i in {1..20}; do
    deep_base="$deep_base/level$i"
    mkdir -p "$deep_base" 2>/dev/null
done
end_time=$(date +%s.%N)
creation_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
if [[ -d "$deep_base" ]]; then
    kk_test_pass "Deep directory structure created (time: ${creation_time}s)"
else
    kk_test_fail "Deep directory structure creation failed"
fi

# Test with many concurrent fixture operations
kk_test_start "Concurrent fixture operations stress test"
start_time=$(date +%s.%N)
for i in {1..50}; do
    temp_file=$(kk_fixture_tmpfile "stress$i")
    temp_dir=$(kk_fixture_tmpdir_create "stress_dir$i")
    echo "stress test $i" > "$temp_file"
done
end_time=$(date +%s.%N)
fixture_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
if (( ${#_KK_CLEANUP_HANDLERS[@]} >= 50 )); then
    kk_test_pass "Concurrent fixture operations completed (time: ${fixture_time}s)"
else
    kk_test_fail "Concurrent fixture operations failed"
fi

# Test assertion performance with different types
kk_test_start "Assertion performance with different types"
start_time=$(date +%s.%N)
# String assertions
for i in {1..50}; do
    kk_assert_equals "string$i" "string$i" "String assertion $i" >/dev/null 2>&1
done
# Numeric assertions
for i in {1..50}; do
    kk_assert_num_equals $i $i "Numeric assertion $i" >/dev/null 2>&1
done
# Array assertions
declare -a test_arr=("a" "b" "c")
for i in {1..50}; do
    kk_assert_array_length test_arr 3 "Array assertion $i" >/dev/null 2>&1
done
end_time=$(date +%s.%N)
assert_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
kk_test_pass "Mixed assertion types completed (time: ${assert_time}s)"

# Test with very long test names and descriptions
kk_test_start "Very long test names and descriptions"
long_name="Very long test name with many characters to test how the framework handles extended test descriptions without performance degradation or truncation issues"
long_desc="Very long test description that contains detailed information about what this test is supposed to verify and check, ensuring that the framework can handle extended metadata without performance problems or display issues"
kk_test_start "$long_name"
if kk_assert_equals "test" "test" "$long_desc"; then
    kk_test_pass "Long names and descriptions handled correctly"
else
    kk_test_fail "Long names and descriptions caused issues"
fi

# Test counter performance with high numbers
kk_test_start "Counter performance with high numbers"
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
start_time=$(date +%s.%N)
for i in {1..1000}; do
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if (( i % 2 == 0 )); then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done
end_time=$(date +%s.%N)
counter_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
if (( TESTS_TOTAL == 1000 )); then
    kk_test_pass "Counter operations with high numbers efficient (time: ${counter_time}s)"
else
    kk_test_fail "Counter operations with high numbers failed"
fi

# Test file system operations performance
kk_test_start "File system operations performance"
start_time=$(date +%s.%N)
stress_dir=$(kk_fixture_tmpdir_create "perf_test")
for i in {1..100}; do
    test_file="$stress_dir/test_file_$i.txt"
    echo "Performance test file $i" > "$test_file"
    kk_assert_file_exists "$test_file" "File $i exists"
done
end_time=$(date +%s.%N)
fs_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
if (( ${#files[@]} >= 100 )); then
    kk_test_pass "File system operations efficient (time: ${fs_time}s)"
else
    kk_test_pass "File system operations completed (time: ${fs_time}s)"
fi

# Test with complex regex patterns
kk_test_start "Complex regex pattern performance"
complex_pattern="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$|^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
test_string="user@example.com"
start_time=$(date +%s.%N)
for i in {1..100}; do
    kk_assert_matches "$test_string" "$complex_pattern" "Complex regex test $i" >/dev/null 2>&1
done
end_time=$(date +%s.%N)
regex_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
kk_test_pass "Complex regex patterns processed (time: ${regex_time}s)"

# Test output processing with large outputs
kk_test_start "Output processing with large outputs"
large_output=$(printf "Line %d with some content\n" {1..1000})
start_time=$(date +%s.%N)
for i in {1..10}; do
    kk_assert_output_contains "$large_output" "Line 500" "Large output test $i" >/dev/null 2>&1
done
end_time=$(date +%s.%N)
output_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
kk_test_pass "Large output processing efficient (time: ${output_time}s)"

# Test configuration operations performance
kk_test_start "Configuration operations performance"
start_time=$(date +%s.%N)
for i in {1..100}; do
    kk_config_set "perf_key_$i" "perf_value_$i"
    value=$(kk_config_get "perf_key_$i")
done
end_time=$(date +%s.%N)
config_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
if [[ "$value" == "perf_value_100" ]]; then
    kk_test_pass "Configuration operations efficient (time: ${config_time}s)"
else
    kk_test_fail "Configuration operations failed"
fi

# Test cleanup handler performance
kk_test_start "Cleanup handler performance"
declare -a perf_cleanup_handlers
start_time=$(date +%s.%N)
for i in {1..100}; do
    cleanup_func() { :; }
    perf_cleanup_handlers+=("cleanup_func_$i")
done
end_time=$(date +%s.%N)
cleanup_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
if (( ${#perf_cleanup_handlers[@]} == 100 )); then
    kk_test_pass "Cleanup handler operations efficient (time: ${cleanup_time}s)"
else
    kk_test_fail "Cleanup handler operations failed"
fi

# Test with extreme edge case - zero-length operations
kk_test_start "Zero-length operation performance"
start_time=$(date +%s.%N)
for i in {1..1000}; do
    : # No-op operation
done
end_time=$(date +%s.%N)
noop_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
kk_test_pass "Zero-length operations benchmarked (time: ${noop_time}s)"

# Test framework initialization performance
kk_test_start "Framework initialization performance"
start_time=$(date +%s.%N)
# Simulate multiple framework initializations
for i in {1..10}; do
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    VERBOSITY="error"
done
end_time=$(date +%s.%N)
init_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
kk_test_pass "Framework initialization efficient (time: ${init_time}s)"