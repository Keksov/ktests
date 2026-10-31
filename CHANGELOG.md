# Changelog — ktests

> Draft (launch L6.7): reviewed before the first release (L8).

ktests is the test framework and runner every kbool suite uses: assertions,
per-case test files, a threaded runner with stray-process and temp-file hygiene,
and `tools/gate.sh`, the one-command phase gate that runs suites across bash
runtimes in hermetic cells and prints one verdict. There is no tag or release yet;
this file groups the whole history by phase, newest first. Start with
[docs/README.md](docs/README.md). Commit hashes in parentheses point at the change for readers
who want the diff.

## Unreleased — first public release (draft)

### Windows runners: no FIFO for the group watchdog (2026-10-31, launch L5.8, L5.9)

* **Git-bash and MSYS2 start a run's worker group as a `coproc`**: its watchdog reads
  the coproc's stdin pipe instead of opening a FIFO. Opening a fresh FIFO read-write
  on cygwin sometimes never returned (the process spun, deaf even to SIGKILL), about
  once per 2,000 to 4,500 group starts on CI runners — the intermittent TIMEOUT and
  STRAY cells of the Windows rows. With the coproc, about 210,000 group starts on
  the runners showed no wedge, and a group start is about three times cheaper.
  Linux, macOS and BSD keep the FIFO. `KT_RUNNER_WATCH=fifo|coproc` forces one
  (test 060).
* A group member that outlives every KILL round of a group stop gets the
  Windows-side kill, so a wedged process no longer becomes an orphan (test 044).

### Launch: CI, macOS and Windows runners, the bash 5.1 floor (2026-10-27 .. 2026-10-30, launch L2.8, L4.5, L5.1-L5.7)

* **Bash 5.1**: the runner's `seen[]` lookup and `group_close` fd write are safe on
  5.1, with a static check (058). `docs/GATE_FOR_AGENTS.md` documents the **bash-floor
  gate** (5.1 in a lab VM) for phases that touch `kbool.sh`, kkore, kklass or ktests.
* **Gate on macOS**: session ids come from `python3 os.getsid` where `ps` has none;
  pipe identity and the working directory come from `lsof -F`; the 052 sampler
  samples only `ps` pid and ppid on the `ps` backend.
* **Gate on Windows runners**: test 057 suspends through .NET calls (a PowerShell
  cmdlet cost 18 to 45 s of module autoload in a CI cell); 051 has a host-suspend
  budget; 042 and 044 print failure detail.
* **Gate hygiene**: cells close inherited file descriptors and start with SIGPIPE at
  its default; a FreeBSD `nap` FIFO sweep; the parent watch outside Windows no longer
  asks `kill -0`, which answers EPERM for a parent of another uid (`su`, `sudo -u`),
  so reparenting decides.
* `timeout(1)` is resolved as `timeout`, then `gtimeout`, else the case SKIPs; test
  054 passes as N/A when `git` is not on PATH; 055 and 056 are free of clock races.
* CI workflow that runs the 13-row kbool matrix with this commit as ktests
  (64227a7); `CONTRIBUTING.md` (1f67fef).

### Launch: portability (2026-10-20 .. 2026-10-22, launch L0-L2)

* **The harness runs on Linux, FreeBSD and busybox**, not only on Windows (05a5b29):
  process facts come from per-platform backends instead of cygwin-only `/proc`
  files, and the watchdog is suspend-aware.
* The stray check attributes processes with a per-backend start tolerance (20 ms on
  Linux).
* The gate stops deaf processes from the Windows side and reports an early TIMEOUT
  for a runner that never starts.
* Comma-locale-safe `EPOCHREALTIME` in the group-stop deadline (test 044).
* MIT `LICENSE`; LF line endings; `#!/usr/bin/env bash` and exec bits; internal plans
  moved to `docs/dev/`.

### The gate: `tools/gate.sh` (2026-10-19 .. 2026-10-20, gate G0-G4)

* **`tools/gate.sh`**: runs suites across bash runtimes in hermetic cells with one
  verdict line (`__GATE__:...`); cross-runtime control was measured first.
* `tools/suitejob.sh` is the shared per-suite job code of the master sweep and the
  gate; `KT_SUMMARY_FILE` carries a machine-readable result.
* Reports: `cells.tsv`, `summary.json`; options `--compare`, `--rerun-failed`,
  `--changed` and a matrix mode.
* An agent guide ([docs/GATE_FOR_AGENTS.md](docs/GATE_FOR_AGENTS.md)) and
  `timing_check` re-exec; a final critic review fixed the gaps it found.

### Rounds 5 and 6: hygiene (2026-10-12 .. 2026-10-19)

* **Config isolation**: the runner isolates the developer's own kbool config per
  test file, and `BASH_ENV` runs in no test file or worker (uses U41, R6).
* A fixture base directory, killed-run cleanup, group stop and a **stray-process
  guard** in the master sweep (round 5 P3).
* The strays tool treats a pipe-fork like its parent, test runs get per-run fixture
  directories, and a standalone run returns a proper exit code (round 6 P4).

### Rounds 1 to 4: runner correctness (2026-10-01 .. 2026-10-05)

* **A fatally aborted test file can no longer report green** (T1, f231248).
* A file-scope `return` has a defined verdict, the threaded runner isolates its
  workers, and cleanup runs from a test's own EXIT trap (round 3).
* A temp leak in test 029, a `parse_args` export leak and unmasked counter resets
  were fixed (round 4).

### Pinned environment and fixtures (2026-09-06 .. 2026-09-26)

* Tests run with `LC_ALL` and `LANG` pinned to `C.UTF-8`, and the framework is safe to
  source under `set -u` (6b2cb77).
* The runner passes the test file path as `$0`; the fixture directory carries the
  test file's name.
* `tools/` fork-storm harness for timing tests, so a timed window can be checked
  under fork pressure (8f37168).

### Hardening and speed (2026-05-24 .. 2026-07-08)

* The framework uses shell built-ins instead of external `grep`, `sed` and `touch`.
* Correctness bugs fixed and the runner hardened; intermittent threaded-mode
  failures fixed by retrying when the counts line is missing.

### The framework (2025-11-22 .. 2025-12-05)

* First version as `kktests`, renamed `ktests` on 2025-12-01: test files with
  assertions, `--option=value` arguments, a failed-file list, quiet output control.
* **Parallel execution by default**: a threaded test runner with test counters that
  never exceed the total.
* The framework can be sourced from anywhere through an environment variable;
  framework variables are declared global; common execution code was extracted.
