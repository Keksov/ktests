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
| **P1** (DONE 2026-10-02, see below) | T2 per DT2, T3/T4/T4b per DT3, T5 per DT5. Red-first: T2 FAILED — `return 1` after a pass, `if …; then return 1; fi`, `cond || return 0`, `eval "return 1"`, `return 1` under set -T; T2 green — last-command rc 1, `[[ ]] && x` at the end, a nested sourced lib's `return`, a test's own RETURN trap (no verdict), a thttpserver-style set -T DEBUG canary; all through sequential AND threaded. T3: per exported name, a prefix assignment AND the export attribute after a plain call; `run_test` and the exported functions absent after the call (both bashes). T4/T4b: a missing file gives the same counts and FAILED list in sequential and threaded. T5: an own-trap fixture through sequential and threaded leaves no dir and prints the WARN; a standalone run's stale dir is wiped at the next setup; math 015 untouched. The 8 kklass files edited (cleanup only, kklass totals unchanged); docs/README "How the Runner Judges a Test File" (T2 rule + residual) and the EXIT-trap rule | ktests suite both bashes (`--mode single` on 5.2); kklass suite both bashes; master sweep 0 [FAIL], identical per-suite totals except ktests |

**P1 DONE 2026-10-02 (worker; awaiting review, not committed).** RETURN trap around
`source FILE` → 6th END field, verdict `file-scope return (source rc=R after status S)`;
threaded spawn + exports in one subshell, KT_ERROR_COUNTS exported, sequential folds a
missing file 1:0:1; runner removes a left fixture dir with a `[WARN]`, setup wipes a
stale one; the 8 kklass files use `kt_fixture_cleanup_register`; 15 legacy dirs removed.
Tests 036 (17, red 7), 037 (13, red 12 on 5.2 / 5 on 5.3), 038 (8, red 5); ktests
389/389 threaded on 5.2.37 and 5.3.9 and single on 5.2.37; kklass 535, thttpserver 497,
kkore 455 unchanged on both. Deviations D1–D9 and findings F1–F3 in the ledger.

## R3.4 Critic record (2026-10-02)

C1 blocker: `$BASH_COMMAND` in the RETURN trap is always the caller's `source` — the
detector uses `$?` at trap entry with a depth-0 guard (rule above). C2: corpus clean on
4 suites × 2 bashes, cost measured, plumbing gap named. C3: T3 is a 5.2-only value leak
but an all-bash attribute/function leak; wrong line ref. C4: sequential skips a missing
file. C5: math 015 must not be edited; 15 of 23 dirs are legacy. C6: runner-side glob
removal + WARN reliable; standalone needs the setup wipe; shim rejected. Probes:
`scratchpad/critic3/{dt2,ktx,dt3,dt5}/`.

# Round 4 (2026-10-03, critic-hardened 2026-10-05) — the P1 leftovers T6–T7

**Status: PLANNED, critic-hardened (C13/C14 folded), decisions taken; no code.**
Owner 2026-10-03: "Потом приступай к открытым пунктам". Runs FIRST in round 4
(before kklass P12 — `kklass/PLAN.md` "Round 4"). Ledger key `round4`.

## R4.1 Findings (ledger `round3.phases.P1.found_in_P1`; critic C13/C14)

| ID | Sev | Where | Symptom (measured) |
|---|---|---|---|
| T6 | low | `tests/029_FixtureAutoRestoreRegression.sh` | Each run leaves +2 `tmp.*` dirs: `_KT_TMPDIR="$(mktemp -d)"` in two `$( )` blocks is not in `_KT_CREATED_TMPDIRS` (Git-bash /tmp on 5.2, `C:\bin\msys64\tmp` on 5.3). (C13) Worse: the inner `kt_fixture_teardown` inherits the OUTER `_KT_CREATED_TMPDIRS` (a relative `./.tmp/<Name>.<file>`) and deletes the outer fixture dir mid-test (`critic4/t6/inner.sh`: "OUTER DIR REMOVED"). Census (read-only, 2026-10-05): Git-bash /tmp (= `C:\Users\1\AppData\Local\Temp`) 372 `tmp.*` dirs — 61 hold only `tmp.*_backup_N_N` (029), 310 EMPTY (2026-04..10, not 029's, still appearing), 1 kcl bench tree; msys64 /tmp 159 — 156 only-029, 1 kcl bench tree, 2 kcl tawk/tfind Argv leftovers. No other ktests test escapes teardown with mktemp. |
| T7 | low | `kt_runner_parse_args` | Ends with `export VERBOSITY MODE WORKERS TEST_SELECTION FAILED_TEST_FILES _KT_ASSERT_QUIET_MODE _KTEST_QUIET_MODE`. (C14) On 5.2.37 all 6 scalar names persist after a prefix call, including the function's own assignment (a `MODE=single` prefix leaves `MODE=threaded`); 5.3.9 restores them. Nobody needs the export: the single-test wrapper passes VERBOSITY and both quiet modes explicitly, the threaded runner exports in its own subshell (P1), the master runner forwards `"$@"`, MODE/WORKERS/TEST_SELECTION are reset by every parse, FAILED_TEST_FILES is an array (export is a no-op). A copy without the export line: ktests 389/389 threaded on both bashes and single on 5.2. |

## R4.2 Decisions

| # | Decision |
|---|---|
| DT6 | (supervisor, per C13) T6: inside each of 029's `$( )` blocks set `_KT_CREATED_TMPDIRS=("$_KT_TMPDIR")` (REPLACE, not append), the scratch dir created under the outer fixture dir — measured: no leak, and the restore still yields ORIGINAL; the test's meaning unchanged. One-time cleanup ONLY of `tmp.*` dirs whose every entry matches `tmp.*_backup_N_N` (both /tmp roots), listed in the ledger; the 310 empty dirs and the kcl leftovers are NOT touched (ledger `found_in_round4_critic`, owner of those unknown). |
| DT7 | (supervisor, per C14) T7: drop the export line; callers' contract unchanged. |

## R4.3 Phase

| phase | content | gate |
|---|---|---|
| **P2** | T6 per DT6, T7 per DT7. Red-first, hermetic (a private TMPDIR — something else keeps creating global `tmp.*` dirs): 029 leaves the private TMPDIR empty and the outer fixture dir still exists after the inner blocks (both bashes); per parse_args name a prefix assignment does not persist on 5.2 and 5.3, and no `-x` attribute is added after a plain call; sequential, threaded and single modes still work | ktests suite both bashes (`--mode single` on 5.2); master sweep 0 [FAIL], identical per-suite totals except ktests |

**P2 DONE 2026-10-05 (uncommitted, awaiting review).** T6: 029 scratch dir + restored files under the
outer fixture dir, list REPLACED per block; +2 asserts (inner dir removed by its own teardown; outer
dir intact). Red (private TMPDIR, standalone): 2 FAIL + 2 leaked dirs on both bashes → 4/4, TMPDIR
empty. One-time cleanup: 62 (Git-bash /tmp) + 156 (msys64 /tmp) all-`tmp.*_backup_N_N` dirs removed;
310 empty dirs and the kcl leftovers untouched. T7: export line dropped; new
`tests/039_ParseArgsNoExport.sh` (8 asserts) red 8 FAIL on 5.2 / 2 FAIL on 5.3 → 8/8.
**Review remark R1** (ledger `round4.phases.P2.review_remark_R1`): 022's "non-existent file" assert
failed on every run since round 3 T4b (a missing file counts 1:0:1) but was invisible — 022 zeroed
its own counters six times mid-file. Fixed: runner calls run through a subshell helper (`kt022_run`)
with exact counts, T4b contract checked in sequential and threaded. Same pattern fixed in 013, 014,
015, 016 (counter checks in subshells; 015's double passes dropped). Red: a FAIL injected after
`kt_test_init` vanished from the suite totals in all five files → now counted on both bashes.
Per-file totals 013 1→4, 014 1→10, 015 16→25, 016 0→4, 022 3→14. ktests 435/435 threaded on 5.2.37
and 5.3.9, `--mode single` on 5.2.37. Found outside: 017 double pass (ledger `found_in_P2`).

## R4.4 Critic record (2026-10-05)

C13 (T6: inner teardown deletes the outer fixture dir; census corrects the plan's "~150
since 2026-04": 61 + 156 029 dirs, 310 empty dirs of unknown origin), C14 (T7: drop the
export, measured). Probes: `scratchpad/critic4/{t6,t7}/`.

# Round 5 (2026-10-15) — ktests leftovers and machine hygiene

**Status: DONE 2026-10-17 (committed, not pushed) — P3 (T8-T11, E1; review rounds R1-R8, N1-N6), 042/044 group-stop root cause (cygwin loses a group signal for a member in exec handover → TERM once + KILL after grace), P3b stray-process guard (tools/strays.sh + master-sweep check; critic rounds F1-F13, N1-N3); forkstorm workers die with their owner. Master sweep 5.2 8780 / 5.3 8781, 30/30, no leftovers. Ledger `round5`.**
Owner 2026-10-15: "Приступай к оставшимся пунктам". Runs FIRST in round 5 (before
kklass P13–P15 — `kklass/PLAN.md` "Round 5"). Ledger key `round5`.

## R5.1 Findings

| ID | Sev | Where | Symptom |
|---|---|---|---|
| T8 | low | `tests/017_AdvancedFileSystemAssertions.sh` 'File assertions with symbolic links' (~101–117) | STANDALONE only (`KK_OUTPUT_COUNTS=1 bash tests/017_….sh` → `__COUNTS__:13:14:0`; under the runner 13/13): `$(dirname "$0")` is relative, so the fixture dir is relative and MSYS `ln -s` (copy mode) resolves the relative target from the link's folder → both attempts fail → the fallback passes and the final if/else passes again. The final if/else passes in BOTH branches, so the test can never fail. 159 test files pass a relative `$(dirname "$0")` to `kt_test_init` (critic C1). |
| T9 | medium | `ktest_runner.sh:762` | `results_dir=$(mktemp -d)` — default `tmp.XXXXXXXXXX` name in the real TMPDIR, removed only at `:867`, no trap. A killed/timed-out threaded run leaks it with `*.sh.result` files (reproduced both bashes; live /tmp holds three such dirs from 10-09/10-14). bash 5.2 does NOT run an EXIT trap on SIGTERM (0/4 variants; 5.3 3/4), so `ktests.sh:76`'s EXIT-only trap is not enough (critic C2, C8). |
| T10 | low | legacy fixture dirs | 21 old dirs (≤ 2026-09-06) + 3 empty bases (`kcl/tcustomapplication/.tmp`, `kcl/tstringlist/.tmp`, `ktests/.tmp`) — all from kklass tests 119/121/123–126 run by the pre-e4dfd8c runner (`$0="bash"` → cwd-relative base). Root cause already fixed; the current runner from a neutral cwd leaves nothing (critic C6). |
| T11 | medium | `kcl/tstringhelper/tests/{001,008,015,027,028,059,060,061}` | ACTIVE leak: `mkdir -p "$SCRIPT_DIR/.tmp/<file>"` (`001_Chars.sh:21-22`), never removed; the runner's sweep (`:657`) does not match the names; 8 dirs in the tree, recreated every run (critic C6). |
| E1 | low | machine /tmp | 311 `tmp.*` dirs are NOT born empty: modify time ≈ birth + 7 days in single-second clusters (56 @ 07-16 21:01:11, 40 @ 07-20 23:08:28, …) — a Windows Temp cleaner emptied them. They were leaked non-empty dirs (T9-shaped: killed/timed-out runs during dev bursts); content gone → unattributable (list: `scratchpad/critic_r5c/empties.txt`). `big/` = `kcl/tfind/bench.sh` (EXIT trap only). `Argv` dirs in msys64 /tmp predate tsed's first commit → a session probe, not kbool code. 5 `.math_fe_<pid>.awk` + `prog.awk` in msys64 /tmp: `kcl/math/math.sh:755`, removed only on the normal path. Other bare `mktemp -d`: `kklass_compiler.sh:133` (leaks if the unit exits at `:148`), 8 kcl `bench.sh`, `kklass/examples/43:188`, `45:9`, test-generated scripts in kcl tdirectory 032/036, tfile 039/043 (critic C2, C7). A clean instrumented sweep of 27 suites leaks nothing to TMPDIR/HOME/cwd (critic C9). |

## R5.2 Decisions

| # | Decision |
|---|---|
| DT8 | (supervisor, amended by C1) T8: the fixture base is made ABSOLUTE once in `kt_fixture_setup`/`kt_test_init` (fixes all 159 callers); 017's symlink test does exactly one pass/fail, and when symlinks are unavailable it is an explicit skip (or a single pass with a "symlinks unavailable" note if ktests has no skip) — never pass-then-pass. Standalone and runner counts must agree. |
| DT9 | (supervisor, amended by C2/C8) T9: results_dir lives under `$KT_ISO_ROOT` with a named template, so the dead-pid sweep at `kt_runner_iso_begin` (`:507-516`) removes it after a kill; the runner and `ktests.sh` add TERM/INT/HUP traps that clean up and exit with 128+signal (EXIT alone is not run on SIGTERM in 5.2). |
| DT10 | (supervisor, amended by C6) T10: no test change (root cause fixed in e4dfd8c); delete the 21 legacy dirs and the 3 empty bases once (the unrelated 2025-12 `benchmark_*.sh`/`test_*.sh` in `kbool/.tmp`: list for the owner, do not delete). |
| DT11 | (supervisor, C6) T11: the 8 tstringhelper tests use `kt_fixture_tmpdir_create`; the 8 dirs are deleted. |
| DE1 | (owner 2026-10-15, refined by C7) E1: every kbool `mktemp -d`/temp file gets a named template (`kbool.*`/`kt_*`/unit-prefixed) and a cleanup that also runs on TERM/INT/HUP (bench.sh ×8, compiler `:133`, examples 43/45, math engine prog file — or the math prog file is swept by dead pid at the next engine start); delete ONLY what is proven kbool's: the T9 `tmp.*` dirs whose content is `*.sh.result`, `big/d1/d2/d3` trees, `.math_fe_<dead pid>.awk`. The 311 emptied `tmp.*` dirs (content gone, unattributable) and the `Argv`/`prog.awk` probe leftovers go to the OWNER as a list — not deleted by us. |

## R5.3 Phase

| phase | content | gate |
|---|---|---|
| **P3** | T8 (DT8), T9 (DT9), T10 (DT10), T11 (DT11), E1 (DE1) | ktests suite both bashes; 017 standalone = runner counts; a KILL scenario (threaded suite, a bench, a math-using test killed with TERM) then the next run leaves 0 new `tmp.*`/`kt_*`/`.math_fe_*`/`big/`; a full master sweep both bashes leaves no new entries in TMPDIR, HOME, cwd and no new `*/tests/.tmp/*` outside the runner's swept names (counted before/after); totals unchanged except new tests |

Critic (2026-10-16, `scratchpad/critic_r5c/REPORT.md`): C1 (T8 standalone-only, absolute base), C2/C8 (T9 = the `tmp.*` source, 5.2 SIGTERM skips EXIT), C6 (T10 root cause fixed; T11 live leak), C7 (E1 dirs emptied by a cleaner — unattributable), C9 (gate needs a kill scenario and a `tests/.tmp` check).

# Round 6 (2026-10-17)

**Status: P4 + review rounds DONE + COMMITTED 2026-10-19 (sweep 8932/8933) (+ critic r6b round: owner mark as sibling `<dir>.owner`, docs) — S1 per DT12 narrowed to the pipe fork (F4), S2 per-run fixture dirs (DT13), S3 standalone exit code (DT14); tests 045 +5 cases, NEW 046, 047, red first; research `scratchpad/research_r6/REPORT.md`.**
The kklass items are planned in `kklass/PLAN.md` "Round 6". Ledger key `round6`.

## R6.1 Findings

| ID | Sev | Where | Symptom |
|---|---|---|---|
| S1 | low | `tools/strays.sh:288-302` (`_kt_strays_self_chain`), marker rule `:254-281` | `strays.sh list --all` lists one extra live row when its output is piped (`… \| while read`, `{ cat; }`, under `timeout`; `\| tail` sometimes): the fork made for the other side of the pipe still carries the caller tool shell's command line (repo path followed by space / `/` / `\` / end), is a SIBLING of strays.sh (not an ancestor), so the self-chain misses it and the repo-path marker matches. Never stopped (ORPHAN=no), but breaks the "list --all = none" check. |
| S2 | low | `ktest_fixtures.sh:76-84` (`kt_fixture_init_tmpdir`), `ktest_runner.sh:1018-1033` (leftover sweep) | (P4 critic F5, real defect) the fixture dir `tests/.tmp/<Test>.<file>` had no per-run part: a second run's setup wiped the first run's LIVE dir as "stale", and the runner swept `.tmp/*.<file>` of a run still at work — two concurrent runs of one file or one suite destroyed each other's dirs (critic: two concurrent `bash 027_….sh` → FAIL 2/3). |
| S3 | info | `ktest.sh` `kt_test_init` (standalone EXIT trap) | (P4 critic info) a standalone test file exited 0 even with a `[FAIL]`; only the runner judged. |
| O2 | done | machine /tmp | 2026-10-17 (owner): the 311 EMPTY `tmp.*` dirs in Git-bash /tmp were deleted one by one (each verified empty); the msys64 /tmp `Argv` probe dirs and `prog.awk` deleted. Both /tmp roots now hold 0 `tmp.*`. |

## R6.2 Decision

| # | Decision |
|---|---|
| DT12 | (owner 2026-10-17) S1: exclude un-started copies of the caller's own shells — a child of the caller's self-chain whose command line equals its parent's is excluded (one line in the roots loop; scan cost noise, 1.52 → 1.64 ms); test 045 case with the piped shapes. **Narrowed in the P4 review (F4):** the rule also hid the caller's OWN live `{ …; } &` / `( … ) &` job (same command line, child of the self chain); now only the fork whose fd 0 is the same pipe as strays.sh's fd 1 (`-p` + `-ef` on `/proc/P/fd/0`, no fork) is excluded; 045: the own jobs ARE listed. |
| DT13 | (owner 2026-10-18) S2: concurrent runs must be safe — per-run fixture dirs `<Test>.<file>.<pid>` with an owner mark (the runtime) in the SIBLING file `<dir>.owner` — the fixture dir starts empty (critic r6b; the first draft put `.kt_owner` inside it); setup and the runner's sweep remove only a dir whose owner is gone (`kt_fixture_stale_dir`: the kt_iso dead-pid rules, incl. the 1-day age guard for the other runtime / an unmarked dir); the runner's leftover WARN kept. Test 046: concurrent standalone runs and concurrent suite runs (single, threaded) both pass and leave nothing. |
| DT14 | (owner 2026-10-18) S3: a standalone test file exits 1 when any test in it failed (a non-zero status of its own is kept); the runner keeps judging by its counts line. Test 047: standalone rc vs runner verdict, incl. a file whose last test passes after an earlier FAIL. |

## R6.3 Phase

| phase | content | gate |
|---|---|---|
| **P4** | S1 (DT12) | 045 both bashes (new piped-caller case red first); ktests suite both bashes; `strays.sh list --all \| while read` shows none from a Bash-tool-shaped caller |
| **P4 review** | F4 (DT12 narrowed), S2 (DT13), S3 (DT14) — developed in a private copy of the five repos, applied to the live tree in one step | red first both bashes (045 own-jobs case, 046, 047); 045 x3 + ktests suite threaded and single both bashes; kklass suite both bashes; the concurrent-run test 046 |
| **P4 review 2** | critic r6b: owner mark moved out of the fixture dir (sibling `<dir>.owner`); docs: sourced test file EXIT trap / exit status, threaded `BASH_FUNC_*` exports — private copy, applied in one step | 046 (new empty-dir case red first) + 045/047; ktests suite threaded and single both bashes; kklass suite both bashes; every timeout `-k 30` |
| **P4 sweep flake** | 046 failed once in the 5.2 full-load master sweep (a runner WARN for a hold dir that outlived its owner): root cause = teardown `rm -rf` failing silently on a native handle without FILE_SHARE_DELETE (virus scanner) — not an isolation bug; teardown now retries (10 × 0.3 s), 046 got an isolation witness + a retry case | 046 red first (retry case) both bashes; 046 x10 under a fork storm both bashes; ktests suite threaded and single both bashes |
