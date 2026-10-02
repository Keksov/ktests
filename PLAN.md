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

**P0 DONE 2026-10-01 (worker; awaiting review, not committed).** END marker + class-A/B
detectors + folding + retry rule in `ktest_runner.sh`; shared `ktest_env_signatures.sh`
(also used by `tools/timing_check.sh`); tests 034 (22, red 19) and 035 (10, red 8);
ktests 351/351 threaded on 5.2.37 and 5.3.9 and single on 5.2.37; kklass 344,
thttpserver 497, tpipe 190, kkore 455 unchanged on both. Deviation D1: §2.2 and the
last-command-rc-1 control contradict (both give source rc 1) — rc ≥ 2 is the verdict,
rc 1 alone is not; a `return N` inside a test block is still caught as an unclosed
test. Details, measurements and D2–D6 in the ledger.

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

# Round 3 (2026-10-02) — the P0 leftovers T2–T5 (critic-hardened the same day)

**Status: PLANNED, critic-hardened (C1–C6 folded), all decisions taken; no code.**
Owner 2026-10-02: "Бери список в работу". Runs FIRST in round 3 (before kklass
P10/P11 — `kklass/PLAN.md` "Round 3"). Ledger key `round3`.

## R3.1 Findings (re-confirmed 2026-10-02)

| ID | Sev | Where | Symptom |
|---|---|---|---|
| T2 | low | runner verdict (P0 deviation D1) | A file-scope `return 1` BETWEEN tests ends the file early and is reported green with a lower total: source rc 1 is indistinguishable from a legitimate last-command rc 1, no test is open. |
| T3 | low | `kt_runner_execute_threaded` (exports at `ktest_runner.sh:681-682`) | (C3) On 5.2.37 a prefix assignment (`VERBOSITY=error kt_runner_execute_threaded …`) persists after the call, for all 7 exported names incl. `results_dir` (a deleted mktemp path); on BOTH bashes a plain call leaves previously non-exported globals `declare -x` (VERBOSITY, `_KT_ASSERT_QUIET_MODE`, `KT_BASH_FATAL_DIAG_RE`), a global function `run_test` and 10 exported functions in the caller. |
| T4 | low | missing test file | `KT_ERROR_COUNTS` (`:40`) is readonly but not exported: in an xargs worker the counts line is empty (the collector still counts 1:0:1). (C4) Sequential mode silently SKIPS a missing file (`kt_runner_execute_sequential:618` `continue`): T=1 F=0, `FAILED_TEST_FILES` empty, while threaded gives T=2 F=1. |
| T5 | low | tests that install their own `trap … EXIT` | The trap REPLACES `kt_test_init`'s (`ktest.sh:110-113`): `kt_fixture_teardown` never runs, `tests/.tmp/<Name>.<file>` stays. (C5) The files are the 8 kklass tests 119, 121, 123, 124, 125, 126, 132, 133 — NOT kcl/math 015 (its trap is inside a child `bash -c` and is the subject of its M6 test; must stay). Of the 23 stale dirs only those 8 are regenerated; 15 are pre-5f64a4b legacy names (6 kklass without the `.file` suffix, 8 tstringhelper, 1 tregex) — remove once. The 8 files keep their own temp files in `${TMPDIR:-/tmp}/kkNNN_$$`; 124 exports a private TMPDIR to count leaks; 133 `cd`s into its TMPD (its trap does `cd /` first). |

## R3.2 Decisions

| # | Decision |
|---|---|
| DT2 | (owner: adopt if the critic's measurement is clean — it is, C1/C2) The wrapper sets a RETURN trap around `source FILE` that records `$?` at trap entry ONLY when `${#BASH_SOURCE[@]} == 0` (the outer source; nested sources fire at depth 1). Verdict "file-scope return" iff the trap fired at depth 0 AND src_rc < 2 AND trap_rc ≠ src_rc (a syntax error gives 257 vs 2 → already the rc ≥ 2 verdict). `$BASH_COMMAND` does NOT work (always the caller's `source`, C1). Applies to `return 0` too where detectable. Measured: 20/20 legitimate endings trap_rc == src_rc; detects `return 1`, `if …; then return 1; fi`, `return 1` under set -T, `eval "return 1"`, `cond || return 0`; zero would-be verdicts on the corpus (ktests, kklass, kkore, thttpserver incl. set -T DEBUG canaries, both bashes); 0 forks, +23 µs per depth-1 source, +8.5 µs per function return under set -T. Plumbing: a separate nonce'd line (or a 6th END field — the worker picks, updating `kt_runner_scan_capture`, `kt_runner_print_output_without_counts`, `kt_runner_filter_output` and 035 consistently). Documented residual: `cmd || return N` whose prior status is N, a bare `return`, and a test that installs its own RETURN trap (blind, no verdict). |
| DT3 | (supervisor, C3) T3: `run_test` is defined and all exports plus the xargs/manual spawn run inside ONE `( … )` subshell; `KT_ERROR_COUNTS` exported there (T4). The caller needs none of them afterwards (the collector reads only the result files) — "no caller-visible change" includes values, export attributes and functions, on both bashes. Measured prototype: zero leak, ktests 351/351 both. T4b (C4): sequential folds a missing file as 1:0:1 into `FAILED_TEST_FILES`, like threaded. |
| DT5 | (owner: files + framework protection; mechanism per C6) (a) the 8 kklass files switch to `kt_fixture_cleanup_register` (a handler that `cd /` first where the file `cd`s; temp paths may move under `kt_fixture_tmpdir`; 124's private-TMPDIR leak count must keep its meaning); (b) runner-side: in `kt_runner_execute_single_test`, after `kt_runner_judge_capture`, remove `${file%/*}/.tmp/*.<base%.sh>` if still present and print a `[WARN] <file>: fixture dir left behind (own EXIT trap?)` line — measured 0 leftovers sequential + threaded, both bashes, exactly the 8 files warn before (a); (c) standalone `bash FILE`: `kt_fixture_init_tmpdir` wipes an existing dir at setup (leak bounded to one dir per file); (d) NO `trap` shim (measured +13 µs per trap call, shadows the builtin everywhere); (e) docs: "never `trap … EXIT` in a test — the runner cannot run your registered handlers (e.g. `kt_fixture_backup_file` restores)"; (f) the 15 legacy dirs removed once. kcl/math 015 untouched. |

## R3.3 Phase

| phase | content | gate |
|---|---|---|
| **P1** | T2 per DT2, T3/T4/T4b per DT3, T5 per DT5. Red-first: T2 FAILED — `return 1` after a pass, `if …; then return 1; fi`, `cond || return 0`, `eval "return 1"`, `return 1` under set -T; T2 green — last-command rc 1, `[[ ]] && x` at the end, a nested sourced lib's `return`, a test's own RETURN trap (no verdict), a thttpserver-style set -T DEBUG canary; all through sequential AND threaded. T3: per exported name, a prefix assignment AND the export attribute after a plain call; `run_test` and the exported functions absent after the call (both bashes). T4/T4b: a missing file gives the same counts and FAILED list in sequential and threaded. T5: an own-trap fixture through sequential and threaded leaves no dir and prints the WARN; a standalone run's stale dir is wiped at the next setup; math 015 untouched. The 8 kklass files edited (cleanup only, kklass totals unchanged); docs/README "How the Runner Judges a Test File" (T2 rule + residual) and the EXIT-trap rule | ktests suite both bashes (`--mode single` on 5.2); kklass suite both bashes; master sweep 0 [FAIL], identical per-suite totals except ktests |

## R3.4 Critic record (2026-10-02)

C1 blocker: `$BASH_COMMAND` in the RETURN trap is always the caller's `source` — the
detector uses `$?` at trap entry with a depth-0 guard (rule above). C2: corpus clean on
4 suites × 2 bashes, cost measured, plumbing gap named. C3: T3 is a 5.2-only value leak
but an all-bash attribute/function leak; wrong line ref. C4: sequential skips a missing
file. C5: math 015 must not be edited; 15 of 23 dirs are legacy. C6: runner-side glob
removal + WARN reliable; standalone needs the setup wipe; shim rejected. Probes:
`scratchpad/critic3/{dt2,ktx,dt3,dt5}/`.
