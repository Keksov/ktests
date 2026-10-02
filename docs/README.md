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
│   ├── ktest_env_signatures.sh # cygwin fork-failure signatures (runner + tools)
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

**Never `trap … EXIT` in a test.** `kt_test_init` installs the EXIT trap that
runs the fixture teardown — your registered handlers (e.g. the restores
`kt_fixture_backup_file` registers) and the removal of the fixture dir
`<tests>/.tmp/<Name>.<file>`. A test's own `trap … EXIT` REPLACES it, so none of
that runs. Register a handler instead (one that first `cd`s out of a directory
it is about to remove). If a fixture dir is still there after a file ran, the
runner removes it and prints
`[WARN] <file>: fixture dir .tmp/<dir> left behind (own EXIT trap?) …`; a
standalone `bash FILE` wipes such a stale dir at its next setup (a dir created
earlier by the same process is kept).

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

## How the Runner Judges a Test File

Each file runs in its own `bash -c` wrapper that sources the framework, then
`source`s the file, then prints an END marker
`__KT_END_<nonce>__:<source rc>:<total>:<passed>:<failed>:<return status>` and the
counts line `__COUNTS__:<total>:<passed>:<failed>`. The nonce is fresh for every
run of every file and only the marker with that nonce counts (a nested runner
inside a test prints markers of its own). Neither line is ever shown in the
output. `<return status>` is the `$?` a RETURN trap set around the `source` saw
when the file's own source returned (`x` if it did not fire): a file that falls
off its end gives the status of its last command — the source rc — while a
file-scope `return N` gives the status of the command BEFORE the `return`.

A file whose assertions merely fail is counted as before. A file that did not run
to its end is **aborted** and is FAILED even when every test it reached passed:

| what the runner sees | cause in the `[FAIL]` line |
|---|---|
| no END marker — the shell exited: `exit N`, `set -u` on an unset variable, `${v:?}`, `set -e` + a failing command (a test's own EXIT trap alone does not remove the marker; with an `exit` the file also has no counts line and is counted `1:0:1`) | `shell exited mid-file (child rc=N)` |
| END marker with source rc >= 2 — an inline syntax error, a file-scope `return N` | `source returned rc=N` |
| END marker with source rc 0/1 and a return status different from it — a file-scope `return` (`return 1` between tests, `if …; then return 1; fi`, `cond \|\| return 0`, `eval "return 1"`, also under `set -T`) | `file-scope return (source rc=R after status S)` |
| at END, total > passed + failed — a test was started and its block never closed | `test aborted mid-block` |
| a bash fatal diagnostic `<file>: line N: …` (expression recursion level exceeded, bad array subscript, invalid variable name, circular name reference, division by 0, unbound variable, syntax error) — the command that hit it was dropped, the rest of the file ran | `bash error at <file>:<N>: <message>` |

An aborted file counts one more test, failed (`total+1`, `failed+1`), its output
is shown with the bash diagnostic, and the runner adds the line
`[FAIL] <file>: source aborted (<cause>)`. Two rules are one-sided on purpose: a
test that passes twice (passed > total) is legal, and a source rc of 1 alone is
just a trailing false-y command (`[[ -d $x ]] && rm -rf "$x"`), not a verdict —
the return status tells the two apart. What the return status cannot see (no
verdict, the file is green with a lower total): `cmd || return N` where `cmd`'s
own status was N, a bare `return` (it returns the previous status), and a file
that installs its own RETURN trap (it replaces the runner's, which then never
fires). A nested `source` of a library and functions under `set -T` fire the
trap at depth ≥ 1 and are ignored.

A test file that does not exist is counted `1:0:1` and listed as FAILED in both
execution modes. A fixture dir the file left behind (its EXIT trap was replaced)
is removed by the runner with a `[WARN]` line — see Fixtures and Cleanup.

A file is re-run (up to 3 attempts, 0.1 s apart) only when it left no END
marker, no counts line, AND printed nothing or a cygwin fork failure (the
signatures in `ktest_env_signatures.sh`, shared with `tools/timing_check.sh`):
that is a worker that died before it could start under load. Anything else is
judged at once.

Never call `exit` in a test file, do not put tests after a `return` — both end
the file early and are reported as aborts — and never `trap … EXIT` (the runner
cannot run your registered handlers then).

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
| Cleanup not working / `[WARN] … left behind (own EXIT trap?)` | Remove the test's own `trap … EXIT`; register the cleanup with `kt_fixture_cleanup_register` |
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
