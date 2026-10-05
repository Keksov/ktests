#!/bin/bash
# Unit tests: Direct test runner execution functions

# Only source if framework not already loaded
if [[ -z "$_KTEST_SOURCED" ]]; then
    source "$(dirname "$0")/../ktest_source.sh" || source "$KTEST_SOURCE_PATH" || exit 1
fi

kt_test_init "DirectRunnerExecution" "$(dirname "$0")"

TMPDIR=$(kt_fixture_tmpdir)
TEST_DIR=$(kt_fixture_tmpdir_create "runner_test")

# Create sample test files for execution testing
kt_test_start "Create sample test files for execution"
FRAMEWORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ktest.sh"

cat > "$TEST_DIR/test1.sh" << EOF
#!/bin/bash
source "$FRAMEWORK_PATH"
kt_test_init "Test1" "\$(dirname "\$0")"
kt_test_start "Test 1 assertion"
if kt_assert_equals "test1" "test1" "Test 1 should pass"; then
    kt_test_pass "Test 1"
else
    kt_test_fail "Test 1"
fi
EOF

cat > "$TEST_DIR/test2.sh" << EOF
#!/bin/bash
source "$FRAMEWORK_PATH"
kt_test_init "Test2" "\$(dirname "\$0")"
kt_test_start "Test 2 assertion"
if kt_assert_equals "test2" "test2" "Test 2 should pass"; then
    kt_test_pass "Test 2"
else
    kt_test_fail "Test 2"
fi
EOF

cat > "$TEST_DIR/test3.sh" << EOF
#!/bin/bash
source "$FRAMEWORK_PATH"
kt_test_init "Test3" "\$(dirname "\$0")"
kt_test_start "Test 3 assertion"
if kt_assert_equals "test3" "different" "Test 3 should fail"; then
    kt_test_pass "Test 3"
else
    kt_test_fail "Test 3"
fi
EOF

chmod +x "$TEST_DIR/test1.sh" "$TEST_DIR/test2.sh" "$TEST_DIR/test3.sh"

if [[ -x "$TEST_DIR/test1.sh" && -x "$TEST_DIR/test2.sh" && -x "$TEST_DIR/test3.sh" ]]; then
    kt_test_pass "Sample test files created and made executable"
else
    kt_test_fail "Failed to create sample test files"
fi


# kt022_run MODE FN ARGS... - run a runner function IN A SUBSHELL with zeroed counters
# and print that run's "TOTAL:PASSED:FAILED|FAILED_TEST_FILES|rc". The runner resets
# and adds to TESTS_TOTAL/PASSED/FAILED in-process; run here, it used to clobber this
# file's own counters (and the file zeroed them six times), so any assertion before
# the last reset was invisible to the outer runner (round 4, review R1).
kt022_run() {
    local __mode="$1"; shift
    (
        MODE="$__mode"
        TESTS_TOTAL=0; TESTS_PASSED=0; TESTS_FAILED=0; FAILED_TEST_FILES=()
        __rc=0
        "$@" >/dev/null 2>&1 || __rc=$?
        printf '%s:%s:%s|%s|%s' "$TESTS_TOTAL" "$TESTS_PASSED" "$TESTS_FAILED" "${FAILED_TEST_FILES[*]}" "$__rc"
    )
}

# kt022_check NAME GOT WANT
kt022_check() {
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1: got '$2', want '$3'"
    fi
}

# Test kt_runner_execute_sequential with multiple files: test1/test2 pass, test3 fails
kt_test_start "kt_runner_execute_sequential with multiple test files"
_r="$(kt022_run single kt_runner_execute_sequential "$TEST_DIR/test1.sh" "$TEST_DIR/test2.sh" "$TEST_DIR/test3.sh")"
kt022_check "Sequential execution counts and failed list" "$_r" "3:2:1|test3.sh|0"

# Test kt_runner_execute_threaded function exists
kt_test_start "kt_runner_execute_threaded function availability"
if declare -f kt_runner_execute_threaded > /dev/null 2>&1; then
    kt_test_pass "kt_runner_execute_threaded function is available"
else
    kt_test_fail "kt_runner_execute_threaded function not found"
fi

# Test kt_runner_execute_threaded execution
kt_test_start "kt_runner_execute_threaded execution test"
_r="$(kt022_run threaded kt_runner_execute_threaded "$TEST_DIR/test1.sh" "$TEST_DIR/test2.sh" "$TEST_DIR/test3.sh")"
kt022_check "Threaded execution counts and failed list" "$_r" "3:2:1|test3.sh|0"

# Test kt_runner_execute_tests with specific directory
kt_test_start "kt_runner_execute_tests with specific directory"
# Create a directory with properly named test files for directory scanning
dir_test_dir=$(kt_fixture_tmpdir_create "dir_scan_test")

cat > "$dir_test_dir/001_test.sh" << EOF
#!/bin/bash
source "$FRAMEWORK_PATH"
kt_test_init "DirTest1" "\$(dirname "\$0")"
kt_test_start "Dir test 1"
kt_assert_equals "a" "a" "Should pass" && kt_test_pass "Dir test 1"
EOF

cat > "$dir_test_dir/002_test.sh" << EOF
#!/bin/bash
source "$FRAMEWORK_PATH"
kt_test_init "DirTest2" "\$(dirname "\$0")"
kt_test_start "Dir test 2"
kt_assert_equals "b" "b" "Should pass" && kt_test_pass "Dir test 2"
EOF

chmod +x "$dir_test_dir/001_test.sh" "$dir_test_dir/002_test.sh"

_r="$(kt022_run threaded kt_runner_execute_tests "$dir_test_dir")"
kt022_check "Directory execution (threaded) found and ran both files" "$_r" "2:2:0||0"

# Test execution with non-existent files: since round 3 T4b a missing file counts
# 1:0:1 and is listed in FAILED_TEST_FILES, in sequential and threaded alike.
kt_test_start "Execution with non-existent files (sequential)"
_r="$(kt022_run single kt_runner_execute_sequential "$TEST_DIR/nonexistent.sh")"
kt022_check "Missing file counts 1:0:1 and is listed (sequential)" "$_r" "1:0:1|nonexistent.sh|0"

kt_test_start "Execution with non-existent files (threaded)"
_r="$(kt022_run threaded kt_runner_execute_threaded "$TEST_DIR/nonexistent.sh")"
kt022_check "Missing file counts 1:0:1 and is listed (threaded)" "$_r" "1:0:1|nonexistent.sh|0"

# Test mixed file existence in execution
kt_test_start "Mixed file existence in execution"
_r="$(kt022_run single kt_runner_execute_sequential "$TEST_DIR/test1.sh" "$TEST_DIR/nonexistent.sh" "$TEST_DIR/test2.sh")"
kt022_check "Mixed files: two run, the missing one counts as a failure" "$_r" "3:2:1|nonexistent.sh|0"

# Test runner execution in single mode
kt_test_start "Runner execution with different modes"
_r="$(kt022_run single kt_runner_execute_tests "$dir_test_dir")"
kt022_check "Directory execution (single) found and ran both files" "$_r" "2:2:0||0"

# Test execution tracking
kt_test_start "Execution result tracking"
_r="$(kt022_run single kt_runner_execute_sequential "$TEST_DIR/test1.sh" "$TEST_DIR/test2.sh")"
kt022_check "Execution tracking records passed tests" "$_r" "2:2:0||0"

# Test with empty directory: nothing to run is an error (rc 1), nothing counted
kt_test_start "Execution with empty directory"
empty_dir=$(kt_fixture_tmpdir_create "empty")
_r="$(kt022_run threaded kt_runner_execute_tests "$empty_dir")"
kt022_check "Empty directory execution handled correctly" "$_r" "0:0:0||1"

# Test execution with permission issues (chmod 000 may be a no-op on Windows):
# it must still produce one counted result for the one file
kt_test_start "Execution with permission-restricted files"
chmod 000 "$TEST_DIR/test1.sh"
_r="$(kt022_run single kt_runner_execute_sequential "$TEST_DIR/test1.sh")"
chmod 755 "$TEST_DIR/test1.sh"
if [[ "$_r" == "1:1:0||0" || "$_r" == "1:0:1|test1.sh|0" ]]; then
    kt_test_pass "Permission restriction test completed"
else
    kt_test_fail "Permission restriction: got '$_r'"
fi

# Test state isolation: a runner call made through kt022_run leaves this file's
# own counters and failed list untouched
kt_test_start "Concurrent execution state isolation"
_before="$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED|${FAILED_TEST_FILES[*]}"
_r="$(kt022_run single kt_runner_execute_sequential "$TEST_DIR/test3.sh")"
_after="$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED|${FAILED_TEST_FILES[*]}"
kt022_check "Runner call leaves the caller's counters alone" "$_after|$_r" "$_before|1:0:1|test3.sh|0"

# Test runner help functionality
kt_test_start "Runner help functionality"
help_output=$(kt_runner_show_help 2>&1)
if [[ "$help_output" == *"--mode"* ]]; then
    kt_test_pass "Help functionality works"
else
    kt_test_fail "Help output lacks --mode: '$help_output'"
fi
