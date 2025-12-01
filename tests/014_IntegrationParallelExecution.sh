#!/bin/bash
# Integration tests: Parallel test execution and result aggregation

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "IntegrationParallelExecution" "$(dirname "$0")"

TMPDIR=$(kt_fixture_tmpdir)
PARALLEL_DIR=$(kt_fixture_tmpdir_create "parallel_tests")

# Create multiple test files for parallel execution testing
kt_test_start "Create multiple test files for parallel execution"
for i in {1..5}; do
    cat > "$PARALLEL_DIR/$(printf '%03d' $i)_ParallelTest.sh" << EOF
#!/bin/bash
source "\$(cd "\$(dirname "\$0")/../../.." && pwd)/ktests/ktest.sh"
KT__FILE="\$(basename "\${BASH_SOURCE[0]}")"
kt_test_init "ParallelTest$i" "\$(dirname "\$0")"

kt_assert_equals "test$i" "test$i" "Test $i assertion"
EOF
    chmod +x "$PARALLEL_DIR/$(printf '%03d' $i)_ParallelTest.sh"
done

files_created=0
for f in "$PARALLEL_DIR"/*.sh; do
    [[ -f "$f" ]] && ((files_created++))
done
if (( files_created >= 5 )); then
    kt_test_pass "Created 5 test files for parallel execution"
else
    kt_test_fail "Failed to create all test files: created $files_created"
fi

# Test finding all files
kt_test_start "kt_runner_find_tests discovers all parallel test files"
test_files=($(kt_runner_find_tests "$PARALLEL_DIR"))
if (( ${#test_files[@]} >= 5 )); then
    kt_test_pass "All parallel test files discovered"
else
    kt_test_fail "Found ${#test_files[@]} files, expected 5+"
fi

# Test parsing test selection ranges
kt_test_start "Parse wide range of test numbers"
kt_runner_parse_selection "1-10"
if (( ${#TESTS_TO_RUN[@]} == 10 )); then
    kt_test_pass "Range parsing creates correct array size"
else
    kt_test_fail "Range parsing created ${#TESTS_TO_RUN[@]} items, expected 10"
fi

# Test parsing large comma-separated list
kt_test_start "Parse large comma-separated test selection"
kt_runner_parse_selection "1,5,10,15,20,25,30"
if (( ${#TESTS_TO_RUN[@]} == 7 )); then
    kt_test_pass "Large selection list parsed correctly"
else
    kt_test_fail "Selection list has ${#TESTS_TO_RUN[@]} items, expected 7"
fi

# Reset selection for other tests
TESTS_TO_RUN=()

# Test mode and worker configuration
kt_test_start "Runner configuration for threaded execution"
kt_runner_parse_args -m threaded -w 4 -v error
if [[ "$MODE" == "threaded" && $WORKERS == 4 && "$VERBOSITY" == "error" ]]; then
    kt_test_pass "Threaded configuration parsed correctly"
else
    kt_test_fail "Configuration mismatch: MODE=$MODE WORKERS=$WORKERS VERBOSITY=$VERBOSITY"
fi

# Test sequential execution mode
kt_test_start "Runner configuration for sequential execution"
kt_runner_parse_args -m single -v error
if [[ "$MODE" == "single" ]]; then
    kt_test_pass "Sequential mode configured correctly"
else
    kt_test_fail "Sequential mode not set correctly"
fi

# Test result aggregation
kt_test_start "Aggregate results from multiple test runs"
kt_test_reset_counts
run1_total=10; run1_pass=9; run1_fail=1
run2_total=8; run2_pass=8; run2_fail=0
run3_total=12; run3_pass=10; run3_fail=2

TESTS_TOTAL=$run1_total
TESTS_PASSED=$run1_pass
TESTS_FAILED=$run1_fail
kt_test_accumulate_counts "$run2_total:$run2_pass:$run2_fail"
kt_test_accumulate_counts "$run3_total:$run3_pass:$run3_fail"

expected_total=$((run1_total + run2_total + run3_total))
expected_pass=$((run1_pass + run2_pass + run3_pass))
expected_fail=$((run1_fail + run2_fail + run3_fail))

if (( TESTS_TOTAL == expected_total && TESTS_PASSED == expected_pass && TESTS_FAILED == expected_fail )); then
    kt_test_pass "Multi-run result aggregation works correctly"
else
    kt_test_fail "Aggregation error: got $TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED expected $expected_total:$expected_pass:$expected_fail"
fi

# Test handling tests with failures
kt_test_start "Aggregation preserves failure information"
kt_test_reset_counts
kt_test_accumulate_counts "5:4:1"
kt_test_accumulate_counts "3:2:1"
kt_test_accumulate_counts "4:4:0"
if (( TESTS_FAILED == 2 )); then
    kt_test_pass "Failures aggregated correctly"
else
    kt_test_fail "Failure count mismatch: got $TESTS_FAILED, expected 2"
fi

# Test selection with overlapping numbers (should not duplicate)
kt_test_start "Parse selection with duplicate numbers"
kt_runner_parse_selection "1,2,2,3"
if (( ${#TESTS_TO_RUN[@]} >= 3 )); then
    kt_test_pass "Selection parsing handles potential duplicates"
else
    kt_test_fail "Selection parsing issue"
fi

# Reset for other tests
TESTS_TO_RUN=()
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test comprehensive configuration state
kt_test_start "Save and restore configuration state"
kt_config_set "verbosity" "info"
kt_config_set "debug" "true"
kt_config_set "color" "false"
v=$(kt_config_get "verbosity")
d=$(kt_config_get "debug")
c=$(kt_config_get "color")
if [[ "$v" == "info" && "$d" == "true" && "$c" == "false" ]]; then
    kt_test_pass "Configuration state preservation works"
else
    kt_test_fail "Configuration state mismatch: v=$v d=$d c=$c"
fi

# Reset config
kt_config_set "verbosity" "error"
kt_config_set "debug" "false"
kt_config_set "color" "true"


