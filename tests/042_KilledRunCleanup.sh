#!/bin/bash
# KilledRunCleanup (ktests round 5, T9 / DT9, 2026-10-16; review R1/R6/R7).
#
# The threaded runner kept its result files in a bare `mktemp -d` (a default
# `tmp.XXXXXXXXXX` in the real TMPDIR) removed only on the normal path, and
# ktests.sh had an EXIT trap only — which bash 5.2 does not run on SIGTERM. A
# killed or timed-out run left a `tmp.*` dir of `*.sh.result` files behind (the
# source of the machine's `tmp.*` litter). Now:
#   - the results dir lives under the run's isolation folder $KT_ISO_ROOT
#     (kt_iso.<pid>), or is named kt_iso.<pid>.results.* without one, so the
#     dead-pid sweep of the next run removes it even after a SIGKILL;
#   - ktests.sh and the threaded runner trap TERM/INT/HUP: clean up, exit 128+N.
#   - R1: the work runs in a background process group the runner `wait`s on, so
#     a TERM to the runner's pid ALONE stops it at once (a trap is deferred
#     while a foreground child runs) and kills its workers and test files.
#   - R6: a test file whose result file is missing counts 1:0:1 and is FAILED
#     (a vanished results dir is never a silent green); the dead-pid sweep
#     leaves the kt_iso.* of ANOTHER bash install (an owner marker; another
#     MSYS runtime cannot see this one's pids) until it is a day old.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "KilledRunCleanup" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"

# kt042_suite DIR SECONDS [PIDFILE] — a 4-file suite whose files sleep SECONDS
# each; with PIDFILE every file appends "<its shell pid> <its sleep pid>"
kt042_suite() {
    local d="$1" s="$2" pf="${3:-}" n body
    mkdir -p "$d"
    printf '%s\n' '#!/bin/bash' \
        'D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' \
        "\"$LIB/ktests.sh\" \"\$D\" \"Kill\" '/[0-9][0-9][0-9]_' \"\$@\"" > "$d/tests.sh"
    if [[ -n "$pf" ]]; then
        body="sleep $s & echo \"\$BASHPID \$!\" >> '$pf'; wait"
    else
        body="sleep $s"
    fi
    for n in 001 002 003 004; do
        printf '%s\n' \
            "source \"$LIB/ktest.sh\"" \
            "kt_test_init \"K$n\" \"\$(dirname \"\$0\")\"" \
            "kt_test_start \"k$n\"" \
            "$body" \
            "kt_test_pass \"k$n\"" > "$d/${n}_k.sh"
    done
}
kt042_suite "$TMP/slow" 20
kt042_suite "$TMP/fast" 0
kt042_suite "$TMP/slowp" 20 "$TMP/pids"

# kt042_left DIR — the entries in DIR, space-separated
kt042_left() {
    local e out=""
    for e in "$1"/* "$1"/.[!.]*; do
        [[ -e "$e" ]] && out+="${e##*/} "
    done
    printf '%s' "${out% }"
}

# kt042_poll SECONDS CMD... — run CMD every 0.1 s until it succeeds; rc 1 on timeout
kt042_poll() {
    local n=$(( $1 * 10 )) i; shift
    for (( i = 0; i < n; i++ )); do "$@" && return 0; sleep 0.1; done
    return 1
}
kt042_has_results() { local d; for d in "$1"/kt_iso.*/results.*; do [[ -d "$d" ]] && return 0; done; return 1; }
kt042_dead() { ! kill -0 "$1" 2>/dev/null; }
kt042_all_dead() { local p; for p in $(<"$1"); do kill -0 "$p" 2>/dev/null && return 1; done; return 0; }
# kt042_alive PIDFILE — the live pids of PIDFILE ("<shell pid> <sleep pid>" per
# line), each as pid:role:state:ppid:pgid:cmdline (ppid 1 = its parent is gone)
kt042_alive() {
    local sh sl p role st pp pg c out=""
    while read -r sh sl; do
        for p in "$sh" "$sl"; do
            kill -0 "$p" 2>/dev/null || continue
            role=file-shell; [[ "$p" == "$sl" ]] && role=sleep
            st="?" pp="?" pg="?"; read -r _ _ st pp pg _ < "/proc/$p/stat" 2>/dev/null
            c="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)"
            out+="$p:$role:$st:pp$pp:pg$pg:${c% } "
        done
    done < "$1"
    printf '%s' "${out% }"
}
kt042_npids() { local n=0 l; [[ -f "$1" ]] && while IFS= read -r l; do n=$(( n + 1 )); done < "$1"; (( n >= $2 )); }

kt_test_start "a threaded run killed with TERM leaves nothing in TMPDIR [T9]"
mkdir -p "$TMP/t1"
# ktests.sh itself under timeout: a suite's tests.sh wrapper dies on TERM at
# once and timeout returns while ktests.sh is still cleaning up
rc=0
TMPDIR="$TMP/t1" timeout -s TERM --preserve-status 4 bash "$LIB/ktests.sh" "$TMP/slow" Kill '/[0-9][0-9][0-9]_' -m threaded -w 4 >/dev/null 2>&1 || rc=$?
left="$(kt042_left "$TMP/t1")"
if [[ -z "$left" && "$rc" == 143 ]]; then
    kt_test_pass "rc=$rc, TMPDIR empty"
else
    kt_test_fail "rc=$rc left=[$left]"
fi

kt_test_start "a threaded run killed with KILL: the next run sweeps everything it left [T9, R7]"
mkdir -p "$TMP/t2"
# its own process group, KILLed as a whole once its results dir exists (no
# fixed delay: under load the run may need long to get there)
set -m
TMPDIR="$TMP/t2" bash "$TMP/slow/tests.sh" -m threaded -w 4 >/dev/null 2>&1 &
kpid=$!
set +m
kt042_poll 60 kt042_has_results "$TMP/t2"; seen=$?
kill -KILL -- -"$kpid" 2>/dev/null; wait "$kpid" 2>/dev/null
left1="$(kt042_left "$TMP/t2")"
TMPDIR="$TMP/t2" bash "$TMP/fast/tests.sh" -m threaded -w 4 >/dev/null 2>&1
left2="$(kt042_left "$TMP/t2")"
if [[ "$seen" == 0 && "$left1" == kt_iso.* && -z "$left2" ]]; then
    kt_test_pass "killed run left [$left1]; next run left nothing"
else
    kt_test_fail "results seen rc=$seen; after kill [$left1] (want kt_iso.<pid> only), after next run [$left2]"
fi

kt_test_start "the threaded runner called without a run folder names its results dir kt_iso.<pid>.results.* [T9]"
mkdir -p "$TMP/t3"
out="$(TMPDIR="$TMP/t3" bash -c '
source "$1/ktest.sh"
unset KT_ISO_ROOT
mktemp() { command mktemp "$@"; local r=$?; ls -A "$TMPDIR" >&2; return $r; }
VERBOSITY=error kt_runner_execute_threaded "$2/001_k.sh" "$2/002_k.sh" >/dev/null
' _ "$LIB" "$TMP/fast" 2>&1)"
left="$(kt042_left "$TMP/t3")"
if [[ "$out" == kt_iso.*.results.* && -z "$left" ]]; then
    kt_test_pass "during the run [$out]; after it nothing"
else
    kt_test_fail "during the run [$out]; after it [$left]"
fi

# ---- R1: TERM to the runner's pid ALONE (not its process group) -------------
for mode in threaded single; do
    want=4; [[ "$mode" == single ]] && want=1
    kt_test_start "$mode: TERM to the runner pid only stops it at once, kills its workers and test files, leaves nothing [R1]"
    mkdir -p "$TMP/t4$mode"; rm -f "$TMP/pids"
    TMPDIR="$TMP/t4$mode" bash "$LIB/ktests.sh" "$TMP/slowp" Kill '/[0-9][0-9][0-9]_' -m "$mode" -w 4 >/dev/null 2>&1 &
    rpid=$!
    kt042_poll 60 kt042_npids "$TMP/pids" "$want"; ready=$?
    # "at once": within 10 s, not after the 20 s files — a TERM lost on the Git
    # runtime (a `sleep` still in its exec) is KILLed after the group grace (3 s
    # threaded, 5 s single: ktests.sh's own group)
    t0=$SECONDS
    kill -TERM "$rpid" 2>/dev/null
    kt042_poll 15 kt042_dead "$rpid"
    dt=$(( SECONDS - t0 ))
    rc=0; wait "$rpid" || rc=$?
    alive=""
    if [[ -f "$TMP/pids" ]]; then
        kt042_poll 10 kt042_all_dead "$TMP/pids"   # a condition, up to 10 s
        alive="$(kt042_alive "$TMP/pids")"
    fi
    left="$(kt042_left "$TMP/t4$mode")"
    if [[ "$ready" == 0 && "$dt" -le 10 && "$rc" == 143 && -z "$alive" && -z "$left" ]]; then
        kt_test_pass "$mode: exit ${dt}s after TERM, rc 143, no orphan, TMPDIR empty"
    else
        # how long does a survivor live on? (diagnosis, never longer than 25 s)
        late=""
        if [[ -n "$alive" ]]; then
            t1=$SECONDS
            kt042_poll 25 kt042_all_dead "$TMP/pids" && late="all gone $(( SECONDS - t1 + 10 ))s after the runner" || late="still alive 35s after the runner"
        fi
        kt_test_fail "$mode: ready=$ready exit after ${dt}s rc=$rc alive=[$alive] ($late) left=[$left]"
    fi
    # never leave an orphan behind, whatever the verdict
    [[ -f "$TMP/pids" ]] && for p in $(<"$TMP/pids"); do kill -KILL "$p" 2>/dev/null; done
done

# ---- R6a: a missing result file is a FAILED file, never a silent green ------
mkdir -p "$TMP/gone"
for n in a b; do
    printf '%s\n' "kt_test_init \"Gone$n\" \"\$(dirname \"\$0\")\"" \
        'kt_test_start "x"; kt_test_pass "x"' \
        'rm -rf -- "$results_dir"' > "$TMP/gone/$n.sh"
done
kt_test_start "the results dir removed during a threaded run: each file counts 1:0:1 and is FAILED by name [R6]"
out="$(cd "$TMP" && TMPDIR="$TMP" bash -c '
source "$1/ktest.sh"
VERBOSITY=error kt_runner_execute_threaded "$2/a.sh" "$2/b.sh"
printf "COUNTS=%s:%s:%s FAILED=%s\n" "$TESTS_TOTAL" "$TESTS_PASSED" "$TESTS_FAILED" "${FAILED_TEST_FILES[*]}"
' _ "$LIB" "$TMP/gone" 2>&1)"
counts="$(printf '%s\n' "$out" | sed -n 's/^COUNTS=//p')"
nmiss="$(printf '%s\n' "$out" | grep -c 'no result file')"
if [[ "$counts" == "2:0:2 FAILED=a.sh b.sh" && "$nmiss" == 2 ]]; then
    kt_test_pass "$counts, $nmiss 'no result file' lines"
else
    kt_test_fail "counts=[$counts] lines=$nmiss out=[${out//$'\n'/ | }]"
fi

# ---- R6b: the sweep and another bash install's run folders -----------------
kt_test_start "the dead-pid sweep: own install swept, another install's kept until a day old, unmarked kept until a day old [R6]"
S="$TMP/t7"; mkdir -p "$S"
d=(); for n in 1 2 3 4 5; do d+=( "$(bash -c 'echo $$')" ); done
mine="$(bash -c 'source "$1/ktest.sh"; kt_runner_iso_owner; printf "%s" "$REPLY"' _ "$LIB")"
mkdir -p "$S/kt_iso.${d[0]}" "$S/kt_iso.${d[1]}" "$S/kt_iso.${d[2]}" "$S/kt_iso.${d[3]}" "$S/kt_iso.${d[4]}.results.abc" "$S/kt_iso.$PPID"
printf '%s\n' "$mine" > "$S/kt_iso.${d[0]}/.kt_owner"
printf '%s\n' "other-install" > "$S/kt_iso.${d[1]}/.kt_owner"
printf '%s\n' "other-install" > "$S/kt_iso.${d[2]}/.kt_owner"
printf '%s\n' "$mine" > "$S/kt_iso.$PPID/.kt_owner"
touch -d '2 days ago' "$S/kt_iso.${d[2]}" "$S/kt_iso.${d[4]}.results.abc"
got="$(
    TMPDIR="$S"
    kt_runner_iso_begin
    kt_runner_iso_end
    cd "$S" && ls -d kt_iso.* 2>/dev/null | sort | tr '\n' ' '
)"
want="$(printf '%s\n' "kt_iso.${d[1]}" "kt_iso.${d[3]}" "kt_iso.$PPID" | sort | tr '\n' ' ')"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "kept: $got"
else
    kt_test_fail "got '$got' want '$want'"
fi

kt_test_start "the owner marker is the pid namespace only: the same for /bin/bash and /usr/bin/bash, no version or path in it [N3]"
m1="$(/usr/bin/bash -c 'source "$1/ktest.sh"; kt_runner_iso_owner; printf "%s" "$REPLY"' _ "$LIB" 2>&1)"
m2="$(/bin/bash -c 'source "$1/ktest.sh"; kt_runner_iso_owner; printf "%s" "$REPLY"' _ "$LIB" 2>&1)"
if [[ -n "$m1" && "$m1" == "$m2" && "$m1" != *"|"* && "$m1" != *"$BASH_VERSION"* ]]; then
    kt_test_pass "marker '$m1'"
else
    kt_test_fail "/usr/bin/bash '$m1' vs /bin/bash '$m2'"
fi

kt_test_log "042_KilledRunCleanup.sh completed"
