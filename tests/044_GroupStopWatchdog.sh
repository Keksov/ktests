#!/usr/bin/env bash
# GroupStopWatchdog (ktests round 5, P3 review round 2: N1, N4; 2026-10-16).
#
# Since review R1 the run and the threaded workers are BACKGROUND process
# groups. Two holes found by the critic:
#   N1  a background group is stopped by SIGTTOU when it writes to a terminal
#       with `stty tostop` (and by SIGTSTP/SIGSTOP); kt_runner_group_stop then
#       sent TERM (pending on a stopped process) and `wait`ed forever. Now it
#       also sends CONT, and a group ignores TTOU/TTIN (its first command,
#       kt_runner_group_watchdog, sets `trap '' TTOU TTIN`).
#   N4  the watchdog opened the FIFO BY PATH in its background child: an open
#       that came after the runner had closed its writer blocked forever (an
#       orphan nothing can wake — not even SIGKILL on MSYS). Now the read end
#       is opened in the group's shell BEFORE the watchdog is spawned (no block:
#       the runner's read-write fd is a writer) and the watchdog reads that fd.
# Every child here runs under `timeout` and in its own process group, so a red
# run cannot hang the suite or signal it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GroupStopWatchdog" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"

# ---- N1: a STOPPED group is still stopped and reaped by kt_runner_group_stop -
kt_test_start "kt_runner_group_stop ends a stopped group at once (TERM + CONT), the group is gone [N1]"
rm -f "$TMP/n1.pgid"
rc=0
timeout --foreground 20 bash -c '
source "$1/ktest.sh"
set -m
( while :; do sleep 1; done ) < /dev/null &
p=$!
set +m
printf "%s" "$p" > "$2/n1.pgid"
sleep 1
kill -STOP -- "-$p"
sleep 0.3
t0=$SECONDS
kt_runner_group_stop "$p"
kill -0 "$p" 2>/dev/null && exit 3
exit 0
' _ "$LIB" "$TMP" >/dev/null 2>&1 || rc=$?
pg="$(cat "$TMP/n1.pgid" 2>/dev/null)"
alive=no
if [[ -n "$pg" ]]; then
    kill -0 -- "-$pg" 2>/dev/null && alive=yes
    # never leave a stopped group behind, whatever the verdict
    kill -CONT -- "-$pg" 2>/dev/null; kill -KILL -- "-$pg" 2>/dev/null
fi
if [[ "$rc" == 0 && "$alive" == no ]]; then
    kt_test_pass "returned, group gone"
else
    kt_test_fail "rc=$rc (124 = group_stop hung) group alive=$alive"
fi

# The P3 master-sweep flake (042 R1 case, bash 5.2 under load): on the Git
# (cygwin) runtime a group signal sent while a member is still in its exec
# handover is lost for it (probe: 20 of 20 `sleep`s forked just before the TERM
# outlived it, in the right group, parent gone). kt_runner_group_stop KILLs
# what is left after its grace (here 0.5 s, 20 groups; its /proc snapshot before
# the TERM usually outlasts the exec handover already).
kt_test_start "kt_runner_group_stop also ends a member forked just before the stop (a lost TERM: KILLed after the grace) [R1, sweep flake]"
out="$(timeout --foreground 120 bash -c '
source "$1/ktest.sh"
g=""; trap "kill -KILL -- -\$g -\$! 2>/dev/null; exit 143" TERM INT HUP   # a killed run takes its set -m groups along ($!: forked, g not yet set)
surv=0 list=""
for (( i = 0; i < 20; i++ )); do
    kill -0 "$3" 2>/dev/null || break   # owner-tied: the test file is gone (a killed run)
    f="$2/rf.$i"; : > "$f"
    set -m
    ( sleep 8 & echo "$!" > "$f"; wait ) < /dev/null &
    g=$!
    set +m
    e=$(( SECONDS + 20 )); while [[ ! -s "$f" ]] && (( SECONDS < e )); do :; done
    s=$(<"$f")
    kt_runner_group_stop "$g" 5
    for (( k = 0; k < 10; k++ )); do kill -0 "$s" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$s" 2>/dev/null; then surv=$(( surv + 1 )); list+="$s "; kill -KILL "$s" 2>/dev/null; fi
done
echo "survivors=$surv [$list]"
' _ "$LIB" "$TMP" "$$" 2>&1)"
if [[ "$out" == "survivors=0 "* ]]; then
    kt_test_pass "20 groups stopped right after a fork: $out"
else
    kt_test_fail "$out"
fi

# The same flake, second half: under load the exec'ing member is also invisible
# to `kill -0 -- -PGID` for tens of ms, so kt_runner_group_stop reads the
# members from /proc too (kt_runner_group_members: no fork, zombies dropped).
kt_test_start "kt_runner_group_members lists exactly a live group's members from /proc, nothing for a gone group [R1, sweep flake]"
out="$(timeout --foreground 60 bash -c '
source "$1/ktest.sh"
g=""; trap "kill -KILL -- -\$g -\$! 2>/dev/null; exit 143" TERM INT HUP   # a killed run takes its set -m groups along ($!: forked, g not yet set)
set -m
( sleep 8 & echo "$!" > "$2/gm.s"; wait ) < /dev/null &
g=$!
set +m
e=$(( SECONDS + 20 )); while [[ ! -s "$2/gm.s" ]] && (( SECONDS < e )); do :; done
s=$(<"$2/gm.s")
# a member in its exec handover can be missing from /proc for a moment: poll (<= 10 s)
for (( k = 0; k < 100; k++ )); do
    kt_runner_group_members "$g"; live=" $REPLY "
    [[ "$live" == *" $s "* ]] && break
    sleep 0.1
done
kt_runner_group_members "$$"; mine=" $REPLY "
kt_runner_group_stop "$g"
kt_runner_group_members "$g"; gone="$REPLY"
kill -KILL "$s" 2>/dev/null
n=0; for p in $live; do n=$(( n + 1 )); done
[[ "$live" == *" $g "* && "$live" == *" $s "* && $n == 2 && "$mine" != *" $g "* && -z "$gone" ]] && echo OK || echo "live=[$live] mine=[$mine] gone=[$gone] g=$g s=$s"
' _ "$LIB" "$TMP" 2>&1)"
if [[ ! -r /proc/$$/pgid ]]; then
    kt_test_pass "no /proc/<pid>/pgid here (not cygwin): the stop falls back to kill -0 -- -PGID"
elif [[ "$out" == OK ]]; then
    kt_test_pass "leader + sleep listed, not in the caller's group, empty once stopped"
else
    kt_test_fail "$out"
fi

# TERM ONCE, then KILL after the grace (supervisor decision 2026-10-16, P3b
# review): a TERM re-sent every 0.1 s cut a test's cleanup short (a trapped
# TERM inside its EXIT trap exits bash at once) and never ended a member that
# ignores TERM.
kt_test_start "kt_runner_group_stop: a TERM-ignoring member is KILLed after the grace, a member's 0.8 s cleanup trap runs to its end [R1, P3b review]"
out="$(timeout --foreground 60 bash -c '
source "$1/ktest.sh"
g=""; trap "kill -KILL -- -\$g -\$! 2>/dev/null; exit 143" TERM INT HUP   # a killed run takes its set -m groups along ($!: forked, g not yet set)
d="$2/gs"; mkdir -p "$d"; rm -f "$d"/*
set -m
(
    ( trap "" TERM; exec sleep 12 ) &
    echo "$!" > "$d/ign"
    (
        # 0.8 s of cleanup without forking (a forked sleep can take 0.3 s under load)
        trap "exec {w}<>/dev/ptmx && read -t 0.8 -u \$w _; echo done > \"$d/clean\"" EXIT
        trap "exit 143" TERM
        sleep 12 &
        echo "$BASHPID" > "$d/good"
        wait
    ) &
    wait
) < /dev/null &
g=$!
set +m
for (( k = 0; k < 100; k++ )); do [[ -s "$d/ign" && -s "$d/good" ]] && break; sleep 0.1; done
sleep 0.5
i=$(<"$d/ign")
t0=${EPOCHREALTIME/[.,]/}
kt_runner_group_stop "$g" 30
dt=$(( (${EPOCHREALTIME/[.,]/} - t0) / 100000 ))
kill -0 "$i" 2>/dev/null && ia=alive || ia=gone
c=$(cat "$d/clean" 2>/dev/null)
kill -KILL "$i" 2>/dev/null
echo "[$KT_GROUP_END_STATS] ignorer=$ia cleanup=[$c] stop=${dt}ds"   # stats: rounds, /proc scan time, KILL rounds (critic F13)
' _ "$LIB" "$TMP" 2>&1)"
dt="${out##*stop=}"; dt="${dt%ds}"
if [[ "$out" == *"] ignorer=gone cleanup=[done] stop="* && "$dt" -ge 29 && "$dt" -le 80 ]]; then
    kt_test_pass "$out (grace 3 s)"
else
    kt_test_fail "$out (want ignorer gone, cleanup done, stop 2.9-8 s)"
fi

kt_test_start "a group's shell ignores SIGTTOU and SIGTTIN (a write to a tostop terminal does not stop it) [N1]"
out="$(timeout --foreground 20 bash -c '
source "$1/ktest.sh"
set -m
( kt_runner_group_watchdog "" ""; trap -p TTOU TTIN ) < /dev/null &
p=$!
set +m
wait "$p"
' _ "$LIB" 2>&1)"
out="${out//$'\n'/ | }"
if [[ "$out" == *"'' SIGTTOU"* && "$out" == *"'' SIGTTIN"* ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "trap -p TTOU TTIN in the group: [$out]"
fi

# ---- N4: a watchdog that starts late cannot block on the FIFO --------------
# A copy of the runner whose watchdog child sleeps 2 s before it reads — it
# starts only after the runner has finished and closed its writer. (ktest.sh
# loads its parts from an exported KTESTS_LIB_DIR: the child must not see it.)
mkdir -p "$TMP/lib"
cp "$LIB"/*.sh "$TMP/lib/"
sed -i '/__kt_l/s/{ IFS= read/{ sleep 2; IFS= read/' "$TMP/lib/ktest_runner.sh"
kt_test_start "a watchdog that starts after the runner closed its writer exits; no orphan [N4]"
if ! grep -q '{ sleep 2; IFS= read' "$TMP/lib/ktest_runner.sh"; then
    kt_test_fail "could not inject the delay into the watchdog"
else
    rm -f "$TMP/n4.fifo" "$TMP/n4.wd"
    timeout --foreground 20 env -u KTESTS_LIB_DIR bash -c '
source "$1/ktest.sh"
fifo="$2/n4.fifo"
kt_runner_group_open "$fifo" || exit 4
fd=$REPLY
set -m
( kt_runner_group_watchdog "$fifo" "$fd"; printf "%s" "$!" > "$2/n4.wd" ) < /dev/null &
p=$!
set +m
wait "$p"
kt_runner_group_close "$fd"
' _ "$TMP/lib" "$TMP" >/dev/null 2>&1
    wd="$(cat "$TMP/n4.wd" 2>/dev/null)"
    # the delayed child needs 2 s; give it 6
    for (( i = 0; i < 60; i++ )); do [[ -n "$wd" ]] && kill -0 "$wd" 2>/dev/null || break; sleep 0.1; done
    alive=no; [[ -n "$wd" ]] && kill -0 "$wd" 2>/dev/null && alive=yes
    # a watchdog blocked in open() is woken by any opener of the FIFO; it then
    # reads EOF and ends its own (dead) group: never leave it behind
    if [[ "$alive" == yes && -p "$TMP/n4.fifo" ]]; then
        exec {kt044_w}<>"$TMP/n4.fifo"; exec {kt044_w}>&-
        for (( i = 0; i < 50; i++ )); do kill -0 "$wd" 2>/dev/null || break; sleep 0.1; done
    fi
    if [[ -n "$wd" && "$alive" == no ]]; then
        kt_test_pass "watchdog $wd gone"
    else
        kt_test_fail "watchdog '$wd' alive=$alive (blocked in the FIFO open)"
    fi
fi

# ---- N6: SIGTSTP (Ctrl-Z) pauses the whole run, SIGCONT resumes it ----------
# A suite of 3 files, each sleeping 2 s and then leaving a marker. TSTP to the
# ktests.sh pid (what Ctrl-Z sends to the terminal's foreground group): no
# marker may appear while it is stopped; CONT finishes the run normally.
mkdir -p "$TMP/tstp"
for n in 001 002 003; do
    printf '%s\n' "source \"$LIB/ktest.sh\"" \
        "kt_test_init \"Z$n\" \"\$(dirname \"\$0\")\"" \
        "kt_test_start \"z$n\"" \
        "echo \"\$BASHPID\" >> '$TMP/tstp.pids'; sleep 2; : > '$TMP/tstp.done.$n'" \
        "kt_test_pass \"z$n\"" > "$TMP/tstp/${n}_z.sh"
done
kt044_ndone() { local f n=0; for f in "$TMP"/tstp.done.*; do [[ -e "$f" ]] && n=$(( n + 1 )); done; printf '%s' "$n"; }
for mode in threaded single; do
    kt_test_start "$mode: TSTP to ktests.sh stops the run (no test file progresses), CONT resumes it to a normal end [N6]"
    rm -f "$TMP"/tstp.done.* "$TMP/tstp.pids"; mkdir -p "$TMP/tstp.tmp.$mode"
    TMPDIR="$TMP/tstp.tmp.$mode" bash "$LIB/ktests.sh" "$TMP/tstp" Z '/[0-9][0-9][0-9]_' -m "$mode" -w 3 > "$TMP/tstp.out.$mode" 2>&1 &
    rp=$!
    for (( i = 0; i < 300; i++ )); do [[ -s "$TMP/tstp.pids" ]] && break; sleep 0.1; done
    kill -TSTP "$rp"
    sleep 0.5
    d1="$(kt044_ndone)"
    sleep 3
    d2="$(kt044_ndone)"
    st="$(cut -d' ' -f3 "/proc/$rp/stat" 2>/dev/null)"
    kill -CONT "$rp"
    rc=0
    # the run must end on its own now; never leave it stopped or running
    for (( i = 0; i < 300; i++ )); do kill -0 "$rp" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$rp" 2>/dev/null; then
        kill -CONT "$rp" 2>/dev/null; kill -TERM "$rp" 2>/dev/null; rc=hung
    fi
    wait "$rp" 2>/dev/null || rc=$?
    d3="$(kt044_ndone)"
    tot="$(grep -a 'Total tests:' "$TMP/tstp.out.$mode" | tr -s ' ' | tr -d '\n')"
    if [[ "$d1" == "$d2" && "$st" == T && "$rc" == 0 && "$d3" == 3 && "$tot" == *"Total tests: 3"* ]]; then
        kt_test_pass "stopped (state $st, $d1 done while stopped), resumed: rc 0, 3 done"
    else
        kt_test_fail "done before/after the pause $d1/$d2, ktests.sh state '$st', rc=$rc, done at end $d3, [$tot]"
    fi
done

# kt044_procs TEXT — REPLY = "pid:argv0 …" of the processes whose command line
# contains TEXT (no fork)
kt044_procs() {
    local f p
    local -a a
    REPLY=""
    for f in /proc/[0-9]*; do
        p="${f#/proc/}"
        [[ "$p" == "$$" || "$p" == "$BASHPID" ]] && continue
        a=(); { mapfile -d '' -t a < "$f/cmdline"; } 2>/dev/null || continue
        [[ "${a[*]}" == *"$1"* ]] && REPLY+="$p:${a[0]##*/} "
    done
    REPLY="${REPLY% }"
}
# kt044_gone TEXT SECONDS — rc 0 once no process carries TEXT (polled 0.1 s)
kt044_gone() {
    local i
    for (( i = 0; i < $2 * 10; i++ )); do
        kt044_procs "$1"; [[ -z "$REPLY" ]] && return 0
        sleep 0.1
    done
    return 1
}

# ---- critic P3b F8: a test file's `timeout N cmd` leaves the run group -------
# GNU timeout puts itself and its command in a process group of their own, so
# a TERM to the run's (or the worker) group never reached them: a TERMed run
# left `timeout` and its command running. kt_runner_group_stop also ends the
# group's descendants outside it (the /proc ppid chain, start time checked).
for mode in threaded single; do
    kt_test_start "$mode: a TERMed run also ends a test file's \`timeout 60 sleep 50\` (timeout's own process group) [critic P3b F8]"
    n="50.${$}${#mode}"
    d="$TMP/f8$mode"; mkdir -p "$d" "$TMP/f8tmp$mode"; rm -f "$d/pids"
    printf '%s\n' "source \"$LIB/ktest.sh\"" \
        "kt_test_init \"F8\" \"\$(dirname \"\$0\")\"" \
        'kt_test_start "f8"' \
        "timeout 60 sleep $n & echo \"\$!\" >> '$d/pids'; wait" \
        'kt_test_pass "f8"' > "$d/001_f.sh"
    TMPDIR="$TMP/f8tmp$mode" bash "$LIB/ktests.sh" "$d" F8 '/[0-9][0-9][0-9]_' -m "$mode" -w 2 > /dev/null 2>&1 &
    rp=$!
    for (( i = 0; i < 300; i++ )); do kt044_procs "sleep $n"; [[ "$REPLY" == *:sleep* ]] && break; sleep 0.1; done
    kt044_procs "$n"; before="$REPLY"
    kill -TERM "$rp" 2>/dev/null
    for (( i = 0; i < 150; i++ )); do kill -0 "$rp" 2>/dev/null || break; sleep 0.1; done
    rc=0; kill -0 "$rp" 2>/dev/null && rc=hung
    if [[ "$rc" == hung ]]; then kill -KILL "$rp" 2>/dev/null; else wait "$rp" 2>/dev/null; rc=$?; fi
    if kt044_gone "$n" 10; then left=""; else left="$REPLY"; fi
    kt044_procs "$n"; for p in $REPLY; do kill -KILL "${p%%:*}" 2>/dev/null; done
    if [[ "$before" == *:timeout*:sleep* || "$before" == *:sleep*:timeout* ]] && [[ "$rc" == 143 && -z "$left" ]]; then
        kt_test_pass "$mode: before [$before], rc $rc, nothing left"
    else
        kt_test_fail "$mode: before [$before] rc=$rc left=[$left]"
    fi
done

# ---- critic P3b F3: the watchdog ends a SIGKILLed run like a group stop -----
# A SIGKILLed ktests.sh runs no trap; the watchdog used to TERM its group once
# (no CONT, no KILL): a member that ignores TERM (or whose TERM was lost) ran
# on. Now it ends the group as kt_runner_group_stop does: TERM+CONT once, a
# fork-free wait, KILL after the grace (5 s for ktests.sh's group).
for mode in threaded single; do
    kt_test_start "$mode: SIGKILL to ktests.sh — the watchdog KILLs a TERM-ignoring test process after its grace [critic P3b F3]"
    n="40.${$}${#mode}"
    d="$TMP/f3$mode"; mkdir -p "$d" "$TMP/f3tmp$mode"
    printf '%s\n' "source \"$LIB/ktest.sh\"" \
        "kt_test_init \"F3\" \"\$(dirname \"\$0\")\"" \
        'kt_test_start "f3"' \
        "( trap '' TERM; exec sleep $n ) & wait" \
        'kt_test_pass "f3"' > "$d/001_f.sh"
    TMPDIR="$TMP/f3tmp$mode" bash "$LIB/ktests.sh" "$d" F3 '/[0-9][0-9][0-9]_' -m "$mode" -w 2 > /dev/null 2>&1 &
    rp=$!
    for (( i = 0; i < 300; i++ )); do kt044_procs "sleep $n"; [[ -n "$REPLY" ]] && break; sleep 0.1; done
    before="$REPLY"
    sleep 0.3
    t0=$SECONDS
    kill -KILL "$rp" 2>/dev/null; wait "$rp" 2>/dev/null
    left=""; kt044_gone "$n" 15 || left="$REPLY"   # the TERM-ignoring sleep
    kt044_gone "$d" 5 || left+=" $REPLY"     # the test file, the run's shells
    dt=$(( SECONDS - t0 ))
    kt044_procs "$d"; for p in $REPLY; do kill -KILL "${p%%:*}" 2>/dev/null; done
    kt044_procs "$n"; for p in $REPLY; do kill -KILL "${p%%:*}" 2>/dev/null; done
    if [[ -n "$before" && -z "${left// /}" ]]; then
        kt_test_pass "$mode: [$before] gone ${dt}s after the SIGKILL"
    else
        kt_test_fail "$mode: before [$before], still alive ${dt}s after the SIGKILL: [$left]"
    fi
done

# ---- critic P3b r2 N3: a tracked pid that was reused adopts no children -----
# cygwin pids wrap and are reused; kt_runner_group_scan adopts the children of
# a pid tracked in an earlier scan only while it is still the process recorded
# then (kt_runner_proc_same: start time, or the recorded process group). A
# reuse is simulated by a wrong record for a live process with a child.
kt_test_start "kt_runner_group_scan adopts a tracked pid's children only while it is the recorded process (a reused pid: dropped, children not adopted) [critic P3b r2 N3]"
out="$(timeout --foreground 60 bash -c '
source "$1/ktest.sh"
g=""; trap "kill -KILL -- -\$g -\$! 2>/dev/null; exit 143" TERM INT HUP
set -m
( sleep 9 & echo "$!" > "$2/n3.s"; wait ) < /dev/null &
g=$!
set +m
e=$(( SECONDS + 20 )); while [[ ! -s "$2/n3.s" ]] && (( SECONDS < e )); do sleep 0.05; done
s=$(<"$2/n3.s")
kt_runner_proc_start "$g"; real="$REPLY"
probe() {
    local __kt_gm=""
    local -A __kt_ds=()
    __kt_ds[$g]="$1"
    kt_runner_group_scan 999999 ""
    printf "%s/%s" "${__kt_ds[$s]+adopted}" "${__kt_ds[$g]+kept}"
}
same="$(probe "$real")"
reused="$(probe "1:1")"
kill -KILL -- "-$g" 2>/dev/null
echo "real=[$real] same=[$same] reused=[$reused]"
' _ "$LIB" "$TMP" 2>&1)"
if [[ "$out" == *"same=[adopted/kept] reused=[/]"* ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "$out (want same=[adopted/kept] reused=[/])"
fi

# ---- a TERMed run lets every test file's cleanup finish (P3b rs probe) -----
# Each file: an EXIT trap that takes 0.8 s (fork-free) and writes a marker,
# `trap 'exit 143' TERM` (the usual pattern), a child `sleep 20`. A TERM to the
# runner pid must reach each file ONCE: a second TERM arriving inside its EXIT
# trap exits bash at once and the marker never appears. In threaded mode the
# outer stop (ktests.sh) TERMed the worker group's processes as its own
# descendants AND the run's shell TERMed them again as its group.
for mode in threaded single; do
    want=2; [[ "$mode" == single ]] && want=1
    kt_test_start "$mode: TERM to the runner pid — every running test file's 0.8 s EXIT cleanup completes, nothing is left [P3b rs]"
    d="$TMP/cl$mode"; x="$TMP/clx$mode"; rm -rf "$x"; mkdir -p "$d" "$x/tmp"
    for k in 001 002; do
        printf '%s\n' "source \"$LIB/ktest.sh\"" \
            "kt_test_init \"C$k\" \"\$(dirname \"\$0\")\"" \
            'kt_test_start "c"' \
            "trap 'exec {w}<>/dev/ptmx && read -t 0.8 -u \$w _; echo done > \"$x/clean.$k\"' EXIT; trap 'exit 143' TERM" \
            "echo \$BASHPID > '$x/up.$k'; sleep 20 & wait" \
            'kt_test_pass "c"' > "$d/${k}_c.sh"
    done
    TMPDIR="$x/tmp" bash "$LIB/ktests.sh" "$d" CL '/[0-9][0-9][0-9]_' -m "$mode" -w 2 > /dev/null 2>&1 &
    rp=$!
    for (( i = 0; i < 300; i++ )); do n=0; for f in "$x"/up.*; do [[ -e "$f" ]] && n=$(( n + 1 )); done; (( n >= want )) && break; sleep 0.1; done
    up=$n
    sleep 0.5
    kill -TERM "$rp" 2>/dev/null
    for (( i = 0; i < 150; i++ )); do kill -0 "$rp" 2>/dev/null || break; sleep 0.1; done
    rc=0; kill -0 "$rp" 2>/dev/null && rc=hung
    if [[ "$rc" == hung ]]; then kill -KILL "$rp" 2>/dev/null; else wait "$rp" 2>/dev/null; rc=$?; fi
    nc=0; for f in "$x"/clean.*; do [[ -e "$f" ]] && nc=$(( nc + 1 )); done
    left=""; kt044_gone "$d" 10 || left="$REPLY"
    kt044_procs "$d"; for p in $REPLY; do kill -KILL "${p%%:*}" 2>/dev/null; done
    tmpl="$(ls -A "$x/tmp" 2>/dev/null | tr '\n' ' ')"
    if [[ "$up" == "$want" && "$nc" == "$want" && "$rc" == 143 && -z "$left" && -z "$tmpl" ]]; then
        kt_test_pass "$mode: $nc of $up cleanups done, rc 143, nothing left, TMPDIR empty"
    else
        kt_test_fail "$mode: cleanups done $nc of $up (want $want), rc=$rc left=[$left] TMPDIR=[$tmpl]"
    fi
done

kt_test_log "044_GroupStopWatchdog.sh completed"
