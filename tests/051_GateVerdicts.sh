#!/usr/bin/env bash
# GateVerdicts (gate G2). Every gate fixture (tests/gate_fixtures) through
# ktests/tools/gate.sh: its verdict, the line, the result file and the exit
# code — PASS (0), warn=N (a column, still PASS), ENV on the first attempt
# only (re-run once, PASS, both attempts kept), ENV on both (3), FAIL with its
# [FAIL] lines (1), TIMEOUT with the group stopped, STRAY with the leaked
# process stopped, CRASH (no summary), a host suspend (a stopped watchdog:
# the deadline moves, PASS with `host suspended Ns`) — and the hermetic cell: a polluted
# caller (a `debug = quiet` config in its HOME/.kbool and USERPROFILE/.kbool —
# fake ones in this file's tmp, never the real HOME —, KBOOL_HOME, BASH_ENV,
# VERBOSITY, CDPATH, an exported variable and exported functions incl.
# kk.uses) changes nothing a cell sees; the caller's locale is kept.
#
# All on fake roots (gate_fixtures/mkroot.sh) in this file's private tmp;
# each gate bounded by `timeout`; the end checks nothing carrying the tmp
# path is left.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GateVerdicts" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
G="$LIB/tools/gate.sh"
MK="$LIB/tests/gate_fixtures/mkroot.sh"
unset KT_GATE_BASHES
V="${BASH_VERSION%%(*}"

kt051_pids() { kt_proc_pids_gone "$1"; }   # what is LEFT (/proc or ps; a busybox timeout watcher waited out — launch L2.1)
# kt051_gate OUTFILE ARGS... — gate.sh bounded; RC; the output in OUTFILE
kt051_gate() {
    local of="$1"; shift
    "$KT_TIMEOUT" -k 10 150 bash "$G" "$@" > "$of" 2>&1 < /dev/null
    RC=$?
}
# kt051_kv FILE KEY — REPLY = KEY's value in a result file
kt051_kv() {
    local k v
    REPLY=""
    while IFS='=' read -r k v; do [[ "$k" == "$2" ]] && { REPLY="$v"; return 0; }; done < "$1"
    return 1
}
# kt051_line OUT IDX — REPLY = the progress line of cell IDX (no ANSI anyway)
kt051_line() {
    local l
    REPLY=""
    while IFS= read -r l; do [[ "$l" == "[$2/"* ]] && { REPLY="$l"; return 0; }; done <<< "$1"
    return 1
}

# ---- A: pass, warn, env (first attempt only) -> 0 --------------------------------
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RA="$TMP/rootA"; OA="$TMP/outA"
bash "$MK" "$RA" pass warn env
kt051_gate "$TMP/a.out" --root "$RA" --out "$OA" --timeout 60 all
oa="$(cat "$TMP/a.out")"
fi   # kt_need_timeout (setup)
kt_test_start "pass + warn + env-once: rc 0, __GATE__:PASS"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
if [[ "$RC" == 0 && "$oa" == *$'\n'"__GATE__:PASS:3:3:0:0:0:0:0:6:6" ]]; then
    kt_test_pass "${oa##*$'\n'}"
else
    kt_test_fail "rc=$RC | ${oa//$'\n'/ | }"
fi
fi   # kt_need_timeout
kt_test_start "pass: PASS 3/3, no log= on a passed cell; warn: PASS 1/1 warn=1 (a column, not a verdict)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt051_line "$oa" 2; l2="$REPLY"; kt051_line "$oa" 3; l3="$REPLY"
kt051_kv "$OA/cells/003/result" warn; w3="$REPLY"
if [[ "$l2" =~ \ pass\ +PASS\ +3/3\  && "$l2" != *log=* && "$l3" =~ \ warn\ +PASS\ +1/1\ +warn=1\  && "$w3" == 1 ]]; then
    kt_test_pass "[$l2] [$l3]"
else
    kt_test_fail "[$l2] [$l3] warn=$w3"
fi
fi   # kt_need_timeout
kt_test_start "env-once: attempt 1 ENV (a raw cygwin fork-failure line) is re-run once in a fresh sandbox; the second run decides (PASS); both attempts kept"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt051_line "$oa" 1; l1="$REPLY"
kt051_kv "$OA/cells/001/result" verdict; v1="$REPLY"; kt051_kv "$OA/cells/001/result" attempts; a1="$REPLY"
kt051_kv "$OA/cells/001/result" attempt1; t1="$REPLY"
if [[ "$l1" =~ \ env\ +PASS\ +2/2\  && "$l1" == *"(attempt 1: ENV, re-run once)"* && "$v1" == PASS && "$a1" == 2 \
      && "$t1" == "ENV rc=1 total=2 passed=1 failed=1 "*"fork failure: "* \
      && -f "$OA/cells/001/log.1.txt" && -f "$OA/cells/001/summary.1" && -f "$OA/cells/001/fails.1.txt" ]] \
   && grep -q 'dofork:' "$OA/cells/001/log.1.txt" && ! grep -q 'dofork:' "$OA/cells/001/log.txt"; then
    kt_test_pass "[$l1] attempt1=[$t1]"
else
    kt_test_fail "line [$l1] verdict=$v1 attempts=$a1 attempt1=[$t1] files: $(ls "$OA/cells/001" | tr '\n' ' ')"
fi
fi   # kt_need_timeout

# ---- B: env on every attempt -> ENV, 3 ---------------------------------------------
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RB="$TMP/rootB"; OB="$TMP/outB"
bash "$MK" "$RB" envx
kt051_gate "$TMP/b.out" --root "$RB" --out "$OB" all
ob="$(cat "$TMP/b.out")"
fi   # kt_need_timeout (setup)
kt_test_start "env-always: ENV after the retry -> exit 3, __GATE__:ENV"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt051_line "$ob" 1; l1="$REPLY"
kt051_kv "$OB/cells/001/result" attempts; a1="$REPLY"
if [[ "$RC" == 3 && "$l1" =~ \ envx\ +ENV\ +0/1\  && "$l1" == *"(attempt 1: ENV, re-run once)"* && "$a1" == 2 \
      && "$ob" == *"        [FAIL] a subshell returned garbage (001_envx.sh)"* && "$l1" == *"(fork failure: dofork:)"* \
      && "$ob" == *$'\n'"gate ENV  out="*$'\n'"__GATE__:ENV:1:0:0:0:1:0:0:0:1" ]]; then
    kt_test_pass "[$l1]"
else
    kt_test_fail "rc=$RC attempts=$a1 | ${ob//$'\n'/ | }"
fi
fi   # kt_need_timeout

# ---- C: fail -> 1 ------------------------------------------------------------------
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RC_="$TMP/rootC"; OC="$TMP/outC"
bash "$MK" "$RC_" fail
kt051_gate "$TMP/c.out" --root "$RC_" --out "$OC" all
oc="$(cat "$TMP/c.out")"
fi   # kt_need_timeout (setup)
kt_test_start "fail: FAIL 2/5 -> exit 1; its [FAIL] lines shown under the line; result counts; log= named"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt051_line "$oc" 1; l1="$REPLY"
kt051_kv "$OC/cells/001/result" failed; f1="$REPLY"; kt051_kv "$OC/cells/001/result" fail_lines; fl="$REPLY"
if [[ "$RC" == 1 && "$l1" =~ \ fail\ +FAIL\ +2/5\  && "$l1" == *"log=cells/001/log.txt"* \
      && "$oc" == *"$l1"$'\n'"        [FAIL] gfx bad one: expected 1 got 2 (002_bad.sh)"$'\n'"        [FAIL] gfx bad two: expected a got b (003_worse.sh)"$'\n'"        [FAIL] gfx bad three: expected x got y (003_worse.sh)"$'\n'* \
      && "$f1" == 3 && "$fl" == 3 && "$oc" == *$'\n'"__GATE__:FAIL:1:0:1:0:0:0:0:2:5" ]] \
   && [[ "$(grep -c '^file ' "$OC/cells/001/summary")" == 2 ]]; then
    kt_test_pass "[$l1] + 3 [FAIL] lines"
else
    kt_test_fail "rc=$RC failed=$f1 fail_lines=$fl | ${oc//$'\n'/ | }"
fi
fi   # kt_need_timeout

# ---- D: hang, leak, crash -> 1 -----------------------------------------------------
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RD="$TMP/rootD"; OD="$TMP/outD"
bash "$MK" "$RD" crash hang leak
t0=$SECONDS
kt051_gate "$TMP/d.out" --root "$RD" --out "$OD" --timeout 10 all   # 10, not 4: under the full suite a 1-file cell took 5.2 s on 5.3 (G4 review round 1)
dt=$(( SECONDS - t0 ))
od="$(cat "$TMP/d.out")"
kt051_pids "$RD"; leftD="$REPLY"
fi   # kt_need_timeout (setup)
kt_test_start "hang: TIMEOUT at --timeout 10 (reason in the line), its group stopped — nothing of it left"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt051_line "$od" 2; l2="$REPLY"
kt051_kv "$OD/cells/002/result" verdict; v2="$REPLY"
# the stop itself (deadline -> the cell's end) is quick in every runtime:
# under 60 s (launch L2.1: a 27-minute "stop" on cygwin was a host sleep)
kt051_kv "$OD/cells/002/result" duration_ms; stopms=$(( ${REPLY:-999999} - 10000 ))
if [[ "$l2" =~ \ hang\ +TIMEOUT\  && "$l2" == *"(timeout 10s, group stopped)"* && "$v2" == TIMEOUT && -z "$leftD" ]] \
   && (( stopms < 60000 )); then
    kt_test_pass "[$l2] stop ${stopms}ms after the deadline"
else
    kt_test_fail "[$l2] verdict=$v2 left=[$leftD] stop=${stopms}ms"
fi
fi   # kt_need_timeout
kt_test_start "leak: STRAY (the suite passed, it left a detached sleep) — listed with the cell, stopped"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt051_line "$od" 3; l3="$REPLY"
kt051_kv "$OD/cells/003/result" strays; s3="$REPLY"; kt051_kv "$OD/cells/003/result" passed; p3="$REPLY"
if [[ "$l3" =~ \ leak\ +STRAY\ +1/1\  && "$od" == *"        stray: pid "*"started during cell 3: gfx-leak:"* \
      && "$s3" == 1 && "$p3" == 1 && -z "$leftD" ]]; then
    kt_test_pass "[$l3]"
else
    kt_test_fail "[$l3] strays=$s3 left=[$leftD] | ${od//$'\n'/ | }"
fi
fi   # kt_need_timeout
kt_test_start "crash: CRASH (the runner died, no summary file) with the log's tail; the whole run -> exit 1"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt051_line "$od" 1; l1="$REPLY"
if [[ "$l1" =~ \ crash\ +CRASH\  && "$l1" == *"(no summary from the runner (rc 137))"* \
      && "$od" == *"        log: gate fixture crash: the runner is about to die"* \
      && "$RC" == 1 && "$od" == *$'\n'"__GATE__:FAIL:3:0:1:0:0:1:1:1:1" && "$dt" -lt 60 ]]; then
    kt_test_pass "[$l1]; run ${dt}s: ${od##*$'\n'}"
else
    kt_test_fail "rc=$RC dt=$dt | ${od//$'\n'/ | }"
fi
fi   # kt_need_timeout

# ---- S: a host suspend is not the cell's time (launch L2.1) --------------------------
# A host that slept during a cell (a laptop on battery: Kernel-Power 42) made
# a 3-minute cell a TIMEOUT at wake-up. Here the watchdog is SIGSTOPped past
# the cell's deadline (--timeout 6, KT_GATE_SUSPEND_GAP=2) while the cell naps
# (gate fixture nap: TMPDIR/gfx-nap.ready, then it waits for gfx-nap.go):
# once CONTinued, the watchdog's tick gap moves the deadline — the cell ends
# PASS when told, its row and result say `host suspended Ns`.
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RSU="$TMP/rootSU"; OSU="$TMP/outSU"
bash "$MK" "$RSU" nap
( export KT_GATE_SUSPEND_GAP=2; exec "$KT_TIMEOUT" -k 10 150 bash "$G" --root "$RSU" --out "$OSU" --timeout 6 all ) > "$TMP/su.out" 2>&1 < /dev/null &
gpS=$!
wdS="" okS="" dlS="" curS=""
for (( i = 0; i < 600; i++ )); do   # the cell at its nap, the watchdog known: <= 60 s
    { read -r wdS < "$OSU/seg-1.wdpid"; } 2>/dev/null
    [[ -e "$OSU/cells/001/tmp/gfx-nap.ready" && "$wdS" =~ ^[0-9]+$ ]] && { okS=1; break; }
    sleep 0.1
done
if [[ -n "$okS" ]] && kill -STOP "$wdS" 2>/dev/null; then
    { read -r curS < "$OSU/seg-1.cur"; } 2>/dev/null
    [[ "$curS" =~ ^run\ 1\ ([0-9]+)$ ]] && dlS=${BASH_REMATCH[1]}
    # past the deadline by 2 s (bounded: 30 s)
    for (( i = 0; i < 300 && ${dlS:-0} > 0 && EPOCHSECONDS < dlS + 2; i++ )); do sleep 0.1; done
    kill -CONT "$wdS" 2>/dev/null
    sleep 3                             # its ticks: the old watchdog stopped the cell here
fi
: > "$OSU/cells/001/tmp/gfx-nap.go"
wait "$gpS"; RC=$?
os="$(cat "$TMP/su.out")"
kt051_line "$os" 1; lS="$REPLY"
kt051_kv "$OSU/cells/001/result" verdict; vS="$REPLY"
kt051_kv "$OSU/cells/001/result" reason; rS="$REPLY"
suspS=""; { read -r suspS < "$OSU/seg-1.susp"; } 2>/dev/null
fi   # kt_need_timeout (setup)
kt_test_start "host suspend: the watchdog stopped past --timeout 6 -> the deadline moves, PASS, 'host suspended Ns' in the row"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
if [[ -n "$okS" && -n "$dlS" && "$RC" == 0 && "$vS" == PASS && "$lS" =~ \ nap\ +PASS\ +1/1\  \
      && "$lS" == *"(host suspended "*"s, not counted against --timeout)"* && "$rS" == "host suspended "* \
      && "$suspS" =~ ^1\ ([0-9]+)$ ]] && (( BASH_REMATCH[1] >= 6 )); then
    kt_test_pass "[$lS] susp=[$suspS]"
else
    kt_test_fail "ready=$okS wd=$wdS cur=[$curS] rc=$RC verdict=$vS reason=[$rS] susp=[$suspS] | ${os//$'\n'/ | }"
fi
fi   # kt_need_timeout

# ---- E: the hermetic cell ------------------------------------------------------------
# kt051_probe_env ROOT — REPLY = the probe cell's environment (its wrapper's dump)
kt051_probe_env() {
    local f
    REPLY=""
    for f in "$1"/probe/tests/.gfx_cell_env.*; do [[ -f "$f" ]] && REPLY="$(cat "$f")"; done
}
# kt051_has DUMP REGEX — rc 0 when a line of DUMP matches REGEX (whole line)
kt051_has() {
    local l
    while IFS= read -r l; do [[ "$l" =~ ^$2$ ]] && return 0; done <<< "$1"
    return 1
}
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
FH="$TMP/fakehome"; FP="$TMP/fakeprofile"
mkdir -p "$FH/.kbool" "$FP/.kbool" "$TMP/kbh"
printf 'debug = quiet\n' > "$FH/.kbool/config"
printf 'debug = quiet\n' > "$FP/.kbool/config"
printf 'printf "%%s\\n" "$0" >> %q\n' "$TMP/bashenv.hits" > "$TMP/bashenv.sh"
FPM="$FP"; command -v cygpath >/dev/null 2>&1 && FPM="$(cygpath -m "$FP")"
RE1="$TMP/rootE1"; RE2="$TMP/rootE2"
bash "$MK" "$RE1" probe
bash "$MK" "$RE2" probe
# the clean caller: a minimal environment
env -i PATH="$PATH" SYSTEMROOT="${SYSTEMROOT:-}" WINDIR="${WINDIR:-}" HOME="$TMP/cleanhome" LC_ALL=C \
    "$KT_TIMEOUT" -k 10 150 bash "$G" --root "$RE1" --out "$TMP/outE1" all > "$TMP/e1.out" 2>&1 < /dev/null
rc1=$?
# the polluted caller
gfx_caller_fn() { :; }
kk.uses() { :; }
(
    export HOME="$FH" USERPROFILE="$FPM" KBOOL_HOME="$TMP/kbh" KBOOL_CONFIG="$FH/.kbool/config" GFX_CALLER_VAR=1 \
        VERBOSITY=info CDPATH=/ GLOBIGNORE='*' BASH_ENV="$TMP/bashenv.sh" VERBOSE_KKLASS=1 \
        KKLASS_CKK_DIR="$TMP/caller-ckk" __KK_CFG_ETC="$FH" ProgramData="$FPM" LC_ALL=C
    export -f gfx_caller_fn kk.uses
    "$KT_TIMEOUT" -k 10 150 bash "$G" --root "$RE2" --out "$TMP/outE2" all > "$TMP/e2.out" 2>&1 < /dev/null
    echo $? > "$TMP/e2.rc"
)
rc2="$(cat "$TMP/e2.rc" 2>/dev/null)"
e1="$(cat "$TMP/e1.out")"; e2="$(cat "$TMP/e2.out")"
fi   # kt_need_timeout (setup)
kt_test_start "hermetic: the probe passes from a clean caller and from a polluted one, with the same counts"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt051_line "$e1" 1; p1="$REPLY"; kt051_line "$e2" 1; p2="$REPLY"
if [[ "$rc1" == 0 && "$rc2" == 0 && "$p1" =~ \ probe\ +PASS\ +9/9\  && "$p2" =~ \ probe\ +PASS\ +9/9\  \
      && "${e1##*$'\n'}" == "${e2##*$'\n'}" ]]; then
    kt_test_pass "clean [$p1] polluted [$p2]"
else
    kt_test_fail "rc1=$rc1 rc2=$rc2 | ${e1//$'\n'/ | } || ${e2//$'\n'/ | } || fails: $(cat "$TMP/outE2/cells/001/fails.txt" 2>/dev/null)"
fi
fi   # kt_need_timeout
kt_test_start "hermetic: the cell's own HOME/USERPROFILE/ProgramData/config etc/TMPDIR/ckk/cwd; nothing of the polluted caller (vars, functions, its paths, BASH_ENV, OLDPWD); its locale kept"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt051_probe_env "$RE2"; d2="$REPLY"
bad=""
for t in GFX_CALLER_VAR KBOOL_HOME KBOOL_CONFIG VERBOSITY= CDPATH= GLOBIGNORE= BASH_ENV VERBOSE_KKLASS BASH_FUNC gfx_caller_fn kk.uses \
         "$FH" "$FP" "$FPM" caller-ckk OLDPWD=; do
    [[ "$d2" == *"$t"* ]] && bad+="[$t] "
done
c='/.*/cells/001'
# the Windows variables carry the mixed C:/ form — a plain path without cygpath (launch L2.1)
drv=""; command -v cygpath >/dev/null 2>&1 && drv="[A-Za-z]:"
for re in "LC_ALL=C" "HOME=$c/home" "USERPROFILE=$drv$c/home" "ProgramData=$drv$c/etc" "__KK_CFG_ETC=$c/etc" \
          "TMPDIR=$c/tmp" "TMP=$c/tmp" "TEMP=$c/tmp" "KKLASS_CKK_DIR=$c/ckk" "PWD_AT_START=$c/cwd" \
          "FDS=0 1 2( 255)?"; do
    kt051_has "$d2" "$re" || bad+="[no $re] "
done
[[ -n "$d2" ]] || bad+="[no dump] "
hits="$(cat "$TMP/bashenv.hits" 2>/dev/null)"
[[ "$hits" == */tests/* ]] && bad+="[BASH_ENV ran in a cell: ${hits//$'\n'/ }] "
if [[ -z "$bad" ]]; then
    kt_test_pass "$(grep -c . <<< "$d2") env lines, none from the caller; BASH_ENV ran only in: ${hits//$'\n'/ }"
else
    kt_test_fail "$bad"
fi
fi   # kt_need_timeout
kt_test_start "hermetic: across runtimes too (the polluted caller, the other bash)"
OTHER=""
for b in /c/bin/msys64/usr/bin/bash.exe /c/msys64/usr/bin/bash.exe /c/bin/Git/usr/bin/bash.exe "/c/Program Files/Git/usr/bin/bash.exe"; do
    [[ -x "$b" ]] || continue
    v="$("$b" -c 'printf %s "$BASH_VERSION"' 2>/dev/null </dev/null)"
    [[ -n "$v" && "$v" != "$BASH_VERSION" ]] && { OTHER="$b"; break; }
done
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
elif [[ -n "$OTHER" ]]; then
    RE3="$TMP/rootE3"
    bash "$MK" "$RE3" probe
    (
        export HOME="$FH" USERPROFILE="$FPM" KBOOL_HOME="$TMP/kbh" GFX_CALLER_VAR=1 VERBOSITY=info LC_ALL=C
        export -f gfx_caller_fn kk.uses
        "$KT_TIMEOUT" -k 10 150 bash "$G" --root "$RE3" --out "$TMP/outE3" --bash "$OTHER" all > "$TMP/e3.out" 2>&1 < /dev/null
        echo $? > "$TMP/e3.rc"
    )
    rc3="$(cat "$TMP/e3.rc" 2>/dev/null)"; e3="$(cat "$TMP/e3.out")"
    kt051_line "$e3" 1; p3="$REPLY"
    kt051_probe_env "$RE3"; d3="$REPLY"
    if [[ "$rc3" == 0 && "$p3" =~ \ probe\ +PASS\ +9/9\  && "$d3" == *"LC_ALL=C"* && "$d3" != *GFX_CALLER_VAR* && "$d3" != *"$FH"* ]] \
       && kt051_has "$d3" "FDS=0 1 2( 255)?"; then
        kt_test_pass "[$p3]"
    else
        kt_test_fail "rc3=$rc3 | ${e3//$'\n'/ | }"
    fi
else
    kt_test_pass "skipped: no second bash runtime on this machine"
fi
kt_test_start "hermetic: an fd the caller left open (7) never reaches a cell — the launcher closes every fd > 2 it inherited (CI runners leave pipes open) [L5.4-3]"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
RE4="$TMP/rootE4"
bash "$MK" "$RE4" probe
( exec 7</dev/null; "$KT_TIMEOUT" -k 10 150 bash "$G" --root "$RE4" --out "$TMP/outE4" all > "$TMP/e4.out" 2>&1 < /dev/null; echo $? > "$TMP/e4.rc" )
rc4="$(cat "$TMP/e4.rc" 2>/dev/null)"; e4="$(cat "$TMP/e4.out")"
kt051_line "$e4" 1; p4="$REPLY"
kt051_probe_env "$RE4"; d4="$REPLY"
fd4=""; while IFS= read -r l; do [[ "$l" == FDS=* ]] && fd4="$l"; done <<< "$d4"
if [[ "$rc4" == 0 && "$p4" =~ \ probe\ +PASS\ +9/9\  ]] && kt051_has "$d4" "FDS=0 1 2( 255)?"; then
    kt_test_pass "[$p4] cell: $fd4"
else
    kt_test_fail "rc4=$rc4 cell: [$fd4] | ${e4//$'\n'/ | }"
fi
fi   # kt_need_timeout

# ---- F: review round 1 (R1, R4, R5, R9, R10) ----------------------------------------
kt_test_start "a FAIL whose message talks about a fork failure stays FAIL (rc 1, not ENV); multi-line messages shown; a failed file with a space in its name is no message"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
RF="$TMP/rootF"; bash "$MK" "$RF" failsig
kt051_gate "$TMP/f.out" --root "$RF" --out "$TMP/outF" all
of="$(cat "$TMP/f.out")"
kt051_line "$of" 1; l1="$REPLY"
kt051_kv "$TMP/outF/cells/001/result" fail_lines; fl="$REPLY"; kt051_kv "$TMP/outF/cells/001/result" attempts; at="$REPLY"
if [[ "$RC" == 1 && "$l1" =~ \ failsig\ +FAIL\ +0/3\  && "$fl" == 3 && "$at" == 1 \
      && "$of" == *$'\n'"        [FAIL] a multi-line message, line 1"$'\n'"        line 2 of it"$'\n'"        line 3 of it (001_failsig.sh)"$'\n'* \
      && "$of" == *"        [FAIL] a file name with a space (002_a b.sh)"* && "$of" != *"        [FAIL] 002_a b.sh"$'\n'* ]] \
   && grep -qx 'file 002_a b.sh' "$TMP/outF/cells/001/summary"; then
    kt_test_pass "[$l1] fail_lines=$fl"
else
    kt_test_fail "rc=$RC fail_lines=$fl attempts=$at | ${of//$'\n'/ | }"
fi
fi   # kt_need_timeout
kt_test_start "a runner crash with a raw fork-failure line is ENV, re-run once (it then passes); a suite without test files is NOTRUN (not a failure) -> PASS, rc 0"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
RG="$TMP/rootG"; bash "$MK" "$RG" pass empty envcrash
kt051_gate "$TMP/g.out" --root "$RG" --out "$TMP/outG" all
og="$(cat "$TMP/g.out")"
kt051_line "$og" 1; l1="$REPLY"; kt051_line "$og" 2; l2="$REPLY"
kt051_kv "$TMP/outG/cells/002/result" attempt1; t2="$REPLY"; kt051_kv "$TMP/outG/cells/001/result" verdict; v1="$REPLY"
if [[ "$RC" == 0 && "$l1" =~ \ empty\ +NOTRUN\  && "$v1" == NOTRUN && "$l2" =~ \ envcrash\ +PASS\ +2/2\  \
      && "$t2" == "ENV "*"crash with a fork failure: dofork:"* && "$og" == *"0 CRASH  1 NOTRUN  tests 5/5"* \
      && "$og" == *$'\n'"__GATE__:PASS:3:2:0:0:0:0:0:5:5" ]]; then
    kt_test_pass "[$l1] [$l2]"
else
    kt_test_fail "rc=$RC attempt1=[$t2] | ${og//$'\n'/ | }"
fi
fi   # kt_need_timeout
kt_test_start "every cell NOTRUN: '[WARN] nothing ran', exit 1"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
RH="$TMP/rootH"; bash "$MK" "$RH" empty
kt051_gate "$TMP/h.out" --root "$RH" --out "$TMP/outH" all
oh="$(cat "$TMP/h.out")"
if [[ "$RC" == 1 && "$oh" == *"[WARN] nothing ran"* && "$oh" == *$'\n'"__GATE__:FAIL:1:0:0:0:0:0:0:0:0" ]]; then
    kt_test_pass "${oh##*$'\n'}"
else
    kt_test_fail "rc=$RC | ${oh//$'\n'/ | }"
fi
fi   # kt_need_timeout
kt_test_start "INT and QUIT are trappable inside a cell — its own runtime (perl/setsid start) and across (review R1)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
RS="$TMP/rootS"; bash "$MK" "$RS" sigs
bl=( --bash "$BASH" ); [[ -n "$OTHER" ]] && bl+=( --bash "$OTHER" )
kt051_gate "$TMP/s.out" --root "$RS" --out "$TMP/outS" "${bl[@]}" all
os="$(cat "$TMP/s.out")"
want=1; [[ -n "$OTHER" ]] && want=2
if [[ "$RC" == 0 && "$os" == *$'\n'"__GATE__:PASS:$want:$want:0:0:0:0:0:$(( 2 * want )):$(( 2 * want ))" ]]; then
    kt_test_pass "${os##*$'\n'}"
else
    kt_test_fail "rc=$RC | ${os//$'\n'/ | }"
fi
fi   # kt_need_timeout

kt_test_start "a fork failure in one file and a REAL failure in another: FAIL (rc 1, one attempt), the fork failure only as a note; envx (every failed file has it) stays ENV (G4 review R2)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
RM="$TMP/rootM"; bash "$MK" "$RM" mix envx
for m in threaded single; do
    kt051_gate "$TMP/m.$m.out" --root "$RM" --out "$TMP/outM.$m" --mode "$m" all
    eval "rcm_$m=\$RC"
done
om="$(cat "$TMP/m.threaded.out")" oms="$(cat "$TMP/m.single.out")"
kt051_line "$om" 2; lm="$REPLY"; kt051_line "$oms" 2; lms="$REPLY"; kt051_line "$om" 1; lx="$REPLY"
kt051_kv "$TMP/outM.threaded/cells/002/result" attempts; am="$REPLY"
if [[ "$rcm_threaded" == 1 && "$rcm_single" == 1 && "$lm" =~ \ mix\ +FAIL\ +0/2\  && "$lms" =~ \ mix\ +FAIL\ +0/2\  && "$am" == 1 \
      && "$lm" == *"+ fork failure in 001_noise.sh"*"not ENV: 002_real.sh failed as well"* && "$lx" =~ \ envx\ +ENV\  ]]; then
    kt_test_pass "[$lm]"
else
    kt_test_fail "rc=$rcm_threaded/$rcm_single attempts=$am | [$lx] [$lm] [$lms]"
fi
fi   # kt_need_timeout

kt_test_start "nothing of this file's gates is left (by its tmp path)"
kt051_pids "$TMP"
if [[ -z "$REPLY" ]]; then kt_test_pass "none"; else kt_test_fail "left: $REPLY"; fi

kt_test_log "051_GateVerdicts.sh completed"
