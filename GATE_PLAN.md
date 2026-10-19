# ktests gate — one command for the phase gate (2026-10-19)

**Status: PLANNED, owner decisions DG1–DG8 taken (quiz 2026-10-19), no code.**
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
[ 9/60] 5.2.37 threaded neutral kcl/thttpserver  FLAKY   497/497 (rerun 1: 005_Lifecycle)  71.2s
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
its own (`_kt_strays_nap`). **G0 measures this before anything is built.**

### 4.2 Hermetic cell (DG4)

Per cell: `OUT/cells/NNN/{home,tmp,etc,cwd,ckk}` + `log.txt` + `result`. Inside
the target bash before `exec`:

- `HOME`, `TMPDIR`, `USERPROFILE` → the cell's home/tmp (mixed `C:/…` paths
  passed in, converted once with `cygpath -u` in the target runtime — the two
  runtimes map `/tmp` to different Windows folders); `ProgramData` and
  `__KK_CFG_ETC` → the empty `etc`; `KKLASS_CKK_DIR` → `ckk` (`--warm`: one per
  segment);
- unset every exported variable with a prefix `KBOOL_ KKLASS_ KK_ __KK KT_ _KT_`
  except what gate sets, plus `BASH_ENV ENV VERBOSE_KKLASS CDPATH GLOBIGNORE`,
  and every exported function (`BASH_FUNC_*`) — the `set -a` child lesson (U1a
  R14);
- keep PATH (target bash dir first), `SYSTEMROOT WINDIR COMSPEC`, the locale as
  the caller has it (030 LocaleContract owns locale behaviour, gate does not);
- cwd = `cwd/` (neutral) or the suite's `tests/` dir (`--cwd suite`); stdin
  `/dev/null`.

A passed cell's sandbox is removed (log and result kept) unless `--keep`. OUT
default: `${TMPDIR:-/tmp}/kt-gate/<stamp>-<pid>`; the last 10 runs are kept —
only directories with gate's own marker whose owner pid is gone are ever
removed (the `kt_iso` dead-pid rules, incl. the other-runtime age guard).
`LAST` = the newest finished run under the same OUT root.

### 4.3 Results without parsing prose

`ktests.sh` gains `KT_SUMMARY_FILE=PATH`: at the end of a run it writes
`total passed failed` and one `file NNN_Name.sh` line per failed file. It reads
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

### 4.4 Reports (DG8)

`cells.tsv` — header + one row per cell: `idx bash_version bash_path mode cwd
suite repeat verdict rc total passed failed warn fail_lines strays attempts
duration_ms log`. `summary.json` — `{gate:{started, finished, root, out,
argv, repos:{name:{sha,dirty}}}, bashes:[…], totals:{per bash}, cells:[…],
verdict}`: written with printf + one JSON-string escape function, never read
by gate. `--compare` reads the other run's `cells.tsv` and prints per
(bash, mode, cwd, suite) the changed `total`/`passed`, and "totals unchanged"
when none — the "sweep sum 8707 on both bashes" check, done by the tool.

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

### 4.6 suitejob.sh (DG5)

Moved from `tests/tests.sh`, no behaviour change: `kt_suitejob_discover ROOT`
(the `process_dir` walk), `kt_suitejob_run LABEL CMD…` (background job under
`set -m`, TTOU/TTIN ignored, `wait` loop with TSTP suspend/resume),
`kt_suitejob_signal RC` (TERM the group, CONT, 15 s fork-free grace, KILL),
`kt_suitejob_strays LABEL` (the `_kt_master_strays` body: scan, 1 s recheck,
report with the running suite, stop). `tests/tests.sh` becomes discovery +
loop + summary over these; `045_StrayGuard.sh` pins the master behaviour and
must stay green unmodified.

## 5. Phases

| phase | content | gate |
|---|---|---|
| **G0** probe (no product code) | measure on both runtimes: launcher→segment rc propagation; STOP file and `-nt` heartbeat latency; launcher killed by SIGKILL / `taskkill /F` / TERM → segment notices ≤ 30 s and leaves nothing; `cygpath` of HOME/TMPDIR across runtimes; cost of an empty cell (sandbox create + scrub + remove). Report → plan amendments here (§4.1 may change) | supervisor review of the report |
| **G1** shared code | `tools/suitejob.sh` + `tests/tests.sh` on it (DG5); `KT_SUMMARY_FILE` in `ktests.sh` (nested-safe) + test | ktests suite + **full master sweep both bashes, totals identical to before**; 045 unmodified |
| **G2** gate core | CLI + suite resolution; launcher/segment/cell; hermetic env; timeout; verdicts PASS/FAIL/TIMEOUT/CRASH/ENV(+1 retry)/STRAY; progress lines, summary, `__GATE__`, exit codes; OUT rotation. Fixture suites under `tests/gate_fixtures/` (pass, fail, hang, leak, env-signature, warn, crash); tests 048 (CLI/resolution), 049 (verdicts), 050 (signals, launcher death, strays — both runtimes) | ktests suite both bashes + **critic** (Opus) + `gate all` on both bashes = master sweep totals |
| **G3** reports + selection | `cells.tsv`, `summary.json` (+repo SHAs), `--compare`, `--rerun-failed`/FLAKY (flaky fixture: fails on its first run via a marker file), `--changed` with the reverse-dependency walk, `--mode both`, `--cwd both`, `--repeat`, `--parallel`, `--fail-fast`, `--warm`; tests 051 (reports/compare), 052 (`--changed` on a scratch git fixture with a submodule) | ktests suite both bashes; `gate --changed` on a real dirty tree selects what §4.5 says |
| **G4** adoption | `tools/README.md` gate section, `docs/README.md`; worker/critic brief template: "the gate is `gate.sh … all --compare LAST`; paste `summary.json` totals into the ledger"; final **critic** over G1–G3; the round's own closing gate is run with `gate.sh` | owner: commit / push |

Test numbers 048+ assume round 6 P4 ends at 047 (`046`, `047` untracked now);
the G2 worker re-checks before creating files.

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

- **Cross-runtime control** (§4.1) is the one unmeasured mechanism — G0 first;
  fallback if `-nt` heartbeats prove unreliable on one runtime: the segment
  polls the launcher's Windows pid via `/proc/<pid>/winpid` + `ps -W` once per
  30 s (one fork per 30 s, outside timing windows as far as the runner allows).
- **Nested runners**: ktests' own suite starts ktests.sh/master inside test
  files; `KT_SUMMARY_FILE` and any `KT_GATE_*` must not leak into them (unset
  at start, test in G1).
- **Commit-charge ENV failures** (machine note 2026-10-14): ENV is a verdict,
  not a test bug; exit 3 tells the supervisor to re-run, not to fix.
- **Duration**: a full two-runtime gate is ~66 min; agents run it with
  `run_in_background` and watch `progress.txt`; `--parallel` (~35 min) is for
  orientation runs only (DG3).
