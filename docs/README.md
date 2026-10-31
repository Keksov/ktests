# KK Testing Framework

> Part of [kbool](https://github.com/Keksov/kbool): installation, quick start and the other components are there.

The bash test framework every kbool suite uses: assertion helpers, fixtures
with automatic cleanup, a runner that runs a suite's test files (threaded or
sequential) and judges each one, and the phase gate on top of it.

## Overview

```
ktests/
├── ktest.sh                 # Main entry point: a test file sources this
├── ktest_core.sh            # Logging, counters, kt_test_start / kt_test_pass / kt_test_fail
├── ktest_assertions.sh      # The kt_assert_* helpers
├── ktest_fixtures.sh        # Temp files and directories, cleanup handlers
├── ktest_runner.sh          # Test discovery and execution (threaded / single)
├── ktest_source.sh          # Sources ktest.sh reliably, also in a bash -c context
├── ktest_proc.sh            # Process listing (/proc or ps) for group stops and strays
├── ktest_env_signatures.sh  # cygwin fork-failure signatures (runner + tools)
├── ktests.sh                # The suite runner: ktests.sh SCRIPT_DIR [SUITE_NAME] [OPTIONS]
│
├── templates/
│   ├── common.sh.template   # A suite's shared setup: copy to tests/common.sh
│   └── test-example.sh      # An example test file
│
├── tools/
│   ├── README.md            # gate.sh, strays.sh, forkstorm.sh, timing_check.sh
│   ├── gate.sh              # The phase gate: suites x bash runtimes, one verdict
│   ├── strays.sh            # Finds and stops processes a run left behind
│   ├── suitejob.sh          # Runs suites as jobs (shared by the master sweep and gate.sh)
│   ├── forkstorm.sh         # A fork storm: the load that makes timing checks flaky
│   └── timing_check.sh      # Runs test files repeatedly under a fork storm, reports the pass rate
│
├── tests/                   # ktests' own suite (NNN_*.sh, gate_fixtures/)
│
└── docs/
    ├── README.md            # This file
    ├── START_HERE.md        # Quick start for new users
    ├── GATE_FOR_AGENTS.md   # How an agent runs the gate
    └── dev/                 # Plans and ledgers of the ktests work
```

## Quick Start

A suite is a `tests/` folder with a runner `tests.sh` and test files named
`NNN_Name.sh`. The template expects `ktests/` next to the module folder
(`kbool/kkore/tests` → `kbool/ktests`).

### 1. Copy the template

```bash
cp ktests/templates/common.sh.template mymod/tests/common.sh
# then edit mymod/tests/common.sh:
MODULE_NAME="mymod"
```

### 2. Add the suite runner, `mymod/tests/tests.sh`

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../ktests/ktests.sh" "$SCRIPT_DIR" "mymod" "$@"
```

### 3. Write a test file, `mymod/tests/001_First.sh`

An assertion only answers true or false; each test is opened with
`kt_test_start` and closed with `kt_test_pass` or `kt_test_fail`:

```bash
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

kt_test_start "two values are equal"
if kt_assert_equals "hello" "hello" "values match"; then
    kt_test_pass "two values are equal"
else
    kt_test_fail "two values are equal"
fi

kt_test_start "a fixture file exists"
file="$(kt_fixture_tmpfile data)"
echo "content" > "$file"
if kt_assert_file_exists "$file" "file created"; then
    kt_test_pass "a fixture file exists"
else
    kt_test_fail "a fixture file exists"
fi
```

### 4. Run it

```bash
bash mymod/tests/tests.sh              # the suite: "Total tests: 2  Passed: 2  Failed: 0"
bash mymod/tests/001_First.sh -v info  # one file, every test shown
```

The kbool suites themselves do not use `common.sh`: each test file sources
`ktest.sh` and calls `kt_test_init "Name" "$SCRIPT_DIR" "$@"` itself (see
`kkore/tests/001_*.sh`).

## Features

**Assertions** (`kt_assert_*`, 24 helpers)
- Value comparisons (equals, not_equals, true, false, numeric equals / gt / lt)
- String operations (contains, matches)
- File checks (exists, readable, writable, directories)
- Command execution (success, failure) and command output (contains, matches)
- Array operations (length, contains)

**Resource management**
- A fixture directory per test file and run, removed at exit
- Temp files and directories inside it
- File backup and restore
- Cleanup handler registration

**Execution**
- Threaded by default (8 workers, `-w N` to change), sequential with `-m single`
- Test selection by number (1, 1-5, 1,3,5-7)
- Verbosity control (error, info)
- Every test file judged: a file that stops part-way is FAILED, not green with a lower total

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
# Create temp file
file=$(kt_fixture_tmpfile "data")
echo "content" > "$file"
# removed when the test file exits
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
`<tests>/.tmp/<Name>.<file>.<pid>`. A test's own `trap … EXIT` REPLACES it, so none of
that runs. Register a handler instead (one that first `cd`s out of a directory
it is about to remove). If a fixture dir is still there after a file ran, the
runner removes it and prints
`[WARN] <file>: fixture dir .tmp/<dir> left behind (own EXIT trap?) …`; a
standalone `bash FILE` wipes such a stale dir at its next setup (a dir created
earlier by the same process is kept). The teardown retries a removal that
failed (up to 10 × 0.3 s, fork-free): on Windows a native handle opened
without FILE_SHARE_DELETE — a virus scanner reading a file just written —
makes `rm -rf` fail with "Device or resource busy" while it is held; a dir
that still outlives its shell is the runner's WARN above.

**Concurrent runs** of one file or one suite (two terminals, two agents) are
safe: the fixture dir is per run — `<Name>.<file>.<pid>` (the pid of the test
file's shell), with an owner mark in the SIBLING file `<Name>.<file>.<pid>.owner`
(the runtime: the source of the `/` mount) — the fixture dir itself starts
empty. Setup and the runner's sweep remove only a dir whose owner is gone (dir
and mark together): one of this runtime whose pid is dead (`kill -0`), or —
the other runtime's pids are invisible here — one of the other runtime (or
without a mark) once it is older than a day (`kt_fixture_stale_dir`). Use
`kt_fixture_tmpdir` / `$_KT_TMPDIR`, never a computed `.tmp/<Name>.<file>`.
A hand-made private `.tmp/<file>` (below) has no owner and is not protected.

The fixture base is made **absolute** at setup: a relative script dir (the
`$(dirname "$0")` of a standalone `bash tests/NNN_X.sh`) is joined to the
current directory (`$PWD`, or `pwd` when `$PWD` is unset or not absolute), so
fixture paths mean the same thing from any cwd. `C:/…` and `C:\…` are
absolute; a drive-relative `c:x` is a relative name to MSYS and joined like
one. A test
that needs a directory of its own takes it from `kt_fixture_tmpdir_create NAME`
(inside the fixture dir, removed at teardown) — never a hand-made
`<tests>/.tmp/<file>`: the runner removes such a dir after the file ran and
prints `[WARN] <file>: private dir .tmp/<file> left behind …` (never for a file
named `.sh` / `..sh`, nor through a symlink).

## Running Tests

```bash
# A suite, threaded (default, 8 workers)
bash tests/tests.sh

# Verbose output
bash tests/tests.sh -v info

# Run specific tests
bash tests/tests.sh -n 1-5

# Execution modes
bash tests/tests.sh -m threaded -w 4     # Parallel with 4 workers
bash tests/tests.sh -m single            # Sequential execution

# Combined options
bash tests/tests.sh -n 1-10 -m threaded -w 4 -v info

# Help
bash tests/tests.sh -h

# One file, standalone
bash tests/001_X.sh; echo $?   # 1 when any test in it FAILED
```

A test file run standalone exits **1 when any of its tests failed** (and it
would otherwise have exited 0; a non-zero status of its own is kept) — the
same verdict the runner reaches from the file's counts line. Under the runner
(`KK_OUTPUT_COUNTS` set) the counts line judges and the exit status is not
changed. A test file SOURCED into another shell (`source tests/X.sh`) installs
the same EXIT trap in that shell: when that shell exits, the fixture teardown
runs and its exit status becomes 1 if a test failed.

The two runner modes give a test file slightly different environments: the
threaded mode's workers get the runner helpers by `export -f`, so every test
file and every child it starts sees them as `BASH_FUNC_*` environment
variables (`run_test`, `kt_runner_*`, `kt_fixture_stale_dir`,
`kt_fixture_owner_mark`, …); the single mode exports none. A test must not
depend on either.

## Phase gate

Three ways to run tests, for three jobs:

| | runs | for |
|---|---|---|
| a suite's `tests.sh` (this runner, `ktests.sh`) | one suite, in your shell, your environment | writing and debugging tests |
| `bash tests/tests.sh` (the master sweep, kbool root) | every suite, one bash | the whole tree on the bash you are in |
| `ktests/tools/gate.sh` (the phase gate) | chosen suites × one or more bash runtimes, every suite in a hermetic sandbox, bounded | checking a change before a commit: one verdict, `cells.tsv` + `summary.json`, totals compared with the last gate |

```bash
# from the kbool root: one suite on both runtimes, one line per (bash, suite)
bash ktests/tools/gate.sh --bash C:/bin/Git/usr/bin/bash.exe --bash C:/bin/msys64/usr/bin/bash.exe kcl/tstopwatch
```

The last line is the machine line
(`__GATE__:PASS:2:2:0:0:0:0:0:122:122`); exit 0 = every cell PASS. Options,
verdicts, exit codes and outputs: [`../tools/README.md`](../tools/README.md#gatesh--the-phase-gate);
how an agent runs it: [`GATE_FOR_AGENTS.md`](GATE_FOR_AGENTS.md).

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

A killed run cleans up after itself. `ktests.sh` keeps its run folder
`${TMPDIR:-/tmp}/kt_iso.<pid>` (the files' HOMEs and the threaded runner's
results dir `results.XXXXXX`) and removes it from its EXIT trap; TERM, INT and
HUP exit with 128+N so that trap runs (bash 5.2 runs no EXIT trap on a signal
by itself). The run is a background job in its own process group that
`ktests.sh` waits on, and the threaded runner's workers are one more such
group, so a signal to the runner's pid ALONE stops it at once (a trap would
wait for a foreground child) and the trap stops the group: the current test
file, xargs, the workers and their test files. The threaded runner restores
the caller's traps when it returns. A group ignores SIGTTOU/SIGTTIN (a
background group writing to a `stty tostop` terminal would stop). Stopping a
group (`kt_runner_group_stop`, `kt_runner_group_end`): take a `/proc` snapshot
of its members and of their descendants OUTSIDE it (a test file's `timeout N
cmd` — GNU timeout makes its own process group — or a `set -m` subgroup), send
TERM and CONT ONCE to the group (a second TERM would cut a test's cleanup
short), wait — without forking — until its members are gone, then TERM+CONT
ONCE the descendants still alive (not earlier: the run's shell stops its
worker group itself, and a TERM from both cut the threaded test files'
cleanups short), and after a grace KILL what is left (3 s for the threaded
workers; 5 s for `ktests.sh`'s own group, so the run's shell is not KILLed in the middle of
its own stop): a member that ignores TERM, or one whose TERM was lost — on the
Git (cygwin) runtime a signal sent while a process is still exec'ing (e.g. a
`sleep` forked moments before) is lost for it, and for tens of ms the group
looks empty to `kill -0 -- -PGID` (the 042/044 sweep flake). So the members
are read from `/proc/<pid>/pgid` too and KILLed by pid, and the group counts
as gone only when every view is empty twice, 0.1 s apart. The leader is reaped
only once it is gone (a cygwin process blocked in a FIFO open ignores even
KILL). Each group also has a watchdog on a FIFO whose only writer is the
runner (its read end is opened by the group's shell before the watchdog
starts, so it never blocks in open): a SIGKILLed runner runs no trap, the
watchdog sees EOF, ignores TERM from then on and ends its group the same way;
it ignores SIGTSTP, so a paused (Ctrl-Z) run that is then SIGKILLed is ended
too. Not covered: a process a dying member forks after the snapshot into a
group of its own (it is reparented at once) — the master sweep's stray check
is the net for that. Ctrl-Z (SIGTSTP) pauses the
whole run — the runner passes it to its group and stops itself; `fg` (SIGCONT)
continues the group (and CONTs by pid any member `/proc` still shows stopped:
a group CONT can be lost on the Git runtime under load too). A SIGKILLed run leaves its
`kt_iso.<pid>` — the next run's dead-pid sweep removes it; without a run folder
(the runner functions called directly) the results dir is
`kt_iso.<pid>.results.XXXXXX`, swept the same way. The sweep leaves the folder
of another pid namespace alone until it is a day old (an owner marker
`.kt_owner` = the source of the `/` mount: on MSYS two runtimes sharing a
TMPDIR cannot see each other's pids, and a live run of the other one would be
swept). A file of a threaded run
whose result file is missing (its worker died, its results dir vanished) is
counted `1:0:1` and listed as FAILED with `no result file`.

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
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"

kt_test_init "Example" "$SCRIPT_DIR" "$@"
kt_test_section "My Tests"

# Test 1: Values
kt_test_start "Check values"
if kt_assert_equals "5" "5" "Numbers match"; then
    kt_test_pass "Check values"
else
    kt_test_fail "Check values"
fi

# Test 2: Files
kt_test_start "Check file"
file="$(kt_fixture_tmpfile "test_data")"
echo "data" > "$file"
if kt_assert_file_exists "$file" "File created"; then
    kt_test_pass "Check file"
else
    kt_test_fail "Check file"
fi

# Test 3: Commands
kt_test_start "Check command"
if kt_assert_success "ls /tmp" "Can list directory"; then
    kt_test_pass "Check command"
else
    kt_test_fail "Check command"
fi

# The fixture directory is removed at exit: no trap needed
```

The assertions print nothing when they hold and an `[ASSERTION FAILED]` line
when they do not; their exit status decides between `kt_test_pass` and
`kt_test_fail`. A test that is started and never closed makes the file
FAILED (`test aborted mid-block`).

## Documentation

- **[START_HERE.md](START_HERE.md)** - New user entry point
- **[GATE_FOR_AGENTS.md](GATE_FOR_AGENTS.md)** - The gate: one command, one verdict
- **[../tools/README.md](../tools/README.md)** - `gate.sh`, `strays.sh` and the other tools
- **[../CONTRIBUTING.md](../CONTRIBUTING.md)** - How to contribute to ktests

## Command Reference

### Test Tracking
```bash
kt_test_start "description"   # Mark test start
kt_test_pass "description"    # Mark passed
kt_test_fail "description"    # Mark failed
kt_test_log "message"         # Info logging
kt_test_section "title"       # Section header
```

The older names `test_start`, `test_pass`, `test_fail`, `test_info` (=
`kt_test_log`), `test_section` and `parse_args` remain as aliases.

### Fixtures
```bash
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

Environment of the runner (`ktests.sh`):

```bash
KT_SUMMARY_FILE=PATH    # write a machine summary of the run to PATH (for tools: ktests/tools/gate.sh)
```

`KT_SUMMARY_FILE` is read once at the start and unset before anything else
runs — no test file, worker or nested `ktests.sh` sees it. At exit the file is
written atomically (`PATH.tmp.<pid>` + `mv`; PATH's directory must exist; a
relative PATH is taken from the caller's cwd). Line 1 is
`TOTAL PASSED FAILED RC` (RC = the runner's exit status), then one
`file NNN_Name.sh` line per failed test file, as the results block lists
them:

```
4 2 2 1
file 001_a.sh
file 003_c.sh
env 003_c.sh
```

`env NAME` lines (after the `file` lines) name the failed files that died of
a cygwin fork failure: the runner's retry rule (no END marker, no counts
line, a capture matching `KT_ENV_FORK_FAILURE_RE`, re-run up to 3 times) gave
up on them. A file that ran to its end is never `env`, whatever its `[FAIL]`
messages say — the runner decides what is ENV, not a grep of the output
(`tools/gate.sh` turns such a run into its ENV verdict).

A run that did not reach its normal end writes `0 0 0 RC` and one
`error REASON` line: `usage` (no SCRIPT_DIR, a bad option, `-h`),
`no-test-files`, `interrupted` (TERM/INT/HUP; RC 128+N), `no-results` (the
run's shell was killed from outside), `exit` (any other exit). So a missing
file means the runner itself died (SIGKILL, a crash). Unset or empty: nothing
is written and nothing else changes. `tests/048_SummaryFile.sh` pins it.

## Variables

```bash
TESTS_TOTAL         # Total tests run
TESTS_PASSED        # Tests passed
TESTS_FAILED        # Tests failed
VERBOSITY           # "info" or "error"
MODE                # "single" or "threaded"
WORKERS             # Thread count (default 8)
_KT_TMPDIR          # The test file's fixture directory (also: kt_fixture_tmpdir)
KT_TIMEOUT          # timeout(1) by NAME: timeout, else gtimeout (macOS brew), else "" -> guard with kt_need_timeout, SKIP: $KT_TIMEOUT_WHY (ktest.sh header)
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Framework not found | Verify KTESTS_DIR path in common.sh |
| Tests not discovered | Files must match `NNN_*.sh` pattern |
| Cleanup not working / `[WARN] … left behind (own EXIT trap?)` | Remove the test's own `trap … EXIT`; register the cleanup with `kt_fixture_cleanup_register` |
| `[WARN] SUITE: N process(es) of the run group … left after the run` | A test file started a background process and did not end it; the runner stopped it — kill (and `wait`) your own children before the file ends |
| `[WARN] N stray process(es) found after …` (master sweep) | A suite left a process running whose parent is gone (a test file's background job, marker or not); it was stopped and the suite FAILS. Leftovers of a killed run: `bash ktests/tools/strays.sh list` / `stop` (unfiltered: orphans older than 120 min; `--older-than 0` for all), under each bash (`tools/README.md`) |

## File Naming Convention

Test files must follow this pattern:
```
001_BasicTests.sh        good
002_AdvancedTests.sh     good
001test.sh               bad (missing underscore)
BasicTests.sh            bad (no number prefix)
test_001.sh              bad (number at end)
```

## Getting Help

1. **Quick overview**: See [START_HERE.md](START_HERE.md)
2. **The gate**: See [GATE_FOR_AGENTS.md](GATE_FOR_AGENTS.md) and [../tools/README.md](../tools/README.md)
