#!/usr/bin/env bash
# GroupWatchBackend (launch L5.9): how a run group's watchdog learns that its
# runner died. kt_runner_group_backend picks `coproc` on cygwin (Git-bash,
# MSYS2: a read-write open of a fresh FIFO can spin there for ever, deaf to
# every signal - diag D11) and `fifo` elsewhere; KT_RUNNER_WATCH=fifo|coproc
# forces one (the seam). kt_runner_group_spawn starts the group either way
# with the same protocol: the runner holds the only writer, a normal end
# writes "done" (the watchdog leaves, nothing of the group is touched), a
# SIGKILLed runner gives EOF (the watchdog ends its group). Both backends are
# checked on Linux/macOS/BSD; on cygwin only coproc groups are started (the fifo
# cases SKIP: a FIFO group start can wedge there). Each child runs under
# `timeout` where there is one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GroupWatchBackend" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
KT060_TMO=(); kt_need_timeout && KT060_TMO=( "$KT_TIMEOUT" 60 )
# no FIFO group is started on cygwin: there its read-write open can wedge
# for ever (the reason for the coproc backend) - the fifo cases SKIP there
KT_CYGWIN=0; [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]] && KT_CYGWIN=1

# kt060_backend [NAME=VALUE...] - REPLY = kt_runner_group_backend's REPLY in a
# fresh bash with KT_RUNNER_WATCH removed, then NAME=VALUE set
kt060_backend() {
    REPLY="$(env -u KT_RUNNER_WATCH -u KTESTS_LIB_DIR "$@" bash -c \
        'source "$1/ktest.sh"; kt_runner_group_backend; printf "%s" "$REPLY"' _ "$LIB" 2>&1 </dev/null)"
}

kt_test_start "kt_runner_group_backend: coproc on cygwin (Git-bash, MSYS2), fifo elsewhere; KT_RUNNER_WATCH=fifo|coproc forces it, another value is ignored [L5.9]"
want=fifo; [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]] && want=coproc
kt060_backend; d="$REPLY"
kt060_backend KT_RUNNER_WATCH=fifo; f="$REPLY"
kt060_backend KT_RUNNER_WATCH=coproc; c="$REPLY"
kt060_backend KT_RUNNER_WATCH=pipe; x="$REPLY"
if [[ "$d" == "$want" && "$f" == fifo && "$c" == coproc && "$x" == "$want" ]]; then
    kt_test_pass "default $d ($OSTYPE), forced fifo/coproc: $f/$c, bogus: $x"
else
    kt_test_fail "default [$d] (want $want), forced fifo [$f] coproc [$c], bogus [$x] (want $want)"
fi

# The normal end: the group leaves a background process behind; the runner
# waits for the leader (bash reaps a coproc and closes its fds then), writes
# "done" through its own writer (kt_runner_group_close). The watchdog must
# take that as "done", not as a dead runner: the leftover is still alive 1.5 s
# later (the stray check names it, not the watchdog). The group's stdout
# reaches the runner's stdout; a FIFO exists only for the fifo backend.
for be in fifo coproc; do
    kt_test_start "$be: kt_runner_group_spawn - a normal end is 'done' (a leftover of the group is not touched), stdout passes, stdin is /dev/null, the group leads its own process group, FIFO only for fifo [L5.9]"
    if [[ "$be" == fifo ]] && (( KT_CYGWIN )); then kt_test_pass "SKIP: the FIFO backend wedges on cygwin (L5.9); covered on Linux/macOS/BSD"; continue; fi
    rm -f "$TMP/n.$be".*
    out="$(KT_RUNNER_WATCH=$be "${KT060_TMO[@]}" bash -c '
source "$1/ktest.sh"
t="$2"
pgid() { local l x; if [[ -r /proc/$1/pgid ]]; then read -r l < "/proc/$1/pgid"; echo "$l"
         elif [[ -r /proc/$1/stat ]]; then read -r l < "/proc/$1/stat"; x=( ${l##*) } ); echo "${x[2]}"
         else ps -o pgid= -p "$1" | tr -d " "; fi; }
body() {
    sleep 30 & echo "$!" > "$t.left"
    read -r -t 2 x; echo "stdin rc=$?"
    [[ "$(pgid "$BASHPID")" == "$BASHPID" ]] && echo "leads its group" || echo "pgid $(pgid "$BASHPID") != $BASHPID"
    echo "body says hi"; exit 7
}
set -m
kt_runner_group_spawn "$t.fifo" "" body
p="$_KT_GROUP_PID" w="$_KT_GROUP_WFD"
set +m
fe=no; [[ -p "$t.fifo" ]] && fe=yes
wait "$p"; rc=$?
kt_runner_group_close "$w"
sleep 1.5
l="$(cat "$t.left" 2>/dev/null)"
a=gone; [[ -n "$l" ]] && kill -0 "$l" 2>/dev/null && a=alive
[[ -n "$l" ]] && kill -KILL "$l" 2>/dev/null
echo "rc=$rc w=${w:+set} fifo=$fe leftover=$a"
' _ "$LIB" "$TMP/n.$be" 2>"$TMP/n.$be.err" </dev/null)"
    err="$(cat "$TMP/n.$be.err" 2>/dev/null)"
    wantfe=no; [[ "$be" == fifo ]] && wantfe=yes
    if [[ "$out" == *"body says hi"* && "$out" == *"stdin rc=1"* && "$out" == *"leads its group"* && "$out" == *"rc=7 w=set fifo=$wantfe leftover=alive"* && -z "$err" ]]; then
        kt_test_pass "$be: [${out//$'\n'/ | }]"
    else
        kt_test_fail "$be: out [${out//$'\n'/ | }] (want body says hi, stdin rc=1 (/dev/null: EOF at once), leads its group, rc=7 w=set fifo=$wantfe leftover=alive), stderr [$err]"
    fi
done

# The group (its watchdog with it) killed from outside while the runner waits:
# the runner's "done" then goes to a pipe without a reader - it must not die of
# SIGPIPE (the coproc backend; a FIFO opened read-write has the runner as a
# reader itself), it goes on past kt_runner_group_close. SIGPIPE at its default.
for be in fifo coproc; do
    kt_test_start "$be: the group killed from outside - the runner's kt_runner_group_close survives (no SIGPIPE) [L5.9]"
    if [[ "$be" == fifo ]] && (( KT_CYGWIN )); then kt_test_pass "SKIP: the FIFO backend wedges on cygwin (L5.9); covered on Linux/macOS/BSD"; continue; fi
    rm -f "$TMP/x.$be".*
    out="$(KT_RUNNER_WATCH=$be "${KT060_TMO[@]}" bash -c '
trap - PIPE
source "$1/ktest.sh"
body() { sleep 30; }
set -m
kt_runner_group_spawn "$2.fifo" "" body
p="$_KT_GROUP_PID" w="$_KT_GROUP_WFD"
set +m
sleep 0.5
kill -KILL -- "-$p" 2>/dev/null
wait "$p"
sleep 0.3
kt_runner_group_close "$w"
echo "after close"
exit 0
' _ "$LIB" "$TMP/x.$be" 2>&1 </dev/null)"; rc=$?
    if [[ "$rc" == 0 && "$out" == *"after close"* ]]; then
        kt_test_pass "$be: rc 0, [${out//$'\n'/ | }]"
    else
        kt_test_fail "$be: rc=$rc (141 = SIGPIPE), out [${out//$'\n'/ | }]"
    fi
done

# The coproc writer's close puts the caller's own PIPE trap back exactly; a
# runner whose stdout is closed gives the group /dev/null as stdout (the group
# writes a lot and still ends - no pipe that nobody reads).
kt_test_start "coproc: kt_runner_group_close restores the caller's PIPE trap; a closed runner stdout gives the group /dev/null [L5.9]"
out="$(KT_RUNNER_WATCH=coproc "${KT060_TMO[@]}" bash -c '
source "$1/ktest.sh"
trap ": mine" PIPE
body() { :; }
set -m
kt_runner_group_spawn "$2.fifo" "" body
p="$_KT_GROUP_PID" w="$_KT_GROUP_WFD"
set +m
wait "$p"
kt_runner_group_close "$w"
echo "trap after: [$(trap -p PIPE)]"
big() { local i; for (( i = 0; i < 20000; i++ )); do echo "line $i of a lot of output"; done; exit 3; }
exec 3>&1 1>&-
set -m
kt_runner_group_spawn "$2.fifo" "" big
p="$_KT_GROUP_PID" w="$_KT_GROUP_WFD"
set +m
wait "$p"; rc=$?
kt_runner_group_close "$w"
echo "closed stdout: rc=$rc" >&3
' _ "$LIB" "$TMP/p.coproc" 2>&1 </dev/null)"
if [[ "$out" == *"trap after: [trap -- ': mine' SIGPIPE]"* && "$out" == *"closed stdout: rc=3"* ]]; then
    kt_test_pass "[${out//$'\n'/ | }]"
else
    kt_test_fail "[${out//$'\n'/ | }] (want trap after: [trap -- ': mine' SIGPIPE], closed stdout: rc=3)"
fi

# A SIGKILLed runner runs no trap: the watchdog sees EOF and ends its group
# (TERM+CONT, KILL after the grace) - the group's sleep is gone.
for be in fifo coproc; do
    kt_test_start "$be: SIGKILL to the runner - the watchdog sees EOF and ends its group [L5.9]"
    if [[ "$be" == fifo ]] && (( KT_CYGWIN )); then kt_test_pass "SKIP: the FIFO backend wedges on cygwin (L5.9); covered on Linux/macOS/BSD"; continue; fi
    rm -f "$TMP/k.$be".*
    n="61.${$}${#be}"
    KT_RUNNER_WATCH=$be "${KT060_TMO[@]}" bash -c '
source "$1/ktest.sh"
body() { sleep "$3" & echo "$!" > "$2.sleep"; wait; }
set -m
kt_runner_group_spawn "$2.fifo" "" body "$@"
set +m
echo "$BASHPID" > "$2.runner"
wait
' _ "$LIB" "$TMP/k.$be" "$n" >/dev/null 2>&1 </dev/null &
bp=$!
    for (( i = 0; i < 300; i++ )); do [[ -s "$TMP/k.$be.sleep" && -s "$TMP/k.$be.runner" ]] && break; sleep 0.1; done
    s="$(cat "$TMP/k.$be.sleep" 2>/dev/null)" r="$(cat "$TMP/k.$be.runner" 2>/dev/null)"
    sleep 0.3
    [[ -n "$r" ]] && kill -KILL "$r" 2>/dev/null
    t0=$SECONDS
    for (( i = 0; i < 150; i++ )); do [[ -n "$s" ]] && kill -0 "$s" 2>/dev/null || break; sleep 0.1; done
    a=gone; [[ -n "$s" ]] && kill -0 "$s" 2>/dev/null && { a=alive; kill -KILL "$s" 2>/dev/null; }
    dt=$(( SECONDS - t0 ))
    kill -KILL "$bp" 2>/dev/null; wait "$bp" 2>/dev/null
    if [[ -n "$s" && -n "$r" && "$a" == gone ]]; then
        kt_test_pass "$be: runner $r KILLed, the group's sleep $s gone ${dt}s later"
    else
        kt_test_fail "$be: runner [$r] sleep [$s] $a ${dt}s after the SIGKILL"
    fi
done

# A real run: ktests.sh's group and, inside it, the threaded runner's group
# (the coproc of the run's group shell, nested) - both end normally, nothing
# on stderr (no "coproc still exists" warning), the totals are right.
mkdir -p "$TMP/suite"
for n in 001 002; do
    printf '%s\n' "source \"$LIB/ktest.sh\"" \
        "kt_test_init \"W$n\" \"\$(dirname \"\$0\")\"" \
        "kt_test_start \"w$n\"" \
        "kt_test_pass \"w$n\"" > "$TMP/suite/${n}_w.sh"
done
for be in fifo coproc; do
    for mode in threaded single; do
        kt_test_start "$be/$mode: ktests.sh runs normally (nested groups), rc 0, 2 tests, an empty stderr [L5.9]"
        if [[ "$be" == fifo ]] && (( KT_CYGWIN )); then kt_test_pass "SKIP: the FIFO backend wedges on cygwin (L5.9); covered on Linux/macOS/BSD"; continue; fi
        mkdir -p "$TMP/run.$be.$mode"
        out="$(KT_RUNNER_WATCH=$be TMPDIR="$TMP/run.$be.$mode" "${KT060_TMO[@]}" bash "$LIB/ktests.sh" "$TMP/suite" W '/[0-9][0-9][0-9]_' -m "$mode" -w 2 2>"$TMP/run.$be.$mode.err" </dev/null)"; rc=$?
        err="$(cat "$TMP/run.$be.$mode.err" 2>/dev/null)"
        if [[ "$rc" == 0 && "$out" == *"Total tests: 2"* && -z "$err" ]]; then
            kt_test_pass "$be/$mode: rc 0, Total tests: 2"
        else
            kt_test_fail "$be/$mode: rc=$rc, [$(grep -a 'Total tests' <<< "$out")], stderr [$err]"
        fi
    done
done
