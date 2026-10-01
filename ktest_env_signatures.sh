#!/bin/bash
# ktest_env_signatures.sh - the ONE definition of the cygwin fork-failure
# signatures ("ENV": the machine failed, not the test).
#
# Seen on MSYS2/cygwin under a system commit limit (0xC000012D is
# STATUS_COMMITMENT_LIMIT, 0xC0000142 a DLL init failure of the new process).
# Used by:
#   - ktest_runner.sh: a file that left no END marker and no counts line is
#     re-run only when its capture is empty or matches this regex (ktests fix
#     plan T1, PLAN.md §2.5);
#   - tools/timing_check.sh: a run whose output matches it is ENV.
# Kept dependency-free so a standalone tool can source it.

declare -g KT_ENV_FORK_FAILURE_RE='dofork:|child_copy:|cygheap read copy failed|0xC000012D|0xC0000142|Resource temporarily unavailable|fork: retry'
