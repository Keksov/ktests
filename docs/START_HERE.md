# KK Testing Framework - START HERE

## What is This?

The bash test framework of kbool. It provides:
- Assertion helpers (`kt_assert_*`)
- A fixture directory per test file, with temp files and cleanup handlers, removed at exit
- A suite runner: threaded by default (8 workers, configurable), sequential with `-m single`
- A verdict for every test file: one that stops part-way is FAILED, not green with a lower total
- The phase gate (`tools/gate.sh`): suites x bash runtimes, one verdict

## Setup

1. **Copy the template to your test suite**
   ```bash
   cp ktests/templates/common.sh.template mymod/tests/common.sh
   ```

2. **Set the module name** in `mymod/tests/common.sh`
   ```bash
   MODULE_NAME="mymod"
   ```

3. **Add the suite runner** `mymod/tests/tests.sh` and write test files named
   `NNN_Name.sh`: [README.md, Quick Start](README.md#quick-start) shows both.

The template expects `ktests/` next to the module folder
(`kbool/kkore/tests` → `kbool/ktests`); adjust `KTESTS_DIR` in `common.sh`
otherwise.

## Files Overview

```
ktests/
├── ktest.sh                 # Main entry point: a test file sources this
├── ktest_core.sh            # Logging & counters
├── ktest_assertions.sh      # Assertion helpers
├── ktest_fixtures.sh        # Resource management
├── ktest_runner.sh          # Test execution
├── ktests.sh                # The suite runner
├── ktest_*.sh               # Internal helpers (source, proc, env signatures)
│
├── templates/
│   ├── common.sh.template   # Copy for new suites
│   └── test-example.sh      # An example test file
│
├── tools/                   # gate.sh, strays.sh and their helpers
│
└── docs/
    ├── README.md            # Framework guide
    ├── START_HERE.md        # This file
    └── GATE_FOR_AGENTS.md   # How an agent runs the gate
```

## Choose Your Path

### "I want to learn the framework"
1. Read [README.md](README.md) - Overview
2. Check [../templates/test-example.sh](../templates/test-example.sh)

### "I want to use it in my tests"
1. Copy [../templates/common.sh.template](../templates/common.sh.template) → `tests/common.sh`
2. Update the module name in common.sh
3. Add `tests/tests.sh` and your `NNN_Name.sh` files ([Quick Start](README.md#quick-start))

## Quick Examples

### Simplest Test
```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

kt_test_start "My first test"
if kt_assert_equals "hello" "hello" "Values match"; then
    kt_test_pass "My first test"
else
    kt_test_fail "My first test"
fi
```

### Test with Fixtures
```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

kt_test_start "File operations"
file="$(kt_fixture_tmpfile "data")"
echo "test" > "$file"
if kt_assert_file_exists "$file" "File created"; then
    kt_test_pass "File operations"
else
    kt_test_fail "File operations"
fi
# The fixture directory is removed at exit
```

An assertion only answers true or false; every test is opened with
`kt_test_start` and closed with `kt_test_pass` or `kt_test_fail`.

## Running Tests

```bash
# A suite, threaded (8 workers by default)
bash tests/tests.sh

# Verbose output
bash tests/tests.sh -v info

# Run tests 1-5
bash tests/tests.sh -n 1-5

# Execution modes
bash tests/tests.sh -m threaded -w 4    # Parallel with 4 workers
bash tests/tests.sh -m single           # Sequential

# Custom configuration
bash tests/tests.sh -n 1-10 -m threaded -w 8 -v info

# See help
bash tests/tests.sh -h
```

## Common Assertions

```bash
# Values
kt_assert_equals "expected" "actual" "message"

# Strings
kt_assert_contains "$text" "substr" "message"

# Files
kt_assert_file_exists "/path" "message"

# Commands
kt_assert_success "ls /tmp" "message"

# Arrays
kt_assert_array_contains "arr" "value" "message"
```

## More Information

- **[README.md](README.md)** - Complete framework documentation
- **[GATE_FOR_AGENTS.md](GATE_FOR_AGENTS.md)** - The gate: one command, one verdict
- **[../tools/README.md](../tools/README.md)** - `gate.sh`, `strays.sh` and the other tools
