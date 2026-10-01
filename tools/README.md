# ktests/tools — load tools for timing tests

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
refuses an overlap, stops with no leftovers).

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
