#!/bin/bash
# Unit tests: Test runner argument parsing

source "$(cd "$(dirname "$0")/.." && pwd)/ktest.sh"

kt_test_init "TestRunnerParsing" "$(dirname "$0")"

# Test verbosity flag parsing
export VERBOSITY=""

kt_test_start "Parse --verbosity=info option"
kt_runner_parse_args --verbosity=info
if [[ "$VERBOSITY" == "info" ]]; then
    kt_test_pass "--verbosity=info parsed correctly"
else
    kt_test_fail "--verbosity=info not parsed correctly"
fi

# Test mode flag parsing
kt_test_start "Parse --mode=single option"
kt_runner_parse_args --mode=single
if [[ "$MODE" == "single" ]]; then
    kt_test_pass "--mode=single parsed correctly"
else
    kt_test_fail "--mode=single not parsed correctly"
fi

# Test workers flag parsing
kt_test_start "Parse --workers=4 option"
kt_runner_parse_args --workers=4
if [[ "$WORKERS" == "4" ]]; then
    kt_test_pass "--workers=4 parsed correctly"
else
    kt_test_fail "--workers=4 not parsed correctly"
fi


