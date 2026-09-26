#!/bin/bash
# ForkStormHarness — tools/forkstorm.sh, the load generator for timing tests.
#
# A timing assertion with a fork inside its window is only as stable as the
# slowest fork, and on MSYS/cygwin concurrent forking (the threaded runner)
# stretches forks from ~15 ms to ~280 ms and beyond. tools/timing_check.sh
# reproduces that with a FORK storm; this file pins the storm's own contract:
# the workers really run and really fork, a second storm is refused while one
# is alive, and a stop leaves NOTHING behind — no worker pid alive and no
# process in /proc carrying the storm's marker (a worker's in-flight `$( )`
# child carries it too). The storm here is 2 tiny workers for about a second.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ForkStormHarness" "$SCRIPT_DIR" "$@"

FS="$KTESTS_LIB_DIR/tools/forkstorm.sh"
source "$FS"

TMP="$(kt_fixture_tmpdir)"
HB="$TMP/heartbeat"
mkdir -p "$HB"

# Whatever happens below, the storm must not outlive this file.
fs033_cleanup() { kt_storm_stop >/dev/null 2>&1 || :; }
kt_fixture_cleanup_register fs033_cleanup

# Another storm may legitimately be running (someone measuring this very suite
# under timing_check.sh); this file checks ITS OWN storm by tag.
export KT_STORM_ALLOW_OVERLAP=1

kt_test_start "kt_storm_start 2 starts two live workers"
KT_STORM_FUNCS=10 KT_STORM_HEARTBEAT="$HB" kt_storm_start 2; rc=$?
kt_storm_alive; alive=$RESULT
if (( rc == 0 && ${#KT_STORM_PIDS[@]} == 2 && alive == 2 )) && [[ -n "$KT_STORM_TAG" ]]; then
    kt_test_pass "tag $KT_STORM_TAG, pids ${KT_STORM_PIDS[*]}"
else
    kt_test_fail "rc=$rc pids=(${KT_STORM_PIDS[*]}) alive=$alive tag='$KT_STORM_TAG'"
fi

kt_test_start "both workers have forked (each touched its heartbeat after its first \$( ))"
for (( i = 0; i < 300; i++ )); do
    n=0
    for p in "${KT_STORM_PIDS[@]}"; do [[ -e "$HB/$p" ]] && n=$(( n + 1 )); done
    (( n == ${#KT_STORM_PIDS[@]} )) && break
    sleep 0.1
done
hbs=( "$HB"/* )
if (( n == 2 )); then
    kt_test_pass "heartbeats from ${KT_STORM_PIDS[*]} after ~$(( i / 10 )).$(( i % 10 )) s"
else
    kt_test_fail "only $n of 2 heartbeats after 30 s: ${hbs[*]##*/}"
fi

kt_test_start "the workers are visible in /proc under the storm's marker"
kt_storm_scan "$KT_STORM_TAG"
if (( RESULT >= 2 )); then
    kt_test_pass "$RESULT process(es) carry forkstorm-worker:$KT_STORM_TAG"
else
    kt_test_fail "only $RESULT process(es) carry the marker"
fi

kt_test_start "a second storm is refused while this one runs, and starts nothing"
second="$(
    KT_STORM_PIDS=(); KT_STORM_TAG=""
    KT_STORM_ALLOW_OVERLAP=0 kt_storm_start 1 2>/dev/null; src=$?
    started=${#KT_STORM_PIDS[@]}
    kt_storm_stop >/dev/null 2>&1 || :        # never leak, even if the guard failed
    printf 'rc=%s started=%s' "$src" "$started"
)"
if [[ "$second" == "rc=1 started=0" ]]; then
    kt_test_pass "$second"
else
    kt_test_fail "$second"
fi

kt_test_start "kt_storm_stop leaves no worker alive and no marked process in /proc"
tag="$KT_STORM_TAG"
pids=( "${KT_STORM_PIDS[@]}" )
kt_storm_stop; rc=$?
still=0
for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && still=$(( still + 1 )); done
kt_storm_scan "$tag"
if (( rc == 0 && still == 0 && RESULT == 0 && ${#KT_STORM_PIDS[@]} == 0 )) && [[ -z "$KT_STORM_TAG" ]]; then
    kt_test_pass "rc 0; pids ${pids[*]} gone; 0 marked processes"
else
    kt_test_fail "rc=$rc alive=$still marked=$RESULT pids-left=(${KT_STORM_PIDS[*]}) tag='$KT_STORM_TAG'"
fi

kt_test_start "the CLI start returns at once (workers hold no stdout), status sees it, stop cleans up"
ST="$TMP/storm.pids"
cli_out="$(timeout 60 "$BASH" "$FS" start 1 --state "$ST" 2>&1)"; crc=$?
cli_tag=""; [[ -f "$ST" ]] && read -r cli_tag < "$ST"
status_out="$(timeout 60 "$BASH" "$FS" status --state "$ST" 2>&1)"
stop_out="$(timeout 60 "$BASH" "$FS" stop --state "$ST" 2>&1)"; src=$?
left=-1; [[ -n "$cli_tag" ]] && { kt_storm_scan "$cli_tag"; left=$RESULT; }
if (( crc == 0 && src == 0 && left == 0 )) && [[ -n "$cli_tag" && ! -e "$ST" \
      && "$status_out" == *"1 of 1 worker(s) alive"* ]]; then
    kt_test_pass "start rc 0, status '1 of 1 alive', stop rc 0, 0 marked processes left"
else
    kt_test_fail "start rc=$crc '$cli_out'; status '$status_out'; stop rc=$src '$stop_out'; left=$left state-file=$([[ -e "$ST" ]] && echo kept || echo gone)"
fi

kt_test_log "033_ForkStormHarness.sh completed"
