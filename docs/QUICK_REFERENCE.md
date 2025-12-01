# KK Testing Framework - Quick Reference

## Setup

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_DIR="$(dirname "$SCRIPT_DIR")/../ktests"
source "$KTESTS_DIR/lib/ktest.sh"
kt_test_init "module_name" "$SCRIPT_DIR"
kt_runner_parse_args "$@"
```

## Test Structure

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

init_test_tmpdir "001"
test_section "Test Category"

test_start "My first test"
kt_assert_equals "expected" "actual" "message"
kt_assert_file_exists "/path" "message"
# Cleanup is automatic
```

## Common Assertions

### Values
```bash
kt_assert_equals "val1" "val2" "message"
kt_assert_not_equals "a" "b" "message"
kt_assert_true "$bool" "message"
kt_assert_false "$bool" "message"
```

### Strings
```bash
kt_assert_contains "text" "substr" "message"
kt_assert_matches "text" "regex" "message"
kt_assert_output_contains "$output" "text" "message"
```

### Files
```bash
kt_assert_file_exists "/path/file" "message"
kt_assert_file_readable "/path/file" "message"
kt_assert_dir_exists "/path/dir" "message"
```

### Commands
```bash
kt_assert_success "ls /tmp" "message"
kt_assert_failure "ls /bad" "message"
```

### Arrays
```bash
kt_assert_array_length "arr" 5 "message"
kt_assert_array_contains "arr" "value" "message"
```

## Fixtures

```bash
# Temp file
file=$(kt_fixture_tmpfile "prefix")
echo "data" > "$file"

# Temp directory
dir=$(kt_fixture_tmpdir)
tmpdir=$(kt_fixture_tmpdir_create "subdir")

# Create with content
kt_fixture_create_file "config.txt" "key=value"

# Backup and restore
backup=$(kt_fixture_backup_file "/etc/config")
# Restored automatically on teardown
```

## Running Tests

```bash
# All tests (parallel, 8 workers - default)
./test_suite.sh

# Verbose output
./test_suite.sh -v info

# Specific tests
./test_suite.sh -n 1              # Test 1
./test_suite.sh -n 1-5            # Tests 1-5
./test_suite.sh -n 1,3,5          # Tests 1, 3, 5
./test_suite.sh -n 1-3,5-7        # Tests 1-3 and 5-7

# Execution modes
./test_suite.sh -m threaded -w 4  # Parallel with 4 workers
./test_suite.sh -m threaded -w 8  # Parallel with 8 workers (optimal)
./test_suite.sh -m single         # Sequential (slower, no parallelism)

# Combined
./test_suite.sh -n 1-10 -m threaded -w 4 -v info

# Help
./test_suite.sh -h
```

## Logging

```bash
test_start "Description"           # Mark test start
test_pass "Description"            # Mark passed
test_fail "Description"            # Mark failed
test_info "Info message"           # Log info
test_section "Section Title"       # Section header

# New API
kt_test_log "message"
kt_test_debug "message"
kt_test_error "message"
kt_test_warning "message"
```

## Configuration

```bash
kt_config_set "debug" "true"
kt_config_set "verbosity" "info"
value=$(kt_config_get "debug")
```

## Cleanup Handlers

```bash
cleanup_my_resources() {
    [[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true
    rm -f "$TEMP_FILE"
}

kt_fixture_cleanup_register "cleanup_my_resources"
# Handler runs automatically on EXIT
```

## CLI Options

```bash
-v, --verbosity LEVEL    Verbosity: "info" or "error" (default: error)
-n, --tests SELECTION    Tests to run: "1" "1-5" "1,3,5" (default: all)
-m, --mode MODE          Execution: "threaded" (default) or "single"
-w, --workers NUM        Workers in threaded mode (default: 8)
-h, --help               Show help
```

## Module Variables

```bash
TESTS_TOTAL         # Total tests
TESTS_PASSED        # Passed count
TESTS_FAILED        # Failed count
VERBOSITY           # "info" or "error"
MODE                # "single" or "threaded"
WORKERS             # Thread count (default 8, optimal)
TEST_TMP_DIR        # Test temp directory
```

## Common Patterns

### Test with setup/cleanup
```bash
init_test_tmpdir "001"
setup_test_db
kt_fixture_cleanup_register "teardown_test_db"

test_start "Database test"
# Test logic
```

### Multiple assertions
```bash
test_start "Multiple checks"
kt_assert_equals "a" "$val1" "First check"
kt_assert_equals "b" "$val2" "Second check"
kt_assert_file_exists "$output" "Output file"
```

### Error checking
```bash
test_start "Error handling"
if ! kt_assert_success "dangerous_cmd"; then
    kt_test_log "Command failed as expected"
fi
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Framework not found | Check KTESTS_DIR path in common.sh |
| Tests not discovered | Ensure files match `NNN_*.sh` pattern |
| Temp files not cleaned | Verify `trap 'kt_fixture_teardown' EXIT` |
| Assertions not working | Check argument order |
| Windows path issues | Framework handles CRLF automatically |
| Debug output missing | Enable with `kt_config_set "debug" "true"` |

## File Naming

```
001_BasicTests.sh          ✓ Good
002_AdvancedTests.sh       ✓ Good
01_test.sh                 ✓ Works
001test.sh                 ✗ Bad (missing underscore)
BasicTests.sh              ✗ Bad (no number prefix)
test_001.sh                ✗ Bad (number at end)
```

## Performance Tips

- **Default mode is fast**: Uses 8 worker threads by default (2.18x speedup)
- **No configuration needed**: Just run `./test_suite.sh` for optimal performance
- **For slow systems**: Use `-m single` or `-w 2` to reduce resource usage
- **For CI/CD**: Default settings work great; set `-w 4` for shared resources

## Cheat Sheet

```bash
# Minimal test
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

init_test_tmpdir "001"
test_start "My test"
kt_assert_equals "expected" "actual" "message"
# Done! Cleanup is automatic
```

```bash
# Fast test runner (parallel, 8 workers)
./test_suite.sh

# Slow test runner (sequential)
./test_suite.sh -m single

# Medium speed (4 workers)
./test_suite.sh -m threaded -w 4
```

## Version

KK Testing Framework v1.0.0
