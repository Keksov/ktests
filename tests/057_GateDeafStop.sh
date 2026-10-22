#!/usr/bin/env bash
# GateDeafStop (launch L2.7-G). A process that acts on no cygwin signal — two
# ktests.sh runners on 2026-10-22 (Git-bash 5.2, threaded gate cells, wedged
# in a cygwin FIFO open) ignored the gate's TERM/KILL for over an hour, one
# spinning a core; here a Windows-SUSPENDED process (NtSuspendProcess through
# powershell) — is stopped from the Windows side as the LAST step of a stop:
# kt_proc_winkill (ktest_proc.sh: the runtime's own `kill -f -9 PID`, a
# narrowed taskkill only when that fails)
#   - in kt_strays_stop after its SIGKILLs (the gate's and the master's stray
#     check, the gate watchdog's segment-killed path), and
#   - in kt_suitejob_signal after the job's SIGKILL — a job leader that
#     ignored KILL used to hang its `wait` (and the gate) for ever; one that
#     survives even the last step makes the cell STRAY (`job leader P could
#     NOT be stopped (winpid W)`) and is listed again by the final check.
# A stray that survives is named with its winpid in the "could NOT be
# stopped" line. Off cygwin there is no such step: kt_proc_winkill is a no-op
# (rc 1) and the cygwin cases are N/A passes. On every platform: the gate's
# start grace (KT_GATE_START_GRACE) stops a cell whose runner never started
# (fixture deadstart) as TIMEOUT `runner did not start`, and leaves a runner
# that started but stays silent past the grace alone (fixture silentalive).
#
# The suspended processes live in the OTHER cygwin runtime when there is one
# (XB below: a suspended process slows every stray scan of its runtime by
# ~1 s); under `gate.sh --parallel` (KT_GATE_PARALLEL=1: that runtime's
# segment runs at the same time) the suspended cases are N/A passes.
#
# Everything made here is recorded ("PID WINPID" files in this file's tmp:
# the fixtures' and the driver's); the EXIT trap ends what is still alive as
# that process (/proc/PID/winpid unchanged) with `kill -f -9`, and KILLs what
# carries the nonce or the tmp path. A suspended process is never left for
# long even when this file is SIGKILLed: each suspend starts a hidden
# powershell reaper that holds a handle to it and ends it after 120 s if it
# is still the process suspended (same start time) — and the stray check of
# the sweep/gate running this file stops it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GateDeafStop" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
G="$LIB/tools/gate.sh"
SJ="$LIB/tools/suitejob.sh"
MK="$LIB/tests/gate_fixtures/mkroot.sh"
unset KT_GATE_BASHES KT_GATE_SPAWN KT_GATE_TEST_NOWINKILL
N="kt057x$$x$RANDOM$RANDOM"
kt_proc_init
# XB: the bash whose runtime holds the SUSPENDED processes — the OTHER cygwin
# runtime when there is one. Every /proc read of a suspended process waits
# ~1 s for an answer it never gets (cygwin asks the process for its argv), so
# while one lives, every stray scan of its runtime is 1 s slower: the other
# test files of this suite (045, 056: timing-bound scans) run in THIS
# runtime, and the gate runs the two runtimes one after the other. So each
# runtime's run of this file exercises the other runtime's stop path (the
# gate covers both); with one runtime only, this one.
XB="$BASH"
if [[ "$KT_PROC_BACKEND" == cygwin ]]; then
    for b in /c/bin/msys64/usr/bin/bash.exe /c/msys64/usr/bin/bash.exe /c/bin/Git/usr/bin/bash.exe "/c/Program Files/Git/usr/bin/bash.exe"; do
        [[ -x "$b" ]] || continue
        v="$("$b" -c 'printf %s "$BASH_VERSION"' 2>/dev/null </dev/null)"
        [[ -n "$v" && "$v" != "$BASH_VERSION" ]] && { XB="$b"; break; }
    done
fi
XV="$("$XB" -c 'printf %s "${BASH_VERSION%%(*}"' 2>/dev/null </dev/null)"
# kt057_x ARGS... — run bash ARGS in XB's runtime (its tools first in PATH)
kt057_x() { PATH="${XB%/*}:$PATH" "$XB" "$@"; }

# kt057_cleanup — every recorded "PID WINPID" still alive as that process (in
# XB's runtime): `kill -f -9`; then KILL what carries the nonce or the tmp path
kt057_cleanup() {
    local f p w
    for f in "$TMP"/*.dpid "$TMP"/out*/cells/*/tmp/gfx-deaf*.pid; do
        [[ -f "$f" ]] || continue
        while read -r p w; do
            [[ "$p" =~ ^[0-9]+$ && "$w" =~ ^[0-9]+$ ]] || continue
            kt057_x -c 'cw=""; { read -r cw < "/proc/$1/winpid"; } 2>/dev/null; [[ "$cw" == "$2" ]] && "${BASH%/*}/kill" -f -9 "$1"; :' _ "$p" "$w" </dev/null >/dev/null 2>&1
        done < "$f"
    done
    for f in "$N" "$TMP"; do
        kt_proc_pids "$f"
        [[ -n "$REPLY" ]] && kill -KILL $REPLY 2>/dev/null
        [[ "$XB" != "$BASH" ]] && kt057_x -c 'source "$1/ktest_proc.sh"; kt_proc_pids "$2"; [[ -n "$REPLY" ]] && kill -KILL $REPLY 2>/dev/null; :' _ "$LIB" "$f" </dev/null
    done
    return 0
}
eval "$(trap -p EXIT | sed "s/^trap -- '/trap -- 'trap \"\" TERM INT HUP; kt057_cleanup; /")"
[[ "$(trap -p EXIT)" == *kt057_cleanup* ]] || trap 'trap "" TERM INT HUP; kt057_cleanup' EXIT
trap 'trap "" TERM INT HUP; exit 143' TERM
trap 'trap "" TERM INT HUP; exit 130' INT
trap 'trap "" TERM INT HUP; exit 129' HUP

# kt057_gone PIDFILE — rc 0 when the process recorded in PIDFILE ("PID
# WINPID") is gone (its /proc entry in XB's runtime no longer names that
# winpid); REPLY = the record
kt057_gone() {
    local p="" w=""
    { read -r p w < "$1"; } 2>/dev/null
    REPLY="$p $w"
    [[ "$p" =~ ^[0-9]+$ && "$w" =~ ^[0-9]+$ ]] || return 1
    ! kt057_x -c 'cw=""; { read -r cw < "/proc/$1/winpid"; } 2>/dev/null; [[ "$cw" == "$2" ]]' _ "$p" "$w" </dev/null
}
kt057_kv() {
    local k v
    REPLY=""
    while IFS='=' read -r k v; do [[ "$k" == "$2" ]] && { REPLY="$v"; return 0; }; done < "$1"
    return 1
}
kt057_line() {
    local l
    REPLY=""
    while IFS= read -r l; do [[ "$l" == "[$2/"* ]] && { REPLY="$l"; return 0; }; done <<< "$1"
    return 1
}

# the cases with a suspended process (cygwin only)
DEAF_T=( "a suspended orphan: plain 'kill -9' leaves it, the runtime's 'kill -f -9' ends it"
         "stray check, no Windows step: the survivor is named with its winpid in the 'could NOT be stopped' line"
         "stray check: a SUSPENDED orphan (deaf to TERM and KILL) is stopped by the Windows step, none left"
         "gate, fixture deaf: the cell's deaf stray is stopped (STRAY, 'stopped them, none left'), nothing left"
         "gate, fixture deafjob: the deaf job leader is ended after the KILL (TIMEOUT), the gate returns, nothing left"
         "gate, fixture deafjob, no Windows step: the surviving job leader makes the cell STRAY ('job leader P could NOT be stopped (winpid W)'), the final check lists it" )

if [[ "$KT_PROC_BACKEND" != cygwin ]]; then
    # ---- off cygwin: no Windows step ------------------------------------------
    kt_test_start "off cygwin: kt_proc_winkill is a no-op (rc 1, REPLY empty), kt_proc_winpid names nothing"
    REPLY=x; kt_proc_winkill "$$"; r1=$? x1="$REPLY"
    REPLY=x; kt_proc_winpid "$$"; r2=$? x2="$REPLY"
    if [[ "$r1" == 1 && -z "$x1" && "$r2" == 1 && -z "$x2" ]]; then
        kt_test_pass "backend $KT_PROC_BACKEND: winkill rc=$r1, winpid rc=$r2"
    else
        kt_test_fail "backend $KT_PROC_BACKEND: winkill rc=$r1 [$x1], winpid rc=$r2 [$x2]"
    fi
    for t in "${DEAF_T[@]}"; do
        kt_test_start "$t"
        kt_test_pass "N/A: no cygwin runtime (backend $KT_PROC_BACKEND)"
    done
else
    # ---- cygwin: kt_proc_winpid / kt_proc_winkill -------------------------------------
    kt_test_start "kt_proc_winpid names this shell's Windows pid; kt_proc_winkill of nothing is rc 1"
    REPLY=x; kt_proc_winpid "$BASHPID"; r1=$? x1="$REPLY"
    cw=""; read -r cw < "/proc/$BASHPID/winpid"
    REPLY=x; kt_proc_winkill 999999999; r2=$? x2="$REPLY"
    if [[ "$r1" == 0 && "$x1" == "$cw" && "$x1" =~ ^[0-9]+$ && "$r2" == 1 && -z "$x2" ]]; then
        kt_test_pass "winpid $x1; winkill of a gone pid rc=$r2"
    else
        kt_test_fail "winpid rc=$r1 [$x1] (/proc: $cw); winkill rc=$r2 [$x2]"
    fi
fi

if [[ "$KT_PROC_BACKEND" == cygwin && "${KT_GATE_PARALLEL:-}" == 1 ]]; then
    for t in "${DEAF_T[@]}"; do
        kt_test_start "$t"
        kt_test_pass "N/A: gate --parallel (the other runtime's segment runs now; a suspended process would slow its stray scans)"
    done
elif [[ "$KT_PROC_BACKEND" == cygwin ]]; then
    # ---- a driver in XB's runtime: a suspended orphan, then a stop -------------------
    cat > "$TMP/drv.sh" <<'EOF'
source "$1"; shift
scen="$1" out="$2" N="$3"
# drv_deaf NAME FILE — an orphan `sleep 60` (this session) whose Windows
# process is suspended; "PID WINPID" in FILE. The sleep runs from a copy named
# NAME.exe beside FILE: a suspended process cannot answer for its argv, /proc
# then shows only its program path — which still carries NAME (the nonce)
drv_deaf() {
    local i p="" w="" c ps x="${2%/*}/$1.exe"
    cp /usr/bin/sleep.exe "$x" || return 1
    bash -c '("$1" 60) </dev/null >/dev/null 2>&1 & echo "$!" > "$2.cpid"' _ "$x" "$2"
    read -r p < "$2.cpid"
    for (( i = 0; i < 50; i++ )); do   # the exec done: <= 5 s
        c=""; { IFS= read -r -d '' c < "/proc/$p/cmdline"; } 2>/dev/null
        [[ "$c" == *"/$1" || "$c" == *"/$1.exe" ]] && { read -r w < "/proc/$p/winpid"; break; }
        sleep 0.1
    done
    [[ "$w" =~ ^[0-9]+$ ]] || return 1
    printf '%s %s\n' "$p" "$w" > "$2"
    ps="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}")/System32/WindowsPowerShell/v1.0/powershell.exe"
    [[ -x "$ps" ]] || ps=powershell.exe
    # Add-Type compiles into %TEMP%: a Windows TEMP/TMP of its own (a bash
    # started from the other runtime may have none: then C:\Windows, denied)
    c="$(cygpath -w "${2%/*}")"
    MSYS2_ARG_CONV_EXCL='*' TEMP="$c" TMP="$c" timeout -k 5 60 "$ps" -NoProfile -NonInteractive -Command "Add-Type -Name N -Namespace W -MemberDefinition '[DllImport(\"ntdll.dll\")] public static extern int NtSuspendProcess(IntPtr h);'; \$p=Get-Process -Id $w; \$t=\$p.StartTime.Ticks; [void][W.N]::NtSuspendProcess(\$p.Handle); Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-NonInteractive','-Command',('\$q=Get-Process -Id $w -EA 0; if(\$q -and \$q.StartTime.Ticks -eq ' + \$t + ' -and -not \$q.WaitForExit(120000)){ \$q.Kill() }')" </dev/null >/dev/null 2>&1
    kill -KILL "$p" 2>/dev/null; sleep 1
    kill -0 "$p" 2>/dev/null && echo "deaf=yes" || echo "deaf=no"
    DRV_P="$p"
}
KT_STRAYS_KILL_MS=1000
kt_suitejob_init "$EPOCHREALTIME" "$N"
drv_deaf "kt057-$N-$scen" "$out.dpid"
case "$scen" in
    killf)
        # plain `kill -9` (the runtime's kill, no -f), then `kill -f -9`
        "${BASH%/*}/kill" -9 "$DRV_P" 2>/dev/null; sleep 1
        kill -0 "$DRV_P" 2>/dev/null && echo "plain=alive" || echo "plain=gone"
        "${BASH%/*}/kill" -f -9 "$DRV_P" 2>/dev/null
        for (( i = 0; i < 20; i++ )); do kill -0 "$DRV_P" 2>/dev/null || break; sleep 0.1; done
        kill -0 "$DRV_P" 2>/dev/null && echo "killf=alive" || echo "killf=gone"
        ;;
    *)
        # nowin: the escalation without its Windows step (what the gate did before)
        [[ "$scen" == nowin ]] && kt_proc_winkill() { REPLY=""; return 1; }
        t0=$SECONDS
        kt_suitejob_strays "the check"; echo "s=$? took=$(( SECONDS - t0 ))"
        ;;
esac
EOF
    kt057_drv() { o="$(timeout -k 5 90 env PATH="${XB%/*}:$PATH" "$XB" "$TMP/drv.sh" "$SJ" "$1" "$TMP/$1" "$N" 2>&1)"; }

    kt_test_start "${DEAF_T[0]} [runtime $XV]"
    kt057_drv killf
    if [[ "$o" == *"deaf=yes"* && "$o" == *"plain=alive"* && "$o" == *"killf=gone"* ]] && kt057_gone "$TMP/killf.dpid"; then
        kt_test_pass "${o//$'\n'/ }"
    else
        kt057_gone "$TMP/killf.dpid"; kt_test_fail "rec [$REPLY] | ${o//$'\n'/ | }"
    fi
    kt057_cleanup

    kt_test_start "${DEAF_T[1]} [runtime $XV]"
    kt057_drv nowin
    read -r p w < "$TMP/nowin.dpid" 2>/dev/null
    if [[ "$o" == *"deaf=yes"* && "$o" == *"[WARN] 1 stray process(es) found after the check:"* \
          && "$o" == *"[WARN] 1 could NOT be stopped (winpid $p=$w):"* && "$o" == *"s=1 "* && -n "${w:-}" ]]; then
        kt_test_pass "pid $p = winpid $w named"
    else
        kt_test_fail "pid ${p:-?} winpid ${w:-?} | ${o//$'\n'/ | }"
    fi
    kt057_cleanup

    kt_test_start "${DEAF_T[2]} [runtime $XV]"
    kt057_drv win
    if [[ "$o" == *"deaf=yes"* && "$o" == *"[WARN] 1 stray process(es) found after the check:"* \
          && "$o" == *"[WARN] stopped them, none left"* && "$o" != *"could NOT"* && "$o" == *"s=1 "* ]] \
       && kt057_gone "$TMP/win.dpid"; then
        kt_test_pass "${o##*$'\n'}; [$REPLY] gone"
    else
        kt057_gone "$TMP/win.dpid"; kt_test_fail "left? [$REPLY] | ${o//$'\n'/ | }"
    fi
    kt057_cleanup

    # ---- the gate, its segment in XB's runtime ----------------------------------------
    R="$TMP/root"; O="$TMP/out"
    bash "$MK" "$R" deaf deafjob
    t0=$SECONDS
    ( export KT_GATE_BASHES="$(cygpath -m "$XB")"; exec timeout -k 10 170 bash "$G" --root "$R" --out "$O" --timeout 5 all ) > "$TMP/g.out" 2>&1 < /dev/null
    RC=$? dt=$(( SECONDS - t0 ))
    og="$(cat "$TMP/g.out")"

    kt_test_start "${DEAF_T[3]} [runtime $XV]"
    kt057_line "$og" 1; l1="$REPLY"
    st1="$(cat "$O/cells/001/strays.txt" 2>/dev/null)"
    if [[ "$l1" =~ \ deaf\ +STRAY\ +1/1\  && "$st1" == *"[WARN] stopped them, none left"* && "$st1" != *"could NOT"* ]] \
       && kt057_gone "$O/cells/001/tmp/gfx-deaf.pid"; then
        kt_test_pass "[$l1]; [$REPLY] gone"
    else
        kt057_gone "$O/cells/001/tmp/gfx-deaf.pid"
        kt_test_fail "rc=$RC dt=${dt}s [$l1] rec [$REPLY] strays: ${st1//$'\n'/ | } | ${og//$'\n'/ | }"
    fi

    kt_test_start "${DEAF_T[4]} [runtime $XV]"
    kt057_line "$og" 2; l2="$REPLY"
    kt057_kv "$O/cells/002/result" duration_ms; stopms=$(( ${REPLY:-999999} - 5000 ))
    if [[ "$RC" == 1 && "$l2" =~ \ deafjob\ +TIMEOUT\  && "$og" == *$'\n'"__GATE__:FAIL:2:0:0:0:0:1:1:"* ]] \
       && (( stopms < 60000 )) && kt057_gone "$O/cells/002/tmp/gfx-deafjob.pid"; then
        kt_test_pass "[$l2] stop ${stopms}ms after the deadline; [$REPLY] gone; gate ${dt}s"
    else
        kt057_gone "$O/cells/002/tmp/gfx-deafjob.pid"
        kt_test_fail "rc=$RC dt=${dt}s stop=${stopms}ms [$l2] rec [$REPLY] | ${og//$'\n'/ | }"
    fi
    kt057_cleanup

    # no Windows step in the segment (KT_GATE_TEST_NOWINKILL=1): the deaf
    # leader survives the stop — the cell is STRAY with its pid and winpid,
    # its strays.txt and the segment's final check name it
    R3="$TMP/root3"; O3="$TMP/out3"
    bash "$MK" "$R3" deafjob
    ( export KT_GATE_BASHES="$(cygpath -m "$XB")" KT_GATE_TEST_NOWINKILL=1
      exec timeout -k 10 170 bash "$G" --root "$R3" --out "$O3" --timeout 5 all ) > "$TMP/g3.out" 2>&1 < /dev/null
    RC=$?
    og="$(cat "$TMP/g3.out")"
    kt_test_start "${DEAF_T[5]} [runtime $XV]"
    kt057_line "$og" 1; l1="$REPLY"
    kt057_kv "$O3/cells/001/result" reason; r1="$REPLY"
    p=""; w=""; { read -r p w < "$O3/cells/001/tmp/gfx-deafjob.pid"; } 2>/dev/null
    st1="$(cat "$O3/cells/001/strays.txt" 2>/dev/null)"
    sf="$(cat "$O3/seg-1.strays.txt" 2>/dev/null)"
    if [[ -n "$p" && "$RC" == 1 && "$l1" =~ \ deafjob\ +STRAY\  && "$r1" == *"job leader $p could NOT be stopped (winpid $w)"* \
          && "$st1" == *"[WARN] job leader $p of cell 1 could NOT be stopped (winpid $w)"* \
          && "$sf" == *"[WARN] job leader $p of cell 1 could NOT be stopped (winpid $w)"* ]]; then
        kt_test_pass "[$l1] reason [$r1]; final check: ${sf//$'\n'/ | }"
    else
        kt_test_fail "rc=$RC pid=$p winpid=$w [$l1] reason [$r1] strays: ${st1//$'\n'/ | } final: ${sf//$'\n'/ | } | ${og//$'\n'/ | }"
    fi
    kt057_cleanup
fi

# ---- every platform: the start grace (3c) -----------------------------------------
# A runner wedged at its start (a cygwin FIFO open: no output, no test file's
# shell) used to cost the whole --timeout. KT_GATE_START_GRACE=6, single
# mode: the fixture deadstart (its wrapper execs `sleep 600`) is stopped as
# TIMEOUT `runner did not start` once 3 looks at least 15 s apart past the
# grace saw nothing (~grace + 30 s), long before --timeout 120; the fixture
# silentalive (one test file that waits 18 s = 3x the grace in silence) is no
# such cell: its test file's shell lives, it runs to its PASS.
R2="$TMP/root2"; O2="$TMP/out2"
bash "$MK" "$R2" deadstart silentalive
t0=$SECONDS
( export KT_GATE_START_GRACE=6; exec timeout -k 10 200 bash "$G" --root "$R2" --out "$O2" --mode single --timeout 120 all ) > "$TMP/g2.out" 2>&1 < /dev/null
RC=$? dt=$(( SECONDS - t0 ))
og="$(cat "$TMP/g2.out")"
kt_test_start "start grace: a cell whose runner never starts (deadstart) is TIMEOUT 'runner did not start' at ~grace + 30 s, not after --timeout"
kt057_line "$og" 1; l1="$REPLY"
kt057_kv "$O2/cells/001/result" reason; r1="$REPLY"
kt057_kv "$O2/cells/001/result" duration_ms; d1="${REPLY:-999999}"
if [[ "$l1" =~ \ deadstart\ +TIMEOUT\  && "$r1" == "runner did not start (no result, no child within 6s)" ]] && (( d1 >= 30000 && d1 < 80000 )); then
    kt_test_pass "[$l1] ${d1}ms"
else
    kt_test_fail "rc=$RC dt=${dt}s [$l1] reason [$r1] ${d1}ms | ${og//$'\n'/ | }"
fi
kt_test_start "start grace: a runner that started but stays silent for 3x the grace (silentalive, single mode) is not stopped by it: PASS"
kt057_line "$og" 2; l2="$REPLY"
if [[ "$l2" =~ \ silentalive\ +PASS\ +1/1\  && "$RC" == 1 ]]; then
    kt_test_pass "[$l2]"
else
    kt_test_fail "rc=$RC [$l2] | ${og//$'\n'/ | }"
fi

kt_test_log "057_GateDeafStop.sh completed"
