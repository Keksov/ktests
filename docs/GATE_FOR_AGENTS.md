# The phase gate for agents

`ktests/tools/gate.sh` is the harness — do not write your own (no `for b in
5.2 5.3` loops, no `timeout` + `PATH=…msys64…` wrappers, no grepping
`Total tests`). Reference: [`../tools/README.md`](../tools/README.md#gatesh--the-phase-gate).

## Calls (from the kbool root, Bash tool)

```bash
# in EVERY call: a tool call's shell keeps no variables from the last one
export KT_GATE_BASHES="C:/bin/Git/usr/bin/bash.exe;C:/bin/msys64/usr/bin/bash.exe" G=ktests/tools/gate.sh

bash $G --rerun-failed 1 --compare LAST all   # the phase gate: every suite x both bashes (~28 min)
bash $G --changed --compare LAST              # only what the uncommitted diff touches
bash $G kcl/tstringlist                       # one suite x both bashes
bash $G kcl/tregex -- -n 1-12                 # some test files of a suite (args to its tests.sh)
bash $G --out "$SCRATCH/g_p3" kklass          # an OUT dir of your choice (new or empty, PRIVATE)
```

`KT_GATE_BASHES` is read by the launcher, in the bash you start it with —
the gate passes everything else to the other runtime itself. `--compare LAST`
= the newest finished run under the default OUT root (`TMPDIR`, else
`%LOCALAPPDATA%/Temp`, + `/kt-gate`: one root for both bashes);
a run with `--out` is compared by naming it: `--compare "$SCRATCH/g_p3"`.
LAST is simply the newest — after a few small runs, name the base you mean;
a 5.2 and a 5.3 launcher share that root, so LAST may be the other's run;
with no readable base the gate says `[WARN]
--compare LAST: no base` and runs without a compare. `--out` must be a
private dir — `$SCRATCH` = your scratch dir: the segments source a spec file
from it (inside the tree: a `[WARN]`).
`--changed` with a dirty `ktests/`, `kklass/`, `kkore/`, `tests/` or
`kbool.sh` means `all`; with nothing to run it says `[WARN] nothing changed`,
exit 0, no OUT.

### The bash-floor gate (5.1)

The floor is bash 5.1 (owner decision OG2), and no Windows runtime has it. A
phase that changes code in `kbool.sh`, `kkore`, `kklass` or `ktests` also runs
the suites on 5.1.16 in the lab VM, after the Windows gate (never beside it):

```bash
bash tools/vmlab/vmlab.sh gate kb-debian --snapshot clean-bashes --out "$SCRATCH/vm51" \
  --env 'KT_GATE_BASHES=/opt/bash-5.1.16/bin/bash;/usr/bin/bash' -- --rerun-failed 1 --timeout 900 all
```

It takes about 12 min (5.1.16 and 5.2.37), so start it with `run_in_background: true`. vmlab
restores the snapshot, syncs the working tree, prints the gate's `__GATE__`
line, fetches its OUT into `$SCRATCH/vm51` and powers the VM off (only
kb-debian, one VM at a time). For a unit-only phase, the CI row
`bash 5.1 alpine` after the push is enough. Constructs that break on 5.1
are listed in [`../../docs/dev/launch/L4_cost.md`](../../docs/dev/launch/L4_cost.md) §1, and each repo's
`*_Bash51Hazards.sh` test rejects them.

## Run it

* **`run_in_background: true`**, one call, nothing around it. Each cell is
  bounded by the gate (`--timeout`, default 1800 s); `timeout -k 120 9000 bash
  $G …` as an outer cap is fine (`-k` longer than the 90 s a stopping
  launcher may wait for its segment, `KT_GATE_STOP_WAIT`).
* **Never detach it with `&`**, `( … & )` or `nohup … &` inside a tool call:
  the call's shell exits, the gate sees its parent gone and stops itself
  (exit 143) — or, behind a wrapper that lives on, runs unwatched with
  nobody reading it. `--nohup` is only for a run you detach on purpose and
  then own (its OUT, its stop).
* **Watch** `OUT/progress.txt`: OUT is in the first output line (`gate STAMP
  root=… out=OUT`). Look with a short `tail -n 5 "$OUT/progress.txt"` now and
  then, or just wait for the background notification. No `tail -F`, no
  Monitor and no sleep loop that outlives you (a bounded wait is fine:
  `timeout 170 bash -c "until grep -q '^__GATE__' '$OUT/progress.txt'; do sleep 3; done"`).
* **One gate at a time** on the machine, and no sweep or fork storm beside
  it: timing tests are fork-latency tests. Never `--parallel` for a phase
  gate.

## Read the result

The last line is the machine line, the exit code says the same:

```
__GATE__:VERDICT:cells:pass:fail:flaky:env:timeout:stray:passed_tests:total_tests
```

| exit | verdict | what to do |
|---|---|---|
| 0 | PASS | done; `warn=N` on a line still deserves a look |
| 1 | FAIL | read the `[FAIL]` lines under the cell's line and its `log=`; FAIL, TIMEOUT, CRASH and STRAY are all exit 1 |
| 2 | usage | nothing ran (bad option, unknown suite, bad `--compare` base) |
| 3 | ENV | the **machine**, not the test (a fork failure near the commit limit), already re-run once: re-run the gate, do not change tests |
| 4 | FLAKY | **not a PASS**: the failed files passed only on `--rerun-failed`; report the `flaky` files |
| 128+N | INTERRUPTED | the gate was stopped (TERM 143, INT 130, HUP 129); partial `cells.tsv`/`summary.json` |

* **STRAY = a bug**: a cell left a process (named in `cells/NNN/strays.txt`,
  stopped by the gate when possible — the reason says `K could NOT be
  stopped`, or `job leader P could NOT be stopped (winpid W)`, when it was
  not: report those pids). Fix the test or the unit; never just re-run.
* **TIMEOUT `runner did not start (no result, no child within Ns)`** is a
  runtime wedge (Git-bash: a cygwin FIFO open that never returns, launch
  L2.7-G), not the test: re-run, do not "fix the test". Early output (e.g.
  `-v info`) or a running test file counts as started; the wait is
  `KT_GATE_START_GRACE` (default 120 s) plus ~30 s.
* The `gate compare` line says `totals unchanged (…)` or lists what changed
  (all of it in `OUT/compare.txt`). A changed total is a finding to explain.
* Counts are per runtime: `gate 5.2.37: …` and `gate 5.3.9: …`.

## Into the ledger

Paste the record from `summary.json`, never retyped counts:

```bash
OUT=…   # from the first output line
node -e 'const j=require(process.argv[1]); console.log(JSON.stringify({verdict:j.verdict, out:j.gate.out, repos:j.gate.repos, totals:j.totals, compare:j.compare}))' "$(cygpath -m "$OUT/summary.json")"
```

## Hygiene around it

The gate stops its own cells (also when it is killed: within ~30 s). After
every run, still list strays in **both** runtimes and put the listing in your
report:

```bash
bash ktests/tools/strays.sh list --all
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe ktests/tools/strays.sh list --all
```

Each must say `strays: none (…)`. Something listed: report it; stop only
processes you started yourself (by your recorded pid), never by a name
pattern. Remove your own scratch dirs (`--out`) when the record is in the
ledger; default OUT dirs rotate by themselves (the newest 10 stay).
