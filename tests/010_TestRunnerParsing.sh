#!/bin/bash
# Unit tests: Test runner argument parsing

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "TestRunnerParsing" "$(dirname "$0")"

# Test verbosity flag parsing
export VERBOSITY=""

kk_test_start "Parse --verbosity=info option"
kk_runner_parse_args --verbosity=info
if [[ "$VERBOSITY" == "info" ]]; then
    kk_test_pass "--verbosity=info parsed correctly"
else
    kk_test_fail "--verbosity=info not parsed correctly"
fi

# Test mode flag parsing
kk_test_start "Parse --mode=single option"
kk_runner_parse_args --mode=single
if [[ "$MODE" == "single" ]]; then
    kk_test_pass "--mode=single parsed correctly"
else
    kk_test_fail "--mode=single not parsed correctly"
fi

# Test workers flag parsing
kk_test_start "Parse --workers=4 option"
kk_runner_parse_args --workers=4
if [[ "$WORKERS" == "4" ]]; then
    kk_test_pass "--workers=4 parsed correctly"
else
    kk_test_fail "--workers=4 not parsed correctly"
fi


