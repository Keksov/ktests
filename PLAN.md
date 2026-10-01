# ktests — fix plan: a fatally-aborted test file can report green (2026-09-30, critic-hardened 2026-10-01)

**Status: PLANNED, critic-hardened, no code.** One finding (T1) from the
kcl/thttpserver review round; the first draft's mechanism was **wrong** and was
replaced by the critic's measured matrix (2026-10-01, both bashes, identical).
Ledger: [`ktests_ledger.json`](ktests_ledger.json). Workflow: one Opus worker phase →
review → ktests suite + full kbool master sweep on bash 5.2.37 AND 5.3.9 → commit.
This phase runs **before** the kklass round-2 phases.

## 1. The finding, as measured

The runner captures each file as `bash -c 'source ktest_source; source FILE; echo
__COUNTS__:…' || true` (`ktest_runner.sh:395-416`) and retries up to 3× when no
counts line appears. **Two distinct abort classes exist, and the current runner
reports both green** (matrix: 18 fixture files — 2 passing asserts, the error, 1 more
assert — identical on 5.2.37 and 5.3.9):

| class | rest of file | wrapper echo | source rc | runner today |
|---|---|---|---|---|
| **(B) aborted top-level command**: arithmetic recursion, `(( 1 + ))`, `$((1/0))`, empty/negative assoc subscript | **runs** | reached | **0** | green (the aborted command's asserts vanish) |
| **(A) shell exit**: `exit N`, `set -u` unbound, `${v:?}`, `set -e; false`, inline syntax error, file-scope `return N` | no | **not reached** (A1) / reached with rc (A2: syntax, return) | – / 2 / 4 | **green with the counts collected so far** — printed by `kt_test_init`'s EXIT trap (`ktest.sh:110-111`), not by the wrapper |
| own EXIT trap replaced, then exit | no | no | – | FAIL after 3 retries (the one case caught today) |

So: a source-rc check alone is blind to class (B) — the file "completes" with rc 0 —
and the wrapper echo being unreached does not make the counts line disappear, because
the EXIT trap prints one. The first draft's §1 said the opposite; its cited anecdote
(thttpserver 003 "131/131 green vs 137/4") is **not reproducible** against the
committed files (reconstruction: wrapper gives `137:133:4`, the threaded suite shows
the 20-FAIL red the ledger records; 131 was the pre-review count). The green-path
mechanism above is what is real and what gets fixed.

Baseline facts for the compatibility gate (526 file-runs per bash, instrumented):
source rc ≠ 0 — **0 occurrences**; start-without-end — 0; `t > p+f` — only 2 nested
ktests-022 fixtures (their outer test asserts `TESTS_TOTAL >= 2`, unaffected);
`p > t` (a double pass) — 8 real files (tcustomapplication 018/024/029, kklass
108/109, ktests 013/015/022), so the unclosed-test detector must be one-sided;
bash fatal-diagnostic lines in captured output — 0. Per-suite totals were identical
across 4 full sweeps (sum 7794), so the "unchanged totals" gate is real.

## 2. The fix

1. **END marker with a per-file nonce.** The runner generates a nonce, passes it in
   the wrapper's env, and the wrapper prints `__KT_END_<nonce>__:<src_rc>:<t>:<p>:<f>`
   right after the `source`. Only the nonce'd marker counts (a normal run already
   prints `__COUNTS__` twice — wrapper + EXIT trap — and nested-runner fixtures can
   print marker-looking lines; C7). Rule = "marker present", never "output ends with".
2. **Class-A detector:** END marker missing → FAILED "shell exited mid-file (child
   rc=N)". END present with src_rc ≠ 0 → FAILED "source returned rc=N". Measured:
   0/526 legitimate files have src_rc ≠ 0 on either bash, so nothing needs protecting;
   if a file ever needs a deliberate early exit, that is a new tiny
   `kt_test_skip_file` helper, added only when first needed.
3. **Class-B detector**, both one-sided: at END, `TESTS_TOTAL > TESTS_PASSED +
   TESTS_FAILED` (an unclosed test) → FAILED "test aborted mid-block"; and a captured
   line matching `^<file>: line N: …(expression recursion level exceeded|bad array
   subscript|invalid variable name|circular name reference|division by 0|unbound
   variable|syntax error)` → FAILED naming the diagnostic. Red-first fixtures put the
   error **inside a test block** so the case is well defined; a file-scope error
   followed by more tests is caught by the diagnostic grep alone.
4. **Verdict folding (threaded path).** The verdict is folded into `counts_line`
   inside `kt_runner_execute_single_test` — `__COUNTS__:$((t+1)):$p:$((f+1))` plus an
   emitted `[FAIL] <basename>: source aborted (<cause>)` — BEFORE `run_test` writes
   the result file, because the threaded collector reads only the first `__COUNTS__`
   line (`kt_runner_find_first_counts_in_file`, `:574`) and fails a file only on
   `f>0` (`:594`). The bash diagnostic line is passed through
   `kt_runner_filter_output` (today it hides everything not `[`-prefixed, `:441-470`).
5. **Retry** iff: no END marker AND no counts line AND (the capture is empty OR it
   matches the ENV fork-failure signatures). The signature regex becomes ONE shared
   definition used by both the runner and `tools/timing_check.sh` (today's copy would
   drift). Never retry when counts or END are present — today a deterministic
   no-counts death is retried 3× and then correctly FAILED (measured), and a worker's
   own fork failure lands on stderr outside the capture, so the empty-output arm is
   the one that matters.
6. **Nothing changes** for a file whose assertions merely fail, and the full-sweep
   per-suite totals must come out identical (sum 7794) on both bashes.

## 3. Phase

| phase | content | gate |
|---|---|---|
| **P0** | the §2 fix; red-first fixtures per abort class (recursion, bad subscript, `$((1/0))`, `exit N`, `set -u`, `${v:?}`, `set -e`, inline syntax error, file-scope `return N` — each must be reported FAILED with its cause; a last-command-rc-1 file and a double-pass file must stay green), run through **both** `kt_runner_execute_sequential` and `kt_runner_execute_threaded` asserting `FAILED_TEST_FILES`; runner docs | ktests suite green both bashes; full kbool master sweep 0 [FAIL] and **identical per-suite totals** (sum 7794) on both |

## 4. Traps

- The runner is threaded ×8: the nonce and any temp names must be per-file; no shared
  state.
- The EXIT trap prints a second `__COUNTS__` — never key on count-line uniqueness.
- Environment variables do **not** cross from Git-bash 5.2 into
  `/c/bin/msys64/usr/bin/bash.exe`: drive 5.3 runs from inside 5.3 and pass variables
  in the `-c` string (a critic sweep silently logged nothing because of this).
- A test's own EXIT trap replaces the framework's — the fix must not add EXIT traps
  inside the sourced context.
- `python` on this machine is a hanging Store stub; probes with stdin closed, under
  `timeout`.
- Read sweep results by grepping ALL `[FAIL]` lines, never the tail.
