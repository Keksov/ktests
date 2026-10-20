# ktests/tools — the phase gate, load tools for timing tests, the stray-process guard, the suite-job library

## gate.sh — the phase gate

One command instead of a hand-written harness (GATE_PLAN.md): run suites
under one or more bash runtimes, every suite as a hermetic **cell**, one line
per cell, a summary per runtime, one machine line.

```bash
G=ktests/tools/gate.sh
B52=C:/bin/Git/usr/bin/bash.exe B53=C:/bin/msys64/usr/bin/bash.exe
bash $G --bash $B52 --bash $B53 all                          # the phase gate (~28 min, 2026-10)
bash $G --bash $B53 kcl/tstringlist kklass --timeout 900     # some suites, one runtime
KT_GATE_BASHES="$B52;$B53" bash $G kcl/tregex -- -n 1-12    # default runtimes; args to every tests.sh
bash $G --root "$SCRATCH/head" --out "$SCRATCH/g_head" kklass # a tree copy, an OUT of your choice
bash $G --bash $B52 --bash $B53 --changed --compare LAST      # what the diff touches, totals vs the last gate
bash $G --bash $B53 kcl/tstringlist --mode both --cwd both --repeat 5 --rerun-failed 2  # flake hunting
```

**Agents** (the short version: [`../docs/GATE_FOR_AGENTS.md`](../docs/GATE_FOR_AGENTS.md)):
start it with `run_in_background`, watch `tail OUT/progress.txt`
(OUT is in the first line, `gate STAMP root=… out=OUT`; every line goes there too), read the last
line: `__GATE__:VERDICT:cells:pass:fail:flaky:env:timeout:stray:passed:total`
(`fail` = FAIL + CRASH cells; NOTRUN cells are in no field). `--timeout`
bounds each cell — enforced by the segment's watchdog, which the launcher
replaces by a rescue watchdog when it goes silent (and the segment refuses to
start a cell without one); a killed gate (TaskStop, SIGKILL, `taskkill`, a
dead parent) stops its cells by itself. A `timeout N` wrapper around the
whole gate is still a sound outer bound for unattended runs: it adds nothing
the gate needs, it only caps the wall time.

Suites: `all`, ids (`kkore`, `kcl` = kcl/tests, `kcl/tstringlist`) or a
unique last component (`tstringlist`); unknown/ambiguous → rc 2 before
anything runs. Options (all in `gate.sh --help`; `--opt VALUE` or `--opt=VALUE`):

| option | what |
|---|---|
| `--bash PATH` | a runtime (repeatable; one segment each, one after another — DG3). Default `KT_GATE_BASHES="PATH;PATH"`; neither: the bash running gate.sh alone, with a `[WARN] one runtime only` |
| `--mode threaded\|single\|both`, `--cwd neutral\|suite\|both` | the runner mode / the cell's cwd; `both` = a cell for each |
| `--repeat N` | every cell N times (the repeat# is a column, the line shows `SUITE#R`); a runtime's cells run repeat > suite > mode > cwd |
| `--workers N`, `--timeout SEC` | the runner's workers; per-cell bound (default 1800 s → TIMEOUT) |
| `--rerun-failed N` | after a FAIL (not ENV/TIMEOUT/STRAY/CRASH): exactly the failed files (`-n` by their numbers from the summary's `file` lines), same mode/cwd, a fresh sandbox `cells/NNN/rerun-R/` each, up to N times; a passing rerun → **FLAKY** (never PASS), a rerun leaving a process → STRAY, else FAIL. The cell keeps the counts and `[FAIL]` lines of its full run |
| `--changed` | the suites the uncommitted changes touch (`git status --porcelain -uall` in the root and every submodule, plus the files of a submodule commit the root has not recorded yet; a rename's both paths, staged or in the worktree): kkore/ kklass/ ktests/ tests/ kbool.sh .gitmodules → all; a root document a suite tests (the doc map: `README.md` → kkore, whose 015 runs its doctest blocks) → that suite; `kcl/tests/…` → kcl; `kcl/DIR/…` → kcl/DIR; a unit file (`kk.unit`; a deleted one when its HEAD version has `kk.unit`) → kcl too, a deleted script without one → its suite only; the units of DIR (touched by a change outside `DIR/tests/` that is not `*.md`) and, transitively, every unit whose unit file `kk.uses` one → their suites, and every suite whose other scripts (test files, a `bench.sh` its tests run) `kk.uses` one of them. Named suites are added (union). Selection + reasons printed before the first cell. Nothing to run → `[WARN] nothing changed`, **exit 0**, no OUT, no machine line |
| `--compare LAST|DIR|FILE.tsv` | this run's cells.tsv vs another's, over the keys (bash, mode, cwd, suite) THIS run plans: the changed total/passed, keys added / not run here / not run in the base (`-` counts, UNSTARTED…), or `totals unchanged`; the per-bash sums over those keys; a base key this run does not plan is no change (`N base key(s) not in this run`, `base_only` in summary.json). DIR/FILE unreadable or garbled (field count, counts > 18 digits) → rc 2 before any run. LAST = the newest FINISHED run under the default root (below: ONE root for a 5.2 and a 5.3 launcher, so either finds the other's runs), by start stamp, a tie by the dir name; an unreadable candidate is skipped (a note); none → `[WARN] --compare LAST: no base`, the run goes on without a compare. Informational (the exit code is the run's) |
| `--parallel` | all runtimes at the same time, lines relayed as they come — **cross-runtime fork contention** (DG3, the 2026-09 timing flakes): for orientation, never a phase gate |
| `--fail-fast` | after the first FAIL/TIMEOUT/STRAY/CRASH every cell not started yet (all runtimes) is SKIPPED; exit 1 |
| `--warm` | one `.ckk` dir per segment (`OUT/seg-N.ckk`) shared by its cells; default a cold one per cell (DG4) |
| `--root DIR`, `--out DIR` | the tree; the run dir (new, or empty — dot names count; claimed by an exclusive marker). It must be private (the segments source `OUT/seg-N.spec`): inside the tree under test a `[WARN]` |
| `--keep`, `--nohup`, `-- ARGS` | keep passed cells' sandboxes; no parent watch; args for every `tests.sh` |

Ctrl-Z is not supported (a `[WARN]`, ignored). The caller's exported
`SHELLOPTS`, `BASHOPTS`, `CDPATH`, `GLOBIGNORE` change nothing (the launcher
resets them).

| verdict (worst wins) | meaning | exit |
|---|---|---|
| STRAY | the cell left a process (found after the cell or at the segment's end, stopped) | 1 |
| TIMEOUT | stopped at `--timeout` (its group: TERM, 15 s, KILL) | 1 |
| NOTRUN | the suite has no test file (summary `error no-test-files`): not a failure, a column of its own | 0 (1 if every cell is NOTRUN: `[WARN] nothing ran`) |
| CRASH | no summary from the runner (`KT_SUMMARY_FILE`), or `error REASON` in it | 1 |
| FAIL | the suite failed; the first 5 lines of its `[FAIL]` messages under the line | 1 |
| ENV | the machine, not the test — re-run once in a fresh sandbox, the 2nd run decides (both kept): a FAIL whose failed files ALL died of a fork failure — the summary's `env NAME` lines (the runner saw it) or a RAW fork-failure line in the log belonging to that file (it precedes the file's next tagged message; never a test's own `[FAIL]`/`[PASS]`/`[WARN]` message) — a real failure next to one stays FAIL, with a note `+ fork failure in …`; a summary without a file list: any such line; a CRASH with such a raw line or without a summary at rc 125–127 | 3 if left |
| FLAKY | `--rerun-failed`: a FAIL whose failed files passed on a rerun (which files, at which attempt: `flaky`, `rerun_pass`) | 4 (no hard failure, no ENV) |
| PASS | `warn=N` is a column (the log's `[WARN]` lines), not a verdict | 0 |
| INTERRUPTED | the gate was stopped while the cell ran | 128+N |
| SKIPPED | `--fail-fast`: never started after a hard failure | (1: there was one) |
| UNSTARTED | (cells.tsv / summary.json only) planned, never started and no result: the run was interrupted, or its segment died (`N not started` in the runtime's summary line) | the run's |

The gate's own verdict (`gate VERDICT` line, `summary.json` `verdict`, the
machine line's first field) is PASS, FAIL, ENV, FLAKY or INTERRUPTED.
NOTRUN, SKIPPED, INTERRUPTED and UNSTARTED cells are in no field of the
machine line, so pass + fail + … can be less than cells.

Exit 0 = every cell PASS (NOTRUN allowed; also `--changed` with nothing to
run), 1 = a hard failure (FAIL/TIMEOUT/STRAY/CRASH, also with `--fail-fast`)
or every cell NOTRUN (`[WARN] nothing ran`), 2 = usage (before anything runs,
no OUT), 3 = ENV left after the retry (re-run, do not fix), 4 =
FLAKY (and nothing worse), 128+N = interrupted (TERM 143, INT 130, HUP 129; a lost parent 143).
A segment killed from outside, or one whose watchdog could not be started
again (`no-watchdog`) → [WARN], exit 1.

**Processes** (two cygwin runtimes cannot signal or see each other): the
*launcher* (as started) writes a spec per runtime (`OUT/seg-N.spec`, mixed
`C:/…` paths, the caller's locale/TZ/COMSPEC…), starts one *segment* per
runtime (`env --default-signal=INT,QUIT -i`: INT/QUIT stay trappable in every
cell; a session of its own; no inherited fd), never signals it —
`OUT/seg-N.result` is its verdict — relays its lines, rewrites `OUT/hb` every
5 s, watches its own parent (parent gone = TERM; `--nohup` or `nohup gate.sh`
turns that off for a run detached on purpose) and the watchdog's
`OUT/seg-N.wdhb` (silent 30 s → a rescue watchdog). The *segment* (`gate.sh
--segment`) runs its cells through `suitejob.sh` (`kt_suitejob_run`: a
job-control group, `wait` — no fork while a cell runs), checks before each
cell that a watchdog lives, and the stray check after each cell and at its
end; its exec'd *watchdog* (`gate.sh --watchdog`, builtins, 1 s tick) sends
USR1 — only while a cell runs, repeated until acknowledged — on `OUT/STOP`
(launcher TERM/INT/HUP), on a stale heartbeat (launcher killed: 30 ticks) and
at the running cell's deadline; when the segment itself is killed (a tree
kill) the watchdog stops the cells and writes `segment-killed`. A *cell* runs
with its own HOME, TMPDIR/TMP/TEMP, USERPROFILE, ProgramData, `__KK_CFG_ETC`,
`KKLASS_CKK_DIR`, cwd (`OUT/cells/NNN/…`), stdin `/dev/null`, fds 0–2,
`KT_SUMMARY_FILE`, and nothing else of the caller's environment
(deny-by-default; locale etc. from the spec).

**Outputs** in OUT (default `PRIVATE_TEMP/kt-gate/STAMP-PID` — PRIVATE_TEMP = TMPDIR when set, else
`%LOCALAPPDATA%/Temp` (else the per-user folder from `cygpath -F 28`), in the C:/ form, the same
for both runtimes; never MSYS2's `/tmp`, which every user may write — made by an
atomic mkdir; only under that default root are old runs rotated: the newest
10 gate-marked dirs stay, an older one is removed only when gate made it, its
owner is dead — the other runtime's: no fresh `OUT/hb` (< 2 min) — and it is complete or older than 2 h — never a neighbour of an
explicit `--out`): `.kt_gate` (the claim marker), `progress.txt`, `FINISHED` (the machine line) or
`INTERRUPTED` (who stopped it), `argv.txt`, **`cells.tsv`**, **`summary.json`**,
`compare.txt`, `FAILFAST`, `cells/NNN/{result,log.txt,summary,fails.txt,
strays.txt}` (+ `log.1.txt` etc. of an ENV first attempt, `rerun-R/` of a
rerun; `result` = KEY=VALUE, the source of cells.tsv), `seg-N.{spec,log,
result}` (+ `seg-N.ckk` with `--warm`).

**Reports** (written by the launcher at the end — also of an interrupted run,
with what finished — before the verdict line):

- `cells.tsv` — header + one row per planned cell (never started: verdict
  UNSTARTED): `idx bash_version bash_path mode cwd suite repeat verdict rc
  total passed failed warn fail_lines strays attempts duration_ms log reruns
  rerun_pass flaky reason`; tab-separated, no value holds a tab/newline/CR
  (each becomes a space), an empty value is `-`, `flaky` joins file names
  with `/`. `--compare` reads it (by column name).
- `summary.json` — `{gate:{started, finished, root, out, argv, repos:{NAME:
  {sha, dirty}}, options}, changed?, bashes:[{version, path, runtime}],
  totals:{VERSION:{cells, PASS, FAIL, FLAKY, ENV, TIMEOUT, STRAY, CRASH,
  NOTRUN, INTERRUPTED, SKIPPED, UNSTARTED, passed_tests, total_tests,
  duration_ms}}, cells:[{…the tsv columns (numbers as numbers, flaky an
  array), attempt1, ckk, fails: the first 5 [FAIL] lines}], compare?,
  machine, exit, verdict}`. Never read back by gate.

**Into a ledger**: take `totals` and `verdict` (and `gate.repos` for the
SHAs) from `summary.json` instead of retyping counts — e.g.
`node -e 'const j=require(process.argv[1]); console.log(JSON.stringify({verdict:j.verdict, out:j.gate.out, repos:j.gate.repos, totals:j.totals, compare:j.compare}))' "$(cygpath -m OUT/summary.json)"`,
and paste the result as the phase's `gate` value (`compare` is left out when
the run had no `--compare`).

Tests: `tests/050_GateCli.sh`, `051_GateVerdicts.sh` (every fixture of
`tests/gate_fixtures/`, hermeticity), `052_GateSignals.sh` (TERM, INT,
SIGKILL, `taskkill /F`, parent kill, `taskkill /T` of launcher and segment,
the watchdog killed, both directions, no fork in the segment),
`053_GateReports.sh` (cells.tsv, summary.json via node, `--compare`, an
interrupted run's reports, sanitising), `054_GateSelection.sh` (`--changed`
on a scratch git fixture, `--rerun-failed`/FLAKY, the matrix options,
`--fail-fast`, `--warm`, `--parallel`).

## Load tools for timing tests (forkstorm.sh, timing_check.sh)

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
* **Self** — the caller is never listed: `strays.sh` itself, its ancestors,
  its own descendants, and the caller's un-started fork for the other side of
  a pipe (`strays.sh list --all | while read …`, `| { cat; }`): a child of an
  ancestor that still carries that ancestor's command line AND whose stdin is
  the pipe `strays.sh` writes into. The caller's own background jobs
  (`{ …; } &`, `( … ) &`) carry the same command line but are listed
  (`ORPHAN=no`) — a leak made in the same call shows; an orphan with the
  caller's command line is listed too (its parent is gone).
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
  never hit. The KILL is re-sent until the targets are gone or
  `KT_STRAYS_KILL_MS` (default 10000) have passed — by the clock, not a round
  count: under full-sweep load SIGKILL *delivery* lags seconds (gate G1/G2:
  20 KILLs over 2 s, still alive → a false "LEFT"); 045 pins it through a
  seam (a wrapped `_kt_strays_signal` holds the KILLs for a while — no
  OS-level suspend: a killed test must never leave a suspended process).
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
`tests/045_StrayGuard.sh` pins all of it. The master's suite-job machinery (discovery,
the job per suite, signals, the stray check) is `suitejob.sh` (below).

## suitejob.sh

The suite-job machinery of the master sweep, a library shared by
`tests/tests.sh` and (from gate G2) `tools/gate.sh` (GATE_PLAN DG5, §4.6).
Plain bash, no kbool; it sources `strays.sh` beside it. Source it, then:

```bash
kt_suitejob_init "$START" "${KT_STRAYS_MATCH:-}"   # stray window (EPOCHREALTIME) + optional narrowing
kt_suitejob_discover "$ROOT"                      # KT_SUITEJOB_SUITES: every DIR/tests/tests.sh, master order
trap kt_suitejob_tstp TSTP                         # Ctrl-Z suspends the job group with the caller
trap kt_suitejob_break USR1                        # (G2 segment) a signal that ends the wait
kt_suitejob_run "$LABEL" bash "$suite" "$@"       # rc 0: ended, status in KT_SUITEJOB_RC; rc 1: broken
kt_suitejob_signal 143                             # stop the running job: TERM+CONT group, 15 s grace, KILL
kt_suitejob_strays "$LABEL"                        # rc 1: strays reported with their label, stopped, recorded
```

* **Discovery** — the master's walk: depth first, at each level the dir's own
  `tests/tests.sh` (not the root's), then its non-hidden subdirectories in
  glob order.
* **The job** — a background job under `set -m`: a process group of its own
  (`KT_SUITEJOB_PID` = its pgid), default SIGINT (a `&` job without job
  control would start with INT ignored, untrappable), TTOU/TTIN ignored, the
  caller's stdin. The caller `wait`s, so a trapped signal is handled at once.
  A trap may run the stop path and exit (the master's TERM/INT/HUP) or call
  `kt_suitejob_break`: `kt_suitejob_run` returns 1 with the job still running
  (`KT_SUITEJOB_PID` set) and the caller calls `kt_suitejob_signal`.
* **Stop** — TERM + CONT to the group once, a fork-free grace while the
  leader lives (`KT_SUITEJOB_GRACE` tenths, default 150), KILL to the group,
  reap. Traps are the caller's (the master ignores TERM/INT/HUP first).
* **Strays** — `kt_strays_scan --session self --since START [--match TEXT]`;
  a hit is looked at again 1 s later, then each process is listed with the
  label that was running when it started (`KT_SUITEJOB_BEFORE` before the
  first job), stopped, and recorded (`KT_SUITEJOB_STRAY_ROWS`,
  `KT_SUITEJOB_STRAY_LABELS`) for the caller's summary.

The header of `suitejob.sh` lists every global. `tests/049_SuiteJob.sh` pins
the library (discovery order = the old walk, the job's group/signals/stdin,
the USR1 break and stop, the narrowed stray check); `045_StrayGuard.sh` pins
the master on top of it.

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

`--bash B` runs the script again under B (B's dir first on PATH) as a child
it waits for, started with `env -i` in a process group of its own. The
environment does not cross cygwin runtimes, so the child gets what it needs
from a spec file in a private dir (`mktemp -d` under TMPDIR, else
`%LOCALAPPDATA%/Temp` (else `cygpath -F 28`/Temp) — MSYS2's `/tmp` is shared by all users —, never the
tree; an `owner` marker in it, and the next run sweeps the dirs of a dead
owner: this runtime by `kill -0`, the other one after 24 h), named by a hidden first argument `--reexec SPEC` — also the guard
against a second re-run, never an environment variable. The child removes
the spec after reading it; the parent removes the dir when the child is done
(also after a TERM/INT, which it passes on as a real TERM of the child's
runtime, and after a B that is no bash: rc 2). The spec carries the parsed
options (absolute /posix paths of `--log`, `--keep-dir`, SUITE_DIR as the
same folder in B's spelling) and an **allowlist** of the caller's exported
variables: `KT_*`, `KBOOL_*`, `KKLASS_*`, `VERBOSE_KKLASS*`, `LANG`,
`LANGUAGE`, `LC_*`, `TZ`, `TMPDIR`, `HOME`, the Windows basics (`SYSTEMROOT
WINDIR COMSPEC SYSTEMDRIVE PATHEXT TERM USERNAME NUMBER_OF_PROCESSORS
PROCESSOR_ARCHITECTURE OS COMPUTERNAME`) and each `--pass-env NAME`
(repeatable) — nothing else, no exported function; path values arrive as the
same folder. The header then says `(re-executed from bash V)`.
`tests/055_TimingCheckReexec.sh` pins it, same runtime and across.
