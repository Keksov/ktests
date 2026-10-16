# ktests/tools — load tools for timing tests, and the stray-process guard

A timing assertion is only as stable as the slowest thing inside its timed
window. On MSYS/cygwin that is a **fork**: a bash forks in ~15 ms when the
machine is idle, but 2–9 % of forks take ~280 ms, and with 8 siblings forking
at the same time — which is exactly what the threaded ktests runner does —
p90 is ~290 ms on bash 5.2.37 and can reach seconds on 5.3.9. CPU load alone
does not reproduce this; concurrent forking does. These two scripts give that
load on demand.

**Rule for timing tests** (kcl/README.md §1.8 applied to tests): no fork in a
timed window — read the clock into a variable (`t=$EPOCHREALTIME`, split on
`[.,]`, or `TStopwatch.getTimeStamp` called directly), call the member under
test directly (it leaves `RESULT`), never through `$( )` — and compare the
best (or the median) of at least 5 interleaved samples, never one. A fork that
IS the workload (a wrapper around an external tool, a producer's process
substitution) belongs on both sides of a ratio and needs the min/median.

## forkstorm.sh

```bash
bash ktests/tools/forkstorm.sh self-check 8   # idle vs storm fork latency, then prove the stop is clean
bash ktests/tools/forkstorm.sh start 8        # 8 workers forking in a loop; returns at once
bash ktests/tools/forkstorm.sh status
bash ktests/tools/forkstorm.sh stop           # TERM, KILL after 5 s, sweep; nothing left behind
```

As a library: `source ktests/tools/forkstorm.sh`, then `kt_storm_start N`,
`kt_storm_stop`, `kt_storm_alive`, `kt_storm_scan [TAG]`. A second storm is
refused while any storm worker is alive (`KT_STORM_ALLOW_OVERLAP=1` overrides).
Every worker's `$0` is `forkstorm-worker:<tag>`, which is how the leak checks
find it — and every `$( )` child it forks — in `/proc`.

Run it with the bash the tests will run under: Git-for-Windows' bash and
MSYS2's bash are separate runtimes and cannot see or signal each other's
processes. `tests/033_ForkStormHarness.sh` pins the contract (starts, forks,
refuses an overlap, stops with no leftovers, workers die with their owner).

Workers never outlive their OWNER: each one checks after every fork (`kill -0`,
a builtin) that the owner pid is alive and exits otherwise. The owner is the
shell that called `kt_storm_start` (or its 2nd argument); for the CLI `start`
it is the caller (`$PPID`) unless `--owner PID` says otherwise — pass it when
`start` runs under a wrapper such as `$(timeout … forkstorm.sh start …)`, whose
pid dies at once. So a test run killed without its cleanup (SIGKILL, a killed
runner) no longer leaves a storm spinning: on 2026-10-16 eight orphaned workers
forked for ~5 h and kept Defender busy.

## strays.sh

The guard against STRAY processes: on 2026-10-16 a killed test/load run left
8 storm workers and a whole ktests process tree running for ~5 h. `strays.sh`
finds the orphaned processes of the test machinery and stops them.

```bash
bash ktests/tools/strays.sh list                   # orphans: PID PPID AGE ORPHAN COMMAND
bash ktests/tools/strays.sh list --all             # every marker process, with its class
bash ktests/tools/strays.sh stop                   # orphans older than 120 min (see below)
bash ktests/tools/strays.sh stop --older-than 0    # ... of any age (only once you KNOW nothing of yours runs)
bash ktests/tools/strays.sh stop --session self    # orphans of THIS shell's session, any age
```

Options: `--session SID|self` (one session only, and the strict rule),
`--since EPOCH` (started at/after it — a plain time filter), `--match TEXT`
(command line contains TEXT), `--older-than MIN` (default 120), `--width N`.
As a library: `kt_strays_scan [OPTS] [SINCE]` (`KT_STRAYS` + `RESULT`, per
pid `KT_STRAYS_PPID/_AGE/_FLAG/_CMD/_START`), `kt_strays_stop`,
`kt_strays_print`, `kt_strays_group_settle PGID LABEL`.

* **Marker rule** — a command line containing `ktests.sh`, `ktest_runner`,
  `run_test "` (the threaded runner's workers), `forkstorm-worker:`,
  `kt_iso`, `__KT_END_` (the test file's wrapper), the repo root path as a
  whole component (followed by `/`, `\`, a space or the end; any spelling,
  no case), or an argument `tests.sh` / `…/tests.sh` run from inside the
  repo. Only such a process is listed — except in the master sweep (below) —
  and only it, plus the descendants of a listed orphan (`ORPHAN=sub`, e.g.
  the `sleep` of an orphaned test file), is ever signalled.
* **Orphan rule** — on cygwin `ppid 1` alone means nothing: a process started
  by any Windows program (a terminal, an IDE, an agent's tool shell, the other
  runtime's bash) has ppid 1 too, but cygwin makes it the leader of its own
  session (`sid == pid`). A process whose cygwin parent died keeps the session
  it was born in (`sid != pid`). So the topmost process of the chain still in
  `/proc` (its root) is looked up: the tree is **detached** when the root's
  parent is gone — ppid 1, or a pid no longer in `/proc` (a parent killed at
  the Windows level: `taskkill /F`, Task Manager, an agent's stopped
  background task keep the dead ppid) — and `sid != pid`. The caller's own
  tree (same root) is never detached. A live tree is never an orphan.
* **Strict** (`--session`): every marker process of a detached tree is an
  orphan, of any age — the caller names its own session (the master sweep,
  the tests).
* **Unfiltered** (no `--session`): a detached tree is an orphan only when it
  is older than `--older-than` (default 120 min, longer than a full sweep; a
  tree rooted at `timeout D` stays young until D + kill-after + 10 s have
  passed; younger: `ORPHAN=young`) and
  its session leader is gone too (alive: `ORPHAN=live-session`, e.g. a
  terminal's background job). Neither is ever stopped. The age limit is what
  protects an agent's live background run: its tool shell (the session
  leader) exits right after the call, so a bounded `( timeout N … ) &` run is
  detached with a dead leader at once.
* **Stop** — TERM+CONT once to each tree's root (an orphaned ktests.sh then
  stops its own group, test files run their cleanups — a TERM re-sent every
  0.1 s cut those short), a fork-free grace until all are gone (3 s; 5.5 s
  when a root is a ktests.sh), then KILL by pid what survives — including
  children forked meanwhile — with the start time checked, so a reused pid is
  never hit.
* **Runtimes** — Git-bash 5.2 and MSYS2 5.3 are separate cygwin runtimes:
  `strays.sh` sees (and stops) only the processes of the bash that runs it.
  Run it once under each.
* Fork-light: one pass over `/proc` with builtins (`read`, `mapfile`); start
  times from `/proc/PID/stat` starttime + `/proc/uptime`; waits are
  `read -t` on a pty master of their own.

Where it runs by itself: the master sweep `tests/tests.sh` checks after every
suite (and once at the end) with `--session self --since START` — every
detached process of its session started during the sweep, **marker or not**
(a leaked `sleep`, `nc`, `awk`) — lists each with the suite that was running
when it started, stops them, and the suite and the sweep FAIL
(`KT_STRAYS_MATCH=TEXT` narrows the check, for a test that runs a nested
sweep). A TERM/INT/HUP to the sweep stops the running suite (each runs as a
background job in a process group of its own, started under `set -m` so it
keeps its default SIGINT; the suite wrappers `exec` ktests.sh), checks once
more and exits 128+N. `KT_MASTER_SUITES=TEXT` runs only the suites whose path contains TEXT. And `ktests.sh` checks at the normal end of a run that its run
group — and the threaded worker group — is empty (fork-free): a test file's
leftover background process is named in a `[WARN]` line and stopped.
`tests/045_StrayGuard.sh` pins all of it.

## timing_check.sh

```bash
# one or more files, each run alone in the unit's runner (--mode single --verbosity info)
bash ktests/tools/timing_check.sh --storm 0,8,16 --reps 10 --grep 'Assign .*Adds' \
     kcl/tstringlist 013_Assign

# the WHOLE suite threaded (no filter): some flakes need the sibling files
bash ktests/tools/timing_check.sh --storm 8 --reps 10 --grep 'sec1 .*sec20' kcl/tinifile

# the other bash: the script re-executes itself under it (PATH set so the runner's child is the same build)
bash ktests/tools/timing_check.sh --bash C:/bin/msys64/usr/bin/bash.exe --storm 8,16 --reps 5 \
     kcl/dateutils 001_Core

# a suite whose tests.sh fixes the name filter itself: select by number
bash ktests/tools/timing_check.sh --storm 8 --reps 5 ktests/tests n:33
```

One line per run (`storm=8 rep=3 013_Assign TIMING-FAIL <[FAIL] lines> | <--grep lines>`),
then a table per target and storm level: passed/runs and the counts of
**TIMING-FAIL** (every [FAIL] line matches `--timing REGEX`), **FUNC-FAIL**
(anything else) and **ENV** (the run failed and its output shows a cygwin
fork failure — `dofork`, `child_copy`, `0xC000012D` = system commit limit,
`fork: retry` — or the runner could not start, rc 125-127; the signature
regex `KT_ENV_FORK_FAILURE_RE` is defined once, in `ktest_env_signatures.sh`,
and the runner's retry rule uses the same one). ENV is the
machine, not the test: under memory pressure a forked child can even return
garbage from `$( )`. `--keep-dir DIR` keeps the raw output of every run that
did not pass, as evidence. Exit status 0 only when every run passed.
`--log FILE` keeps a copy, `--workers N` sets the runner's workers in suite
mode, `--timeout SEC` bounds one run (default 900). Before the first run of a
level the storm is given time until every worker has forked once. Storm
levels run one after another and never overlap; the storm (and the run in
flight) is stopped on exit, Ctrl-C and TERM included.
