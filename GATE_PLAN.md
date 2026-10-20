# ktests gate — one command for the phase gate (2026-10-19)

**Status: COMPLETE 2026-10-20 (closing gate: 60/60 PASS, 9059 / 9060, compare vs G3 = ktests +19 only). owner decisions DG1–DG8 taken (quiz 2026-10-19); G0 measured (§8, reviewed 2026-10-20); G1 done 2026-10-20 (reviewed, sweep 8950/8951): `tools/suitejob.sh`, master on it, `KT_SUMMARY_FILE`, tests 048–049. G2 done 2026-10-20 + critic review round 1 (R1–R14), accepted: `gate all` = master sweep per suite on both runtimes (9011/9012); `tools/gate.sh`, `tests/gate_fixtures/`, tests 050–052, strays.sh KILL by the clock, the runner's `env NAME` summary lines (§4.1–4.3 "G2 as built", "Review round 1"). G3 done 2026-10-20 (reviewed; gate all 60/60 PASS 9040/9041): `cells.tsv` + `summary.json`, `--compare`, `--rerun-failed`/FLAKY, `--changed`, `--mode/--cwd both`, `--repeat`, `--fail-fast` (SKIPPED), `--warm`, `--parallel`; fixtures flaky + ckk; tests 053–054 (§3, §4.4, §4.5 "G3 as built"). G4 done 2026-10-20 (uncommitted), awaiting final critic: docs (`docs/GATE_FOR_AGENTS.md`, `docs/README.md` "Phase gate", tools/README gate section re-checked, kbool README), the speed observation measured (§9: no defect — the "33 min" sweep was a pre-kklass-round-5 figure), `timing_check.sh --bash` across runtimes via a spec file (test 055). Final critic: review round 1 R1–R12 done (§9 "G4 review round 1"), awaiting the supervisor's review and closing gate.**
Ledger: [`gate_ledger.json`](gate_ledger.json). Workflow as in the kklass rounds:
one Opus worker per phase → supervisor review against the live tree (critic on
G2 and at the end) → ktests suite + full kbool sweep on bash 5.2.37 AND 5.3.9 →
commit. Builds on ktests round 6 P4 (committed + pushed as ktests e266334,
2026-10-19: `tools/strays.sh` pipe-fork rule, per-run fixture dirs, tests up
to 047).

## 1. Why

Analysis of every shell call in this project's agent transcripts (2026-10-19:
86 transcripts, 10 943 Bash/PowerShell calls, 90 % by worker/critic subagents):

| what the agents did by hand | count |
|---|---|
| one-off harness scripts written (`cat > X.sh <<EOF`) | **632**, 501 distinct names (`run.sh` ×14, `suites.sh`, `sweep.sh`, `r53.sh`, `gate3.sh`, …) |
| runs under the MSYS2 bash (`PATH=/c/bin/msys64/usr/bin:$PATH …/bash.exe`) | 1 530 |
| `timeout N` wrappers | 1 895 |
| greps of human output for `Total tests\|Passed\|Failed\|[FAIL]` | 312 (the machine `__COUNTS__` line: 67) |
| hand-written gate records (`gate.json`, ledger "gate" strings via node/perl) | ~440 JSON edits |
| process checks / kills / sleep-polling around runs | ~980 / 422 |

Every one of those harnesses re-implements the same thing: run suite(s) × bash
5.2/5.3 × (mode, cwd) with a private HOME/TMPDIR, a clean kbool environment, a
time bound, collect the counts and the [FAIL]/[WARN] lines, classify fork
failures as ENV, check for strays, compare the totals with the last sweep and
write the record into the ledger. The variants drifted (one `run.sh` exported
the env from the outer bash and had to be rewritten to set it inside the target
bash; one `sweep.sh` killed `0`). `gate` is that harness, written once, tested.

Not the goal: a CI system, HTML reports, a JSON editor, Linux/macOS discovery
(any `--bash PATH` works; nothing is auto-detected).

## 2. Owner decisions (2026-10-19, all as recommended)

| id | decision |
|---|---|
| DG1 | a standalone tool **`ktests/tools/gate.sh`**, next to `timing_check.sh` / `strays.sh`; `ktests.sh` keeps its interface |
| DG2 | **plain bash, no kbool/kkore/kklass** — a broken unit under test must not break the tool that tests it; fork-light (builtins, `strays.sh`) |
| DG3 | runtimes run **one after another** by default (no cross-runtime fork contention — the source of the 2026-09 timing flakes); `--parallel` is opt-in |
| DG4 | every cell **fully hermetic**: own HOME / TMPDIR / `.ckk` dir / config dirs, kbool env scrubbed, neutral cwd; `--warm` shares one `.ckk` dir per runtime |
| DG5 | the master sweep's suite-job machinery (job-control group, TERM/INT/HUP/TSTP forwarding, the stray check, suite discovery) moves to **`ktests/tools/suitejob.sh`**; `tests/tests.sh` and gate both use it, master behaviour unchanged |
| DG6 | `--changed` = suites of touched units **+ their reverse `kk.uses` dependents**; a change in kkore / kklass / ktests / `kbool.sh` / `tests/` → **all** |
| DG7 | `--rerun-failed N` re-runs only the failed files (off by default) → verdict **FLAKY**, never folded into PASS; ENV (fork failure) is re-run once automatically |
| DG8 | outputs: human lines + **`cells.tsv`** (primary, read back by `--compare`) + **`summary.json`** (the record a ledger gets, replaces hand-written gate.json) |

## 3. Interface

```bash
G=ktests/tools/gate.sh
B52=/usr/bin/bash B53=C:/bin/msys64/usr/bin/bash.exe

bash $G --bash $B52 --bash $B53 all                       # the phase gate: every suite, both bashes
bash $G --bash $B52 --bash $B53 --changed --compare LAST  # what my diff touches, totals vs the last gate
bash $G --bash $B53 kcl/tstringlist kklass --mode both --cwd both --repeat 5
bash $G --root "$SCRATCH/head" --out "$SCRATCH/g_head" kklass    # a tree copy (head vs new)
```

`KT_GATE_BASHES="PATH;PATH"` is the default for `--bash` (the briefs set it
once); with neither, the current `$BASH` alone and a `[WARN] one runtime only`.

**Suites** (positional): `all` (the master's discovery list and order), a
suite id = the suite dir relative to the root without `/tests` (`kklass`,
`kkore`, `ktests`, `kcl` = kcl/tests, `kcl/tstringlist`), or a unique last
component (`tstringlist`). Unknown/ambiguous → usage error, rc 2, before any run.

**Options**: `--bash PATH` (repeatable) · `--mode threaded|single|both` (default
threaded) · `--workers N` · `--cwd neutral|suite|both` (default neutral) ·
`--repeat N` · `--timeout SEC` per cell (default 1800) · `--rerun-failed N` ·
`--changed` · `--compare LAST|DIR|FILE.tsv` · `--parallel` · `--fail-fast` ·
`--warm` · `--root DIR` (default: the tree that holds this ktests) · `--out DIR`
· `--keep` (keep the cell sandboxes of passed cells too) · `-- ARGS…` passed to
every suite's `tests.sh` (e.g. `-- -n 1-12`).

**A cell** = (bash, mode, cwd, suite, repeat#). Order: bash-major (all cells of
runtime 1, then runtime 2 — DG3), suites in discovery order inside.

**Output** (stdout, line-buffered, also appended to `OUT/progress.txt` so a
background run can be watched with `tail`/Monitor):

```
gate 2026-10-19T10:22:03 root=/c/projects/kkbot/kbool out=C:/…/kt-gate/20261019-102203-4711
gate repos: kbool f81abdc+dirty kcl 0bb0ff8 kklass b3709a9 kkore c432048 ktests 3747117+dirty
[ 1/60] 5.2.37 threaded neutral kkore            PASS    669/669            38.1s
[ 2/60] 5.2.37 threaded neutral kklass           PASS    803/803  warn=1   214.0s
[ 7/60] 5.2.37 threaded neutral kcl/tstringlist  FAIL    291/293           44.0s  log=cells/007/log.txt
        [FAIL] 013_Assign: Assign of 20 sections ... (2 lines, first 5 shown)
[ 9/60] 5.2.37 threaded neutral kcl/thttpserver  FLAKY   496/497 (rerun 1 passed: 005_Lifecycle.sh)  71.2s
...
gate 5.2.37: 30 cells  29 PASS  1 FAIL  0 FLAKY  0 ENV  0 TIMEOUT  0 STRAY  tests 8221/8223  33m10s
gate 5.3.9 : 30 cells  30 PASS ...                                           tests 8223/8223  32m45s
gate compare LAST (…/20261018-…): totals unchanged on 5.3.9; 5.2.37 kcl/tstringlist failed 0 → 2
gate FAIL  out=C:/…/kt-gate/20261019-102203-4711
__GATE__:FAIL:60:59:1:0:0:0:0:16444:16446
```

The last line is the one machine line:
`__GATE__:VERDICT:cells:pass:fail:flaky:env:timeout:stray:passed_tests:total_tests`.

**Exit status**: 0 every cell PASS · 1 any FAIL / TIMEOUT / STRAY / CRASH ·
2 usage · 3 no hard failure, ENV left after the retry · 4 no hard failure and no
ENV, some FLAKY · 130/143/129 interrupted (after cleanup).

**G3 as built (2026-10-20)**:

- **Cell order** inside a runtime: repeat > suite (discovery order) > mode >
  cwd, so all variants of a suite are neighbours and repeats interleave (a
  flake hunt sees the whole set before the next round). With `--repeat` > 1
  the line shows `SUITE#R`.
- **FLAKY keeps the full run's counts**: a FLAKY cell's total/passed/failed
  and `[FAIL]` lines are those of its full run (e.g. `FLAKY 3/4 (rerun 1
  passed: 002_flaky.sh)`), not a merged 4/4 — the summary does not give the
  failed files' own counts in the full run, and a merge would invent them;
  the rerun's own counts are in `cells/NNN/rerun-R/summary`. So
  `passed_tests < total_tests` in the machine line of an exit-4 run. A rerun
  that dies of a fork failure counts as a failed rerun (no ENV retry inside
  the reruns); a rerun that leaves a process makes the cell STRAY.
- **SKIPPED** (`--fail-fast`): its own verdict, not a NOTRUN (NOTRUN = "the
  suite has no test file", which never fails a gate); counted apart like
  INTERRUPTED, in no field of the machine line; `OUT/FAILFAST` (the first
  hard failure) is what the segments look at before each cell — in a
  `--parallel` run the other runtime stops there too; serially the launcher
  writes the SKIPPED results of a runtime it no longer starts.
- **`--parallel`** = one launcher loop over all segments (the serial run is
  the same loop over one); every segment keeps its own relay counter,
  watchdog rescue and stop handling.
- **`--warm`**: `OUT/seg-N.ckk`, removed at the segment's end unless `--keep`
  (a full kcl .ckk is large; rotation keeps 10 runs). The cell's `result`
  names its ckk dir (`ckk=`).
- **`--changed` with nothing to run** (nothing changed, or only paths that
  select no suite, and no suite named): `[WARN]`, exit 0, and neither an OUT
  dir nor a `__GATE__` line — a machine line `PASS:0:…` would read as a
  passing gate.

## 4. Design

### 4.1 Processes and runtimes

Git-bash 5.2 and MSYS2 5.3 are separate cygwin runtimes: a process of one
cannot see, signal or `wait`-track the process tree of the other except as a
plain Windows child (exit code yes, signals no — a "kill" is a Windows-level
TerminateProcess, which is exactly the 2026-10-16 orphan case, strays F7).
Hence three levels:

1. **launcher** — `gate.sh` as started. Parses, resolves suites, creates OUT,
   then for each runtime starts one **segment** and waits; writes the reports.
   Holds no test process itself.
2. **segment** — `B gate.sh --segment OUT/seg-N.spec` under the bash of that
   runtime (PATH prefixed with its dir, as `timing_check.sh` does). Runs the
   runtime's cells one by one, each through `suitejob.sh`, and the stray check
   **inside its own runtime** after every cell and at the end
   (`kt_strays_scan --session self --since CELL_START` — the master rule).
3. **cell** — the suite's `tests.sh` in a job-control group of its own,
   started by the segment with the hermetic environment set **inside the
   target bash** (the lesson of the rewritten `run.sh`, 2026-10-16).

Launcher → segment control is **file-based** (works across runtimes, no
fork): `OUT/STOP` (launcher got TERM/INT/HUP: segments stop the running cell,
check strays, write their results, exit) and `OUT/hb` (launcher heartbeat,
rewritten with a builtin redirection every 5 s; the segment's watchdog compares
it with `-nt` against its own reference file, so no `stat` fork). Heartbeat
older than 30 s = the launcher was killed (SIGKILL, `taskkill /F`, an agent's
TaskStop) → the segment behaves as for STOP. Waits are `read -t` on a pty of
its own (`_kt_strays_nap`). **Measured in G0 (§8); the design is fixed as:**

- **Spec file, mixed paths.** The environment does not cross runtimes (only
  9 variables arrive — HOME is the child's passwd default, TMPDIR/USERPROFILE/
  locale/exported functions are lost) and arguments are passed unconverted
  (`/tmp` is a different folder per runtime). The spec path and every path in
  it are `C:/…` (or `/c/…`), never `/tmp`, `/home`, `/usr`; the spec carries
  everything the cell needs from the caller (locale `LANG`/`LC_*`,
  `USERPROFILE`, `COMSPEC`, `TZ`, the PATH tail). The segment is started with
  `env -i` + a whitelist, so a same-runtime segment is as clean as a
  cross-runtime one.
- **Launcher.** Never signals a segment (cross-runtime `kill` is a
  TerminateProcess or nothing, depending on the direction, never a trap) and
  never trusts its rc alone (a segment killed by a signal reads as **rc 0**):
  the segment's `OUT/seg-N.result` is the verdict, rc 0 without it = CRASH.
  It does not block in `wait` on the segment (the stub stays alive while the
  segment's orphans live): a loop of 1 s naps checks the result file and
  `kill -0` on the stub, rewrites `hb` (`printf '%s\n' "$EPOCHREALTIME" > hb`)
  every 5th tick, then a bounded `wait`. It **watches its own parent** each
  tick (`kill -0 $PPID` + `/proc/$PPID/winpid` equal to the value read at
  start): a parent killed at Windows level leaves the launcher alive and
  heartbeating, so parent loss = TERM (STOP path); a deliberately detached run
  opts out (`--nohup`, G2).
- **Segment.** Its main shell `wait`s on the cell job (no tick latency at a
  cell's end). The **watchdog is a separate, exec'd bash**
  (`( exec bash gate.sh --watchdog … ) &`, once per segment, builtins only,
  tick 1 s): STOP seen, or 30 consecutive ticks without `hb -nt mark` (mark
  rewritten whenever hb is fresh; a tick count, not a clock difference) →
  `kill -USR1` to the segment main, whose trap breaks `wait` at once and takes
  the `kt_suitejob_signal` path. Segment main gone (a `taskkill /T` tree kill
  terminates launcher, segment and every *forked* child, but not exec'd
  processes) → the watchdog stops the cell group itself, runs the stray
  check and writes `result` = `segment-killed`.

**G2 as built (2026-10-20)** — the design above, with these changes (052
pins each):

- **A session of its own for a same-runtime segment** (`setsid` where it
  exists — MSYS2 —, else `perl -MPOSIX` `setsid()` — Git for Windows has no
  `setsid`; neither → a `[WARN]`). The stray checks are `--session self`: in
  the caller's session they would see — and stop — the caller's other
  detached processes (the ktests runner's sibling test files when 050–052 run
  a gate, an agent's other jobs). A cross-runtime segment is a session leader
  anyway.
- **PATH crosses by the environment, not the spec**: cygwin converts it on
  the way (a spec copy would name the other runtime's `/usr/bin`); the spec
  carries the rest (locale `LANG`/`LC_*`, `TZ`, `COMSPEC`, `SYSTEMROOT`, …).
- **The per-cell timeout is the watchdog's third request** (no `timeout`
  binary, no fork): the segment writes `run IDX DEADLINE` to `seg-N.cur`;
  the watchdog's requests are a reason in `seg-N.why` (`stop`, `stale`,
  `timeout IDX`) plus USR1, repeated every tick until the segment writes the
  same reason to `seg-N.ack`; a late `timeout` of the previous cell is
  acknowledged and the wait resumed, never taken for a stop.
- **`segment-killed` stops by session, not by pgid**: the watchdog runs
  `kt_strays_stop --session self --since SEGMENT_START` — every detached
  process of the segment's session, TERM once at each tree's root (the
  cell's ktests.sh stops its own group), KILL after the grace — so it needs
  no pgid (the cell's pgid is known only inside `kt_suitejob_run`).
- **Measured in G2: a tree kill of the LAUNCHER does not reach the segment**
  (both directions and same-runtime): the `env -i` / `setsid` exec chain cuts
  the Windows parent link. The segment then stops by the stale heartbeat
  (30 s; 6–7.5 s with the test knob `KT_GATE_HB_TICKS=6`). The watchdog's
  own path is exercised by a tree kill of the SEGMENT (`taskkill /F /T` on
  its Windows pid, written to `seg-N.pid`): stopped in 1.2–3.7 s.
- **Lines**: the segment appends its cell lines to `seg-N.lines`; the
  launcher is the one writer of stdout and `progress.txt` (relayed each 1 s
  tick, only complete lines). A launcher killed without a trap leaves the
  INTERRUPTED mark to the segment (stale heartbeat) or the watchdog.
- **`--nohup`** (G0's open point) is implemented: it turns the parent watch
  off, and so does `nohup gate.sh …` (SIGHUP ignored on entry). Why: the
  watch cannot tell a parent killed at the Windows level from a parent that
  exited normally — both are `kill -0` failures — and a run detached on
  purpose (`nohup gate.sh … &`, `( gate.sh … & )` from a shell that then
  exits) loses its parent by design; without the opt-out it would stop
  itself at once. An agent's `run_in_background` keeps the parent alive and
  needs no flag.
- **A segment killed from outside while the launcher lives** (no result, or
  `segment-killed` without a stop): `[WARN]`, verdict FAIL, exit 1; the
  launcher goes on with the next runtime. A lost parent exits 143 (= TERM).
- **Review round 1 (2026-10-20)**: spec paths are mixed `C:/…` (R11, any
  mount prefix; the segment converts them once, `cygpath -u`); the watchdog
  is no single point of failure (R6): it writes `seg-N.wdpid` and touches
  `seg-N.wdhb` every tick; the segment checks a live watchdog before every
  cell (started again once, else `no-watchdog`, exit 1); the launcher
  watches `wdhb` as the segment watches `hb` and starts a rescue
  `gate.sh --watchdog` for the segment's main (its pid, session and start in
  `seg-N.pid`) when it is silent for HB_TICKS; in its own runtime it also
  signals the segment directly when a stop is unanswered for
  KT_GATE_STOP_WAIT. The watchdog sends USR1 only while a cell runs, a
  timeout only for the cell that still runs (R8), the segment acknowledges
  after `idle` and writes `final` before its last stray check (no nap cut
  short). Ctrl-Z of the launcher is trapped and refused with a `[WARN]`
  (R13): a stopped launcher would stop heartbeating.

### 4.2 Hermetic cell (DG4)

Per cell: `OUT/cells/NNN/{home,tmp,etc,cwd,ckk}` + `log.txt` + `result`. Inside
the target bash before `exec`:

- `HOME`, `TMPDIR`, `USERPROFILE` → the cell's home/tmp (mixed `C:/…` paths
  passed in, converted once with `cygpath -u` in the target runtime — the two
  runtimes map `/tmp` to different Windows folders; G0: `/c/…` is the same in
  both, so a spec that holds `/c/…` needs no `cygpath` at all, and a
  `/tmp`-relative OUT is converted once by the launcher, `cygpath -m`);
  `ProgramData` and
  `__KK_CFG_ETC` → the empty `etc`; `KKLASS_CKK_DIR` → `ckk` (`--warm`: one per
  segment);
- unset every exported variable with a prefix `KBOOL_ KKLASS_ KK_ __KK KT_ _KT_`
  except what gate sets, plus `BASH_ENV ENV VERBOSE_KKLASS CDPATH GLOBIGNORE`,
  and every exported function (`BASH_FUNC_*`) — the `set -a` child lesson (U1a
  R14). Fork-free (G0: 0 forks, 1.5–5 ms): `compgen -e > F` and
  `declare -Fx > F` into a file in the cell's `tmp`, `mapfile < F`, `unset` /
  `unset -f` — never `$( )`. Entries bash cannot import (`BASH_FUNC_a b%%`,
  `BASH_FUNC_c/d%%`) are invisible to builtins and reach every child; the
  segment's `env -i` start (§4.1) is what removes them;
- keep PATH (target bash dir first), `SYSTEMROOT WINDIR COMSPEC`, the locale as
  the caller has it (030 LocaleContract owns locale behaviour, gate does not) —
  taken from the spec, not inherited: across runtimes none of them but PATH,
  SYSTEMROOT and WINDIR arrive;
- cwd = `cwd/` (neutral) or the suite's `tests/` dir (`--cwd suite`); stdin
  `/dev/null`.

**G2 as built**: the environment is **deny-by-default**, a superset of the
prefix scrub: the segment starts from `env -i`, then (fork-free, the recipe
above) unsets every exported variable but `PATH`/`PWD`/`SHLVL` and every
exported function, and exports only the caller's whitelisted variables from
the spec (`LANG LANGUAGE LC_* TZ COMSPEC SYSTEMROOT WINDIR SYSTEMDRIVE
PATHEXT TERM USERNAME NUMBER_OF_PROCESSORS PROCESSOR_ARCHITECTURE OS
COMPUTERNAME`); per cell the gate's own (`HOME TMPDIR TMP TEMP USERPROFILE
ProgramData __KK_CFG_ETC KKLASS_CKK_DIR KT_SUMMARY_FILE`; `OLDPWD` unset).
Both runtimes add `MSYSTEM=MINGW64` to every process started without one —
the runtime's, not the caller's. The ktests runner isolates each test file
further (its own HOME / `__KK_CFG_ETC` under the cell's TMPDIR, USERPROFILE
and ProgramData unset). 051 dumps a probe cell's environment from a polluted
caller (fake HOME/USERPROFILE with `debug = quiet`, KBOOL_HOME, BASH_ENV,
VERBOSITY, CDPATH, exported `kk.uses`) — nothing of it arrives, the locale
does; same counts as from a clean caller, also across runtimes.

*Review round 1:* the segment starts through `env
--default-signal=INT,QUIT` (R1: a `&` start without job control handed the
segment and every cell INT/QUIT as SIG_IGN — untrappable; kcl/thttpserver 006
failed in a cell); the launcher's nap fd (a pty master) is closed for the
segment (R12: the probe sees fds 0–2 and bash's own script fd); the launcher
resets its own shell state at start — `set +aefuC`, `+o pipefail/posix`, the
glob/case `shopt`s off, `CDPATH`/`GLOBIGNORE` unset (R2: an exported CDPATH
redirected `cd -P OUT` into another, non-empty dir that a later rotation
would have removed; failglob from BASHOPTS killed the launcher).

A passed cell's sandbox is removed (log and result kept) unless `--keep`. OUT
default: `${TMPDIR:-/tmp}/kt-gate/<stamp>-<pid>` (*G4 review R13:* PRIVATE_TEMP/kt-gate — TMPDIR, else `%LOCALAPPDATA%/Temp` — one root for both runtimes), made by an atomic `mkdir`
(a taken name gets `-2`, `-3`, …: the other runtime has its own pids); an
explicit `--out` is a new dir (atomic `mkdir` of the leaf) or an existing
EMPTY one (checked on the resolved path, dot names included), claimed by an
exclusive (`noclobber`) marker `kt-gate 2 PID WINPID START CREATED RUNTIME`.
*Review round 1 (R3, F15) narrowed the rotation:* only under the default
root, the last 10 runs are kept; an older dir is removed only when gate made
it (CREATED=1), its owner is dead (the `kt_iso` dead-pid rules, incl. the
other-runtime age guard) AND it is complete (every `seg-N.spec` has its
`seg-N.result`) or older than 2 h — never a neighbour of an explicit `--out`
(head/new tree copies, a `--compare` base). `LAST` = the newest finished run
under the same OUT root. *G3 as built:* under the DEFAULT OUT root
`${TMPDIR:-/tmp}/kt-gate` (since R13 the shared PRIVATE_TEMP/kt-gate; by the marker's start time; it must have
`FINISHED` and `cells.tsv`), also when this run has an explicit `--out` —
an explicit dir's neighbours are the user's, and `--compare DIR` names them.

### 4.3 Results without parsing prose

`ktests.sh` gains `KT_SUMMARY_FILE=PATH`: at the end of a run it writes
`total passed failed rc` and one `file NNN_Name.sh` line per failed file (G1:
an exit before the normal end writes `0 0 0 rc` + `error usage|no-test-files|
interrupted|no-results|exit`, atomically, so a missing file = the runner
died; `docs/README.md`). It reads
the variable once at start and **unsets it before any test file runs** —
ktests' own suite starts nested runners (fixtures) that must not overwrite it
(the C7 nested-marker lesson). The segment additionally counts `[FAIL]` and
`[WARN]` lines and matches `KT_ENV_FORK_FAILURE_RE`
(`ktest_env_signatures.sh`, the one definition) in the cell log.

**Verdict of a cell** (worst wins): STRAY (left a process — a leak is a bug,
master rule) · TIMEOUT (killed at `--timeout`, group stopped) · CRASH (rc ≠ 0
and no summary file: the runner itself broke) · FAIL · ENV (failed and the log
matches the fork signature; re-run once, the second run decides) · FLAKY
(failed, a `--rerun-failed` run of exactly the failed files, `-n` by their
numbers, same mode, passed) · PASS. `warn=N` is a column, not a verdict.

**G2 as built**: CRASH also when the summary file says `error REASON` (the
runner stopped before its end: usage, no-test-files, interrupted, …) and
when it is missing after rc 0 (a wrapper that never ran ktests.sh has no
counts to PASS on). *Review round 1 (R4, R5, R10) replaced the next two
sentences of the first build:* the RUNNER decides what is ENV — ktest_runner
records the failed files its retry rule gave up on (no END marker, no counts,
a capture matching the signature) and `ktests.sh` writes them as `env NAME`
lines into the summary (048 pins it); the gate's own look at the log matches
the signature only in RAW lines, never in a test's `[FAIL]`/`[PASS]`/`[WARN]`
message or its continuation lines (ktests 035 talks about fork failures in
its messages: that is a FAIL), the runner's own "source aborted" line
included. ENV = a FAIL with `env` lines or a raw signature line, or a CRASH
with a raw signature line or without a summary at rc 125–127 (the runner
could not start) — the same retry, the second run decides. A summary
`error no-test-files` is NOTRUN (not a failure; its own column; every cell
NOTRUN = `[WARN] nothing ran`, exit 1; NOTRUN cells are in no field of the
machine line, whose field order stays as documented). The fail lines shown
under a FAIL are its messages with their continuation lines, 5 lines in all;
the runner's list of failed files is told apart by the summary's `file`
names (spaces allowed). A cell the
gate itself stopped (STOP, stale heartbeat, segment killed) is INTERRUPTED,
counted apart, never a suite verdict. The ENV retry runs in a fresh sandbox;
attempt 1 stays as `log.1.txt`, `summary.1`, `fails.1.txt` and the result's
`attempt1=` line. A stray found only by the segment's final check (window =
the segment's start) turns the cell it started in to STRAY afterwards (an
extra line). The machine line keeps the plan's fields; its `fail` counts
FAIL + CRASH.

### 4.4 Reports (DG8)

`cells.tsv` — header + one row per cell: `idx bash_version bash_path mode cwd
suite repeat verdict rc total passed failed warn fail_lines strays attempts
duration_ms log`. `summary.json` — `{gate:{started, finished, root, out,
argv, repos:{name:{sha,dirty}}}, bashes:[…], totals:{per bash}, cells:[…],
verdict}`: written with printf + one JSON-string escape function, never read
by gate. `--compare` reads the other run's `cells.tsv` and prints per
(bash, mode, cwd, suite) the changed `total`/`passed`, and "totals unchanged"
when none — the "sweep sum 8707 on both bashes" check, done by the tool.

**G3 as built (2026-10-20)**: `cells.tsv` has the plan's columns plus
`reruns rerun_pass flaky reason` (22; `reason` last, the only free text); a
row per PLANNED cell (a cell never started: `UNSTARTED`); no value holds a
tab/newline/CR (each a space), an empty value is `-`, `flaky` joins names
with `/` (no file name holds one). `summary.json` adds `gate.options`,
`changed` (with `--changed`), `compare` (with `--compare`), `machine` (the
`__GATE__` line) and `exit`; `totals` is keyed by bash version (a second
`--bash` of the same version: `"5.3.9 (2)"`) with every verdict count,
`passed_tests`, `total_tests`, `duration_ms`; each cell carries the tsv
columns typed (numbers, `flaky` an array, empty = null) plus `attempt1`,
`ckk` and `fails` (the first 5 lines of `fails.txt`). The JSON escape
(`_kt_gate_jstr`) escapes `"` `\` and every control character (`\n \r \t
\b \f`, the rest `\u00XX`), bytes ≥ 0x80 pass through — 053 reads them back
with node. Both reports are written before the verdict line (a watcher that
sees `__GATE__` finds them complete), also for an INTERRUPTED run.
`--compare` reads the base by its header's column names (needs
`bash_version mode cwd suite verdict total passed`; extra columns are
fine), before OUT is made — missing / empty / not a gate tsv / a row with
the wrong field count or non-numeric counts → rc 2. Per key over
`--repeat`: the largest total and the smallest passed (the worst repeat).
Kinds: `changed`, `added`, `removed`, `notrun` (the key is planned here but
SKIPPED / INTERRUPTED / UNSTARTED); a base row that never ran counts as
absent. The summary line carries the per-bash sums (`5.2.37 405/405 ->
403/405`); all detail lines go to `OUT/compare.txt`, the first 20 to the
output.

### 4.5 `--changed` (DG6)

`git status --porcelain` in the root repo and each submodule (uncommitted
changes — the pre-commit gate; a ref range is out of scope). Any path under
`kkore/ kklass/ ktests/ tests/` or `kbool.sh` → `all`. Otherwise each changed
path under `kcl/<dir>/` selects suite `kcl/<dir>`, plus `kcl` (the kcl-level
unit suite) for any change to a unit file, plus — transitively — every kcl
suite with a `kk.uses U` line (unit files AND test files: 14 test files
`kk.uses tstopwatch`) for each unit U defined under a selected dir. Docs-only
changes (`*.md`) still select their suite (doc-example tests exist, U5). The
selection and its reason are printed before the first cell.

**G3 as built (2026-10-20)** — the rule above, made precise:

- **The dependency travels through UNIT files only.** The units of `kcl/DIR`
  are *touched* by a change in `kcl/DIR` outside `DIR/tests/` that is not
  `*.md`; a unit whose unit file (`kcl/DIR/X.sh` with a `kk.unit X` line) has
  `kk.uses [--optional] U` for a touched or affected U is *affected*,
  transitively; selected = the suite of every affected unit + every suite
  with another script that `kk.uses` an affected unit — a test file
  (`kcl/DIR/tests/**.sh`) or a script the tests run (`kcl/DIR/bench.sh`:
  17 of them `kk.uses tstopwatch`, run by the `*_Bench.sh` tests; found when
  probing a tstopwatch change on a clean clone) — + every suite with a changed
  path. Such a script's `kk.uses` only selects its own suite: suite D's tests using U say nothing about D's unit, so a change
  of U does not reach the suites of D's dependents (the plan's wording "for
  each unit U defined under a selected dir" would have; DG6 says "touched
  units + their reverse dependents"). A test-only or docs-only change of DIR
  selects kcl/DIR alone.
- **Unit file** = has the `kk.unit` header (one `grep -r` over `kcl/*.sh`
  for the `kk.unit` / `kk.uses` lines: unit names are the literal words up
  to `||`/`;`/`#`/a redirection; `kk.uses "$u"` is skipped). A deleted
  top-level `kcl/DIR/X.sh` counts as a unit file of unit X (U33: the file
  stem) — `kcl` is selected and X's dependents too.
- **A submodule's commit that the root has not recorded yet** (the state
  between a submodule commit and the root's bump): the root's status is read
  with `--ignore-submodules=dirty`, a submodule entry there adds the files of
  `git -C SUB diff --name-only RECORDED HEAD`; when that cannot be read, all.
- Paths outside any suite (`kcl/README.md`, `docs/`, root files other than
  `kbool.sh`) select nothing; they are listed as `(no suite)`.
- The root must be the top of a git work tree (`rev-parse --show-toplevel`);
  a dir inside a repository is a usage error, and `gate repos:` likewise no
  longer reports an enclosing repository for a non-repository root (a
  fixture root in a test's tmp did).
- `git status` failing (or an unwritable TMPDIR for the NUL-separated list)
  is a usage error, never "nothing changed".

### 4.6 suitejob.sh (DG5)

Moved from `tests/tests.sh`, no behaviour change: `kt_suitejob_discover ROOT`
(the `process_dir` walk), `kt_suitejob_run LABEL CMD…` (background job under
`set -m`, TTOU/TTIN ignored, `wait` loop with TSTP suspend/resume),
`kt_suitejob_signal RC` (TERM the group, CONT, 15 s fork-free grace, KILL),
`kt_suitejob_strays LABEL` (the `_kt_master_strays` body: scan, 1 s recheck,
report with the running suite, stop). `tests/tests.sh` becomes discovery +
loop + summary over these; `045_StrayGuard.sh` pins the master behaviour and
must stay green unmodified. G1 (done): plus `kt_suitejob_init SINCE [MATCH]`
(the stray window + the KT_STRAYS_MATCH narrowing as parameters),
`kt_suitejob_break` (a caller's USR1 trap ends the wait: `kt_suitejob_run`
returns 1, `KT_SUITEJOB_PID` still names the job, the caller calls
`kt_suitejob_signal`) and `kt_suitejob_tstp` (the TSTP trap body); state in
`KT_SUITEJOB_*` globals (header of the file, `tools/README.md`). 045 needed
one fixture line — its fake root copied only `strays.sh` into `ktests/tools`,
the master now sources `suitejob.sh` too; no assertion changed.

## 5. Phases

| phase | content | gate |
|---|---|---|
| **G0** probe (no product code) | measure on both runtimes: launcher→segment rc propagation; STOP file and `-nt` heartbeat latency; launcher killed by SIGKILL / `taskkill /F` / TERM → segment notices ≤ 30 s and leaves nothing; `cygpath` of HOME/TMPDIR across runtimes; cost of an empty cell (sandbox create + scrub + remove). Report → plan amendments here (§4.1 may change) | supervisor review of the report |
| **G1** shared code | `tools/suitejob.sh` + `tests/tests.sh` on it (DG5); `KT_SUMMARY_FILE` in `ktests.sh` (nested-safe); tests 048 (summary file), 049 (suitejob.sh) | ktests suite + **full master sweep both bashes, totals identical to before**; 045 unmodified (G1: one fixture line, its fake root copies suitejob.sh too) |
| **G2** gate core (done 2026-10-20, awaiting review) | CLI + suite resolution; launcher/segment/cell; hermetic env; timeout; verdicts PASS/FAIL/TIMEOUT/CRASH/ENV(+1 retry)/STRAY; progress lines, summary, `__GATE__`, exit codes; OUT rotation. Fixture suites under `tests/gate_fixtures/` (pass, fail, hang, leak, env-signature, warn, crash); tests 050 (CLI/resolution), 051 (verdicts), 052 (signals, launcher death, strays — both runtimes) | ktests suite both bashes + **critic** (Opus) + `gate all` on both bashes = master sweep totals |
| **G3** reports + selection (done 2026-10-20, awaiting review) | `cells.tsv`, `summary.json` (+repo SHAs), `--compare`, `--rerun-failed`/FLAKY (flaky fixture: fails on its first run via a marker file), `--changed` with the reverse-dependency walk, `--mode both`, `--cwd both`, `--repeat`, `--parallel`, `--fail-fast`, `--warm`; tests 053 (reports/compare), 054 (`--changed` on a scratch git fixture with a submodule) | ktests suite both bashes; `gate --changed` on a real dirty tree selects what §4.5 says |
| **G4** adoption (done 2026-10-20, awaiting final critic) | `tools/README.md` gate section, `docs/README.md`; worker/critic brief template: "the gate is `gate.sh … all --compare LAST`; paste `summary.json` totals into the ledger"; final **critic** over G1–G3; the round's own closing gate is run with `gate.sh`. *As built:* the brief template is [`docs/GATE_FOR_AGENTS.md`](docs/GATE_FOR_AGENTS.md) (calls, running in the background, reading the verdict, the ledger one-liner, strays after the run); `docs/README.md` "Phase gate" (ktests.sh vs master vs gate); the kbool README names the gate for a change on both runtimes; tools/README gate section re-read against gate.sh (UNSTARTED, the gate verdict set, exit 1/2/3 details, `--opt=VALUE`, the `KT_GATE_BASHES` default, OUT in the first line, ~28 min); open items: the speed observation (§9) and `timing_check.sh --bash` across runtimes (spec file + `--reexec`, test 055) | ktests suite both bashes; every doc example run; final critic; supervisor `gate all --compare` → owner: commit / push |

Test numbers: round 6 P4 ended at 047; G1 took 048 (SummaryFile) and 049
(SuiteJob), so G2 has 050–052, G3 053–054 and G4 055 (TimingCheckReexec;
the G2 worker re-checks before creating files).

## 6. Acceptance (the whole plan)

1. `gate.sh --bash 5.2 --bash 5.3 all` reports per runtime the same per-suite
   totals as `bash tests/tests.sh` run directly on the same tree.
2. Overhead: ≤ 2 s per cell over the bare suite run; **no fork in the
   segment while a cell runs** (watchdog = builtins); the sweep's timing tests
   are not made flakier (`timing_check.sh` idea: 3 full gates, 0 TIMING-FAIL
   beyond the master baseline).
3. Hermeticity: with `debug = quiet` in the real `~/.kbool/config` and
   `$USERPROFILE/.kbool/config` (the U5 critic accident), a `KBOOL_HOME` and an
   exported `BASH_FUNC_kk.uses%%` in the caller, every cell's counts and
   `[FAIL]` set are unchanged.
4. Cleanliness: after TERM, Ctrl-C, SIGKILL and `taskkill /F` of the launcher —
   in each runtime — `strays.sh list --all` shows nothing of the gate within
   60 s; OUT has `result` files for the finished cells and an `INTERRUPTED`
   mark.
5. Fixture verdicts: fail → 1 with the `[FAIL]` lines shown; env-signature →
   ENV after one retry → 3; flaky + `--rerun-failed 1` → FLAKY → 4; hang →
   TIMEOUT with its group stopped; leak → STRAY, stopped, → 1; crash → CRASH.
6. The plan's own phase gates G2–G4 are run with gate.sh itself from G2 on.

## 7. Risks

- **Cross-runtime control** (§4.1) — measured in G0 (§8): STOP and the `-nt`
  heartbeat are reliable on both runtimes, idle and under 16+16 fork-storm
  workers (25 s margin to a false positive). The fallback is not needed:
  `kill -0` and `/proc` cannot see the other runtime's pid at all; only
  `ps -W` (~210 ms) or `tasklist` (~240 ms), one fork + exec per check, would
  — kept as a diagnostic only (a Windows pid is reused; it would need the
  start time too).
- **Tree kills** (`taskkill /F /T`, possibly an agent's TaskStop) terminate
  the launcher, the segment and every forked child without a trap; only an
  exec'd watchdog survives to stop the cell (§4.1). Test 052 must cover it
  in both directions.
- **Parent killed at Windows level**: the launcher survives it; without the
  parent watch (§4.1) the gate runs on unseen to its end.
- **Noisy fork counting on 5.2**: other tools' Git-bash shells live in the
  same runtime (G0: a foreign `curl`+`sleep` poll loop forked ~2/s), so a
  runtime-wide pid-counter proof of "no fork" is only valid on an idle
  runtime; 052's zero-fork check attributes forks by ppid instead.
- **Nested runners**: ktests' own suite starts ktests.sh/master inside test
  files; `KT_SUMMARY_FILE` and any `KT_GATE_*` must not leak into them (unset
  at start, test in G1).
- **Commit-charge ENV failures** (machine note 2026-10-14): ENV is a verdict,
  not a test bug; exit 3 tells the supervisor to re-run, not to fix.
- **SIGKILL delivery lag** (found in G1, fixed in G2): `kt_strays_stop` sent
  KILL 20× over 2 s and reported LEFT while the targets were merely not yet
  scheduled — a false STRAY for a gate cell. The KILL phase now runs by the
  clock (`KT_STRAYS_KILL_MS`, 10 s); 045 pins it through a seam (a wrapped
  `_kt_strays_signal` holds the KILLs for a while; the identity checks still
  run). The first build used a Windows-suspended target (`NtSuspendProcess`);
  review round 1 (R7) removed it: a killed 045 would have left a suspended
  process behind, forever, invisible to strays.sh (its cmdline read returns
  the exe path while it is suspended).
- **A lost watchdog** (review R6): the segment's watchdog enforces
  `--timeout` and delivers STOP/stale; the launcher replaces a silent one by a
  rescue (`seg-N.wdhb`), the segment refuses to start a cell without one.
  The watchdog's segment-killed path is done by one watchdog (a lock dir).
- **Duration**: a full two-runtime gate is ~28 min (G3 supervisor run,
  15m19s + 12m38s; the plan's first estimate, ~66 min, used the pre-kklass
  round 5 sweep time — §9); agents run it with
  `run_in_background` and watch `progress.txt`; `--parallel` is for
  orientation runs only (DG3).

## 8. G0 measurements (2026-10-19)

Probe scripts and raw output: the G0 worker's scratch dir (`w_g0/`, not in
the tree). Both directions (5.2→5.3, 5.3→5.2) and same-runtime as control;
numbers agree across directions unless noted. "No fork" proofs: cygwin pids
are sequential per runtime, so `: & a=$!; …; : & b=$!` bounds the forks in
between (calibrated: `$(:)` = 1, builtins = 0); on 5.2 attributed by ppid.

| # | fact | numbers |
|---|---|---|
| 1 | cross-runtime `exit N` | exact for 0–4, 64, 126–130, 137, 143, 255 |
| 1 | child killed by a signal, cross-runtime | **rc 0** (same runtime: 128+N) |
| 1 | launcher `kill` on the cross-runtime stub | no trap ever; 5.2→5.3 TERM/KILL = TerminateProcess; 5.3→5.2 TERM ignored, KILL terminates; the child's own children orphaned; stub + `wait` linger until those orphans exit (10.6 s / 24 s) |
| 1 | child output to a file | arrives line by line, 1–50 ms |
| 2 | env across runtimes | only HOME (child's passwd default), MSYSTEM, PATH (converted), PWD, SHLVL, SYSTEMDRIVE, SYSTEMROOT, TERM, WINDIR; lost: custom vars, `BASH_FUNC_*`, TMPDIR, TMP, TEMP, USERPROFILE, ProgramData, COMSPEC, locale |
| 2 | arguments across runtimes | unconverted (`/tmp/x` names another folder; `/c/…` = `C:/…` in both) |
| 2 | builtin scrub (`compgen -e`/`declare -Fx` → file → `mapfile`, `unset`) | 0 forks, 1.5 ms (5.3) / 4.8 ms (5.2); non-importable `BASH_FUNC_a b%%` etc. survive it |
| 2 | `cygpath` | present in both; 24–27 ms a call |
| 3 | STOP detection | tick 0.5 s: 15–405 ms; tick 1 s: 94–874 ms; writer runtime irrelevant |
| 3 | idle watchdog forks | 0 (both runtimes, 20–40 ticks) |
| 3 | `CHLD` trap vs `read -t` | does not interrupt it (cell end seen 720–745 ms late at tick 1 s) |
| 3 | trapped `USR1` vs `wait` | breaks it at once (rc 158) |
| 4 | mtime | sub-ms resolution; `: > f` updates it (also when empty); cross-runtime visible |
| 4 | heartbeat 5 s, 1 s ticks, stale = 30 missed ticks | max write gap 5.02–5.12 s, max age while alive ≤ 5.0 s (idle, storm 8+8, 16+16), stale 30.3–31.3 s after the last write, 0 false positives |
| 5 | launcher TERM | STOP seen +0.9 s, cell group empty +1.0 s, all gone, launcher exits with the result +1.0–1.5 s |
| 5 | launcher SIGKILL / `taskkill /F` | hb stale +30.2 s, group empty +30.2–30.4 s, nothing left |
| 5 | launcher's parent `taskkill /F` | launcher lives on, nothing noticed; with the parent watch: +0.86 s → STOP, all gone +1.06 s |
| 5 | `taskkill /F /T` on the launcher | segment + forked watchdog terminated, exec'd cell left detached; with an exec'd watchdog: noticed +0.7–0.9 s, group empty +0.8–1.0 s, nothing left |
| 5 | `kill -0 -- -PGID` | sees a group whose leader has exited (both) |
| 6 | other runtime's Windows pid alive? | `kill -0`, `/proc`: blind; `ps -W` 210–220 ms; `tasklist` 228–246 ms |
| 7 | cell overhead (mkdir 5 dirs + scrub + group start + stray scan + rm) over the bare suite, best of 5 | 72 ms (5.2), 17 ms (5.3); mkdir 27, rm 22–24, scan 1–4 ms; the suite's own start-up (~0.8 s) dominates |
| 7 | segment spawn | 24–35 ms; via `env -i` +15–19 ms |

Amendments applied above: §4.1 (spec file with mixed paths and the
caller's locale etc.; segment started via `env -i`; launcher never signals,
never trusts rc alone, does not block in `wait`, watches its parent; segment
main `wait`s, exec'd watchdog with USR1, tick-count heartbeat, tree-kill
recovery), §4.2 (fork-free scrub recipe, its `BASH_FUNC` gap, no `cygpath`
needed for `/c/…`, locale from the spec), §7 (fallback measured and dropped,
tree kill, parent kill, noisy 5.2 fork counting). No measurement argues
against DG1–DG8. Open for G2: the `--nohup` opt-out of the parent watch;
052 covers TERM, SIGKILL, `taskkill /F`, parent kill and `taskkill /T` in
both directions.

## 9. G4: the speed observation (2026-10-20)

The G2 note "a full gate (27 min, both runtimes) is much faster than the
master sweep (~33 min PER runtime)" compared two different trees: ~33 min was
the 5.3 sweep before kklass round 5 (kklass ledger, final gate 2026-10-17:
"5.3 sweep ~10 min, was ~33"; the round made class loads 20-30x faster).
On the SAME tree the sweep is not slower — the G2 acceptance run
(`g2sup/accept.sh`: gate all, then the master sweep, back to back):

| runtime | gate all (G2) | master sweep, same tree | gate − sweep |
|---|---|---|---|
| 5.2.37 | 15m02s (902 s) | 12m52s (772 s) | +130 s: kcl/math 135.6 s in the gate (the 018 race below, ~+116 s) + ~0.5 s/cell |
| 5.3.9 | 12m17s (737 s) | 11m50s (710 s) | +27 s ≈ 0.9 s/cell |

Per suite on 5.2 (seconds, wall, 2 interleaved reps; A = `tests.sh` from the
suite dir, B = from a neutral cwd, C = `KT_MASTER_SUITES=/<suite>/tests/ bash
tests/tests.sh`, D = `gate.sh --bash 5.2 <suite>`; raw data: the G4 worker's
`w_g4/speed/`):

| suite | A suite dir | B neutral | C master | D gate (cell) |
|---|---|---|---|---|
| kcl/dateutils | 25.6, 23.4 | 24.9, 22.0 | 25.4, 23.5 | 30.0 (26.9), 27.0 (24.1) |
| kcl/thttpserver | 41.3, 27.4 | 40.8, 41.0 | 41.2, 28.8 | 66.4 (63.4), 43.2 (40.6) |
| kklass | 130.9, 105.9 | 88.2, 95.6 | 88.4, 118.9 | 143.6 (140.6), 116.8 (111.0) |

* **The master costs nothing between suites**: C = B within the noise (the
  per-suite stray scan is one `/proc` pass, 1–4 ms; discovery ~0.1 s). The
  noise of one suite run on this machine is ±15–30 % (kklass 88–131 s,
  thttpserver bimodal ~28 / ~41 s whatever the method — its network
  timeouts), so a single run says little.
* **The gate costs ~0.5–1 s per cell plus ~3–6 s per run** (launcher: git
  status of the repos, the bash probe, the 1 s relay tick, the segment's
  final stray check; G3 run: the 30 cells of 5.2 sum to 912.8 s of a 919 s
  segment). Its cells are not faster than a direct run: the cold `.ckk` per
  cell (DG4) and the hermetic HOME/TMPDIR cost a little, never minutes.
* **The one large difference — kcl/math on 5.2 — is a test race, not the
  gate**: kcl/math direct 20.8 s, as a one-cell gate 23.9 s, but 135.6 s
  (G2) / 133.9 s (G3) in the full gates, and 133–142 s in five of the
  twelve G4 bisect gates with a full kcl/math cell (17.7–22.4 s in the
  other seven). Bisected to `kcl/math/tests/018_DE1_ProgfileSweep.sh`: it
  starts `bash -c '…; exec sleep 120' &`, waits for its pid file and sends
  one `kill -TERM`; on the Git-bash 5.2 runtime that TERM is evidently
  sometimes lost around the exec (cygwin exec = a new Windows process
  behind the same pid), and `wait` then sits out the full 120 s. `gate.sh --bash 5.2 --repeat 8
  kcl/math -- -n 18`: seven cells 3.4–3.7 s, one 123.6 s. Nothing of the
  race is the gate's: run directly, `kcl/math/tests/tests.sh -n 18` took
  ~124 s in 4 of 10 runs threaded and 0 of 10 with `--mode single` (3.7 s)
  — the threaded runner's timing makes the window likelier; the master
  sweep, threaded too, is exposed the same way (the G2 acceptance sweep,
  772 s, evidently did not hit it); a
  bisect of kcl/tests files (ttail first looked guilty) proved a coincidence
  on a re-run. Not a ktests defect; the supervisor fixed the test in kcl
  (018 sends TERM only once the child IS the sleep, waits bounded, then
  KILL; `gate --repeat 8` on both bashes: 16/16 cells ≤ 6 s).
* Nothing to fix in ktests: no pathological wait, no per-suite cost in the
  master; §7 "Duration" corrected (~28 min, not ~66).

### G4 review round 1 (final critic, 2026-10-20)

The final critic over G1–G4 (probes: the supervisor's `critic_final/`); the
supervisor decided R1–R12, the G4 worker fixed them (red first where a test
can show it):

| id | finding | fix | pinned by |
|---|---|---|---|
| R1 (F1, high) | timing_check's spec held the WHOLE exported env (live tokens) in `ktests/.tmp` (Users: read, Authenticated Users: modify), was `source`d back and left forever when the child never read it | an allowlist (`KT_* KBOOL_* KKLASS_* VERBOSE_KKLASS*`, `LANG LANGUAGE LC_* TZ TMPDIR HOME`, the Windows basics) + `--pass-env NAME`; the spec in a `mktemp -d` dir under TMPDIR / `%LOCALAPPDATA%/Temp`; no `exec`: the parent runs the child (`env -i`, a process group of its own), waits, removes the dir in its EXIT trap, passes TERM/INT on as a real TERM of the child's runtime; a child that never reads the spec → rc 2 | 055 (6 cases, both runtimes) |
| R2 (F2, high) | one ENV file + one real FAIL → ENV (rc 3) | ENV only when every failed file is an `env` file or owns a raw fork-failure line (the line precedes the file's next tagged message); else FAIL with `+ fork failure in …` | 051 (`mix` fixture) |
| R3 (F3) | `--compare LAST` without a readable base refused the run | unreadable candidates skipped (a note), none → `[WARN] … no base`, no compare; explicit DIR/FILE still rc 2; newest by start stamp, a tie by name | 053 |
| R4 (F4) | a worktree rename (`Y=R`) mangled the old path | X or Y | 054 |
| R5 (F5) | the root README selected nothing; `.gitmodules` neither | a doc map (`README.md` → kkore); `.gitmodules` → all | 054 |
| R6 (F6, F10b) | base suites not planned here counted as changes and in the sums; a base row that never ran was "added" | compared over the planned keys; base-only keys apart (`base_only`); "not run in the base" | 053 |
| R7 (F7) | summary.json could hold invalid UTF-8 | invalid sequences → U+FFFD (`_kt_gate_jutf8`) | 053 (strict `TextDecoder`) |
| R8 (F8) | FAILFAST: two writers could race | `mkdir FAILFAST.lock` decides | 054 |
| R9 (F9, F10, F12, F13) | `--help` printed code; huge base numbers; long / control-char suite ids in the lines; a deleted non-unit script counted as a unit | header comment only; ≤ 18 digits; the suite column capped at 40 (`...`), control chars `?`; a deleted file is a unit only when its HEAD version has `kk.unit` | 053, 054 |
| R10 (F11) | `--warm`: `seg-N.ckk` left on the segment-killed path | removed there too | 052 (segtree with `--warm`) |
| R11 (F14, F15) | docs; `--out` inside the tree (the segments source `OUT/seg-N.spec`) | §3 FLAKY example, the tools README timing-tests heading, `timeout -k 120`, `--out` must be private + a `[WARN]` inside the tree | 050 |
| R12 | ledger / plan | `phases.G4.review_round_1`, `open` / `closed` | — |
| R13 (supervisor, on the worker's open note) | the DEFAULT OUT root of a 5.3 launcher was MSYS2's `/tmp` (`C:/bin/msys64/tmp`, Authenticated Users: modify) and the segments source `OUT/seg-N.spec` from it; a killed timing_check parent left its private dir | the default root is PRIVATE_TEMP/kt-gate (`_kt_gate_ptmp`: TMPDIR when set, else `%LOCALAPPDATA%/Temp`, else `cygpath -F 28`/Temp; mixed form) — ONE root for both runtimes, so LAST and the rotation are runtime-independent; the rotation's other-runtime rule also needs a stale `OUT/hb` (a live launcher of the other runtime that already wrote INTERRUPTED keeps its dir); timing_check writes an `owner` marker and sweeps dead owners' dirs | 050 (default root unit + both launchers share it, LAST both ways; rotation `othlive`/`othdead`), 055 (sweep) |
