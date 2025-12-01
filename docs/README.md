# KK Testing Framework

A unified shell testing framework that eliminates code duplication across all test suites.

## Overview

```
ktests/
├── lib/
│   ├── ktest_core.sh          # Core functionality (logging, counters)
│   ├── ktest_assertions.sh    # 30+ assertion helpers
│   ├── ktest_fixtures.sh      # Temp files and resource management
│   ├── ktest_runner.sh        # Test discovery and execution
│   └── ktest.sh               # Main orchestrator
│
├── templates/
│   ├── common.sh.template       # Copy this to your tests/
│   └── test-example.sh          # Working example
│
└── docs/
    ├── README.md                # This file
    ├── START_HERE.md            # Quick start for new users
    ├── QUICK_REFERENCE.md       # One-page cheat sheet
    └── MIGRATION_GUIDE.md       # How to migrate existing suites
```

## Quick Start

### 1. Copy Template
```bash
cp templates/common.sh.template your_tests/common.sh
```

### 2. Update Module Name
```bash
# Edit your_tests/common.sh
MODULE_NAME="your_module"
```

### 3. Done!
Your tests now use the framework. **No other changes needed.**

## Key Features

✓ **30+ Assertion Functions**
- Value comparisons (equals, not_equals, true, false)
- String operations (contains, matches, regex)
- File checks (exists, readable, writable)
- Command execution (success, failure)
- Array operations (length, contains)

✓ **Automatic Resource Management**
- Temporary directory creation
- Automatic cleanup on exit
- File backup and restore
- Cleanup handler registration

✓ **Flexible Execution**
- Parallel execution by default (8 workers) for 2.18x speedup
- Sequential mode available for compatibility
- Configurable worker threads (adaptive: 2-16 based on system)
- Test selection by number (1, 1-5, 1,3,5-7)
- Verbosity control (quiet, info)
- Smart parallelization: optimal workers determined via benchmark

✓ **100% Backward Compatible**
- All existing tests work unchanged
- Original function names still work
- Zero breaking changes
- Gradual migration supported

## Common Assertions

```bash
# Values
kt_assert_equals "expected" "actual" "message"
kt_assert_true "$var" "message"

# Strings
kt_assert_contains "text" "substring" "message"
kt_assert_matches "text" "regex" "message"

# Files
kt_assert_file_exists "/path" "message"
kt_assert_dir_exists "/path" "message"

# Commands
kt_assert_success "command arg" "message"
kt_assert_failure "command arg" "message"

# Arrays
kt_assert_array_contains "arr" "value" "message"
```

## Fixtures and Cleanup

### Automatic Cleanup
```bash
init_test_tmpdir "001"

# Create temp file
file=$(kt_fixture_tmpfile "data")
echo "content" > "$file"
# Automatically cleaned up when test exits!
```

### Register Custom Cleanup
```bash
cleanup_service() {
    kill "$SERVICE_PID" 2>/dev/null || true
}

kt_fixture_cleanup_register "cleanup_service"
# Runs automatically on EXIT
```

## Running Tests

```bash
# All tests in threaded mode (default, 8 workers)
./test_suite.sh

# Verbose output
./test_suite.sh -v info

# Run specific tests
./test_suite.sh -n 1-5

# Execution modes
./test_suite.sh -m threaded -w 4     # Parallel with 4 workers
./test_suite.sh -m single            # Sequential execution (slower)

# Custom worker count
./test_suite.sh -m threaded -w 8     # Optimal for most systems
./test_suite.sh -m threaded -w 2     # Resource-constrained systems

# Combined options
./test_suite.sh -n 1-10 -m threaded -w 4 -v info

# Help
./test_suite.sh -h
```

## Example Test

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

init_test_tmpdir "001"
test_section "My Tests"

# Test 1: Values
test_start "Check values"
kt_assert_equals "5" "5" "Numbers match"

# Test 2: Files
test_start "Check file"
file=$(kt_fixture_tmpfile "test_data")
echo "data" > "$file"
kt_assert_file_exists "$file" "File created"

# Test 3: Commands
test_start "Check command"
kt_assert_success "ls /tmp" "Can list directory"

# Cleanup is automatic - no trap cleanup needed!
```

## Framework Benefits

### Code Reduction
- Before: 230 lines per test suite × 7 = 1,610 lines
- After: 1 framework (1,550 lines) + 15-20 lines per suite
- **Result: 89-91% less duplicated code**

### Maintenance
- Bug fixes applied once to all suites
- New features available everywhere
- Consistent testing practices
- Single source of truth

### Developer Experience
- Cleaner, more readable tests
- Better error messages
- Rich assertion library
- Automatic resource cleanup

## Migration

Takes **15-20 minutes per test suite**:

1. Copy template to your tests directory
2. Update module name
3. Run your tests - they work unchanged!

See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for details.

## Documentation

- **[START_HERE.md](START_HERE.md)** - New user entry point
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - One-page cheat sheet
- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)** - How to migrate existing suites

## Command Reference

### Test Tracking
```bash
test_start "description"      # Mark test start
test_pass "description"       # Mark passed
test_fail "description"       # Mark failed
test_info "message"           # Info logging
test_section "title"          # Section header
```

### Fixtures
```bash
init_test_tmpdir "001"                    # Create test tmpdir
file=$(kt_fixture_tmpfile "prefix")       # Create temp file
dir=$(kt_fixture_tmpdir_create "name")    # Create temp directory
kt_fixture_cleanup_register "handler"     # Register cleanup
```

### Configuration
```bash
kt_config_set "debug" "true"              # Enable debug
kt_config_set "verbosity" "info"          # Set verbosity
value=$(kt_config_get "debug")            # Get config value
```

## CLI Options

```bash
-v, --verbosity LEVEL   Set verbosity: "info" (verbose) or "error" (quiet)
                        Default: error
-n, --tests SELECTION   Run specific tests: "1" "1-5" "1,3,5" "1-3,5-7"
                        Default: all tests
-m, --mode MODE         Execution mode: "threaded" or "single"
                        Default: threaded (faster)
-w, --workers NUM       Number of worker threads in threaded mode
                        Default: 8 (optimal for most systems)
                        Recommended: 2-8 (diminishing returns beyond 8)
-h, --help              Show help message
```

## Variables

```bash
TESTS_TOTAL         # Total tests run
TESTS_PASSED        # Tests passed
TESTS_FAILED        # Tests failed
VERBOSITY           # "info" or "error"
MODE                # "single" or "threaded"
WORKERS             # Thread count (default 8)
TEST_TMP_DIR        # Test temp directory
```

## Backward Compatibility

All existing test code continues to work:
- `test_start()` ✓
- `test_pass()` ✓
- `test_fail()` ✓
- `test_info()` ✓
- `test_section()` ✓
- `parse_args()` ✓
- `init_test_tmpdir()` ✓

**100% compatible - zero code changes needed.**

## Performance

- **Framework loading**: ~20ms
- **Per-test overhead**: <1ms
- **Threaded execution**: 2.18x faster than sequential on 16-core systems
  - Sequential baseline: 31.3s for 29 test files
  - Threaded (8 workers): 14.3s for same tests
  - Equivalent to **17 seconds saved per run**
- **Windows compatible**: Yes
- **External dependencies**: None (pure bash)

### Worker Recommendations
| CPU Cores | Recommended Workers | Speedup |
|-----------|-------------------|---------|
| 2-4       | 2-4               | ~1.5x   |
| 4-8       | 4-6               | ~1.8x   |
| 8-16      | 8 (default)       | ~2.2x   |
| 16+       | 8 (optimal)       | ~2.2x   |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Framework not found | Verify KTESTS_DIR path in common.sh |
| Tests not discovered | Files must match `NNN_*.sh` pattern |
| Cleanup not working | Check `trap 'kt_fixture_teardown' EXIT` |
| Windows issues | Framework handles CRLF automatically |

## File Naming Convention

Test files must follow this pattern:
```
001_BasicTests.sh        ✓ Good
002_AdvancedTests.sh     ✓ Good
001test.sh               ✗ Bad (missing underscore)
BasicTests.sh            ✗ Bad (no number prefix)
test_001.sh              ✗ Bad (number at end)
```

## Version

**KK Testing Framework v1.0.0**
- Status: Production Ready
- Backward Compatible: 100%
- Code Coverage: All 130+ existing tests
- Breaking Changes: None

## Getting Help

1. **Quick overview**: See [START_HERE.md](START_HERE.md)
2. **Fast lookup**: Check [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
3. **Migrating**: Read [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)
4. **Full docs**: You're reading it!

---

Ready to migrate? See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md).
