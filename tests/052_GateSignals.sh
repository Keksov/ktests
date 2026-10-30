#!/usr/bin/env bash
# GateSignals (gate G2). ktests/tools/gate.sh when it is stopped or killed
# from outside while a cell runs (GATE_PLAN 4.1, 6.4): TERM to the launcher,
# SIGKILL, `taskkill /F` (no trap: the segment sees the heartbeat go stale),
# the launcher's PARENT killed at the Windows level (the parent watch; also
# through a `timeout` between them: launch L2.1),
# `taskkill /F /T` on the launcher (a tree kill) and on the segment itself
# (the exec'd watchdog stops the cell: `segment-killed`) — in both directions
# launcher 5.2 -> segment 5.3 and 5.3 -> 5.2 when a second runtime exists
# (plus the same-runtime segment for SIGKILL, the tree kill and INT), the
# watchdog KILLed during a cell (review R6: a rescue watchdog still enforces
# --timeout / stops the cell after a TERM). Each: the
# launcher gone and the segment's result written within 60 s, an INTERRUPTED
# mark, a result for the finished cell, nothing of the run left in either
# runtime. And: no fork in the segment while a cell runs (its main and its
# watchdog get no new child — attributed by ppid: other tool shells fork in
# the Git runtime, G0).
#
# The fake root holds a_pass (finishes) and b_hang (runs 25 s); the
# heartbeat is shortened for the test (KT_GATE_HB_TICKS=6, every tick).
# A driver in the LAUNCHER's runtime starts the gate, kills what it recorded
# and nothing else; leftovers are found by this file's tmp path (in every
# command line of the run) and KILLed in their runtime.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GateSignals" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
G="$LIB/tools/gate.sh"
MK="$LIB/tests/gate_fixtures/mkroot.sh"
unset KT_GATE_BASHES

# this runtime and the other one (MSYS2 / Git for Windows), if any
SELF_B="$BASH"
# the /c/... spelling: the same file in both runtimes (G0)
if command -v cygpath >/dev/null 2>&1; then
    SELF_B="$(cygpath -m "$BASH")"
    [[ "$SELF_B" =~ ^([A-Za-z]):(/.*)$ ]] && SELF_B="/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
fi
OTHER=""
for b in /c/bin/msys64/usr/bin/bash.exe /c/msys64/usr/bin/bash.exe /c/bin/Git/usr/bin/bash.exe "/c/Program Files/Git/usr/bin/bash.exe"; do
    [[ -x "$b" ]] || continue
    v="$("$b" -c 'printf %s "$BASH_VERSION"' 2>/dev/null </dev/null)"
    [[ -n "$v" && "$v" != "$BASH_VERSION" ]] && { OTHER="$b"; break; }
done
TK="$(cygpath -u "${SYSTEMROOT:-C:\Windows}" 2>/dev/null)/System32/taskkill.exe"

R="$TMP/root"
bash "$MK" "$R" pass=a_pass hang=b_hang
# the sampler's pace: cygwin reads one /proc file a process, the table
# backends a whole snapshot per sample (Linux /proc/PID/stat, ps) — fewer
# samples under load (launch L2.1)
KT052_MINSAMP=30; kt_proc_init && [[ "$KT_PROC_BACKEND" != cygwin ]] && KT052_MINSAMP=10

# the driver: DRV SCEN SEGBASH OUT ROOT GATE TK SAMPLER TMO TIMEOUT_NAME — runs in the LAUNCHER's
# runtime; writes KEY=VALUE lines to OUT.drv
cat > "$TMP/drv.sh" <<'EOF'
SC=$1 SB=$2 OUT=$3 ROOT=$4 G=$5 TK=$6 SAMPLER=$7 TMO=${8:-120} TMOCMD=$9
P="" LP=""
# kill the segment's watchdog (in the segment's runtime: a child of its bash)
wdkill() {
    local w=""; { read -r w < "$OUT/seg-1.wdpid"; } 2>/dev/null
    say "wdpid=$w"
    [[ "$w" =~ ^[0-9]+$ ]] && env -i PATH="${SB%/*}:$PATH" SYSTEMROOT="${SYSTEMROOT:-}" "$SB" -c 'kill -KILL "$1"' _ "$w" </dev/null
}
drv_cleanup() { [[ -n "$P" ]] && kill -KILL "$P" 2>/dev/null; [[ -n "$LP" ]] && kill -KILL "$LP" 2>/dev/null; return 0; }
trap drv_cleanup EXIT; trap 'exit 143' TERM; trap 'exit 130' INT; trap 'exit 129' HUP
{ [[ -c /dev/ptmx ]] && exec 4<>/dev/ptmx; } 2>/dev/null || exec 4</dev/null
nap() { read -t "$1" -u 4 _ 2>/dev/null; (( $? > 128 )) || sleep "$1"; }   # no pty (FreeBSD): sleep
say() { printf '%s\n' "$1" >> "$OUT.drv"; }
ms() { local t="${EPOCHREALTIME/[.,]/}"; REPLY=$(( 10#$t / 1000 )); }
export KT_GATE_HB_TICKS=6 KT_GATE_HB_EVERY=1
# under job control: an async child of a shell without it starts with INT
# ignored — the INT case needs the launcher's own INT trap
set -m
if [[ $SC == parent ]]; then
    # an intermediate parent, killed at the Windows level below
    bash -c 'bash "$1" --root "$2" --out "$3" --timeout "$5" --bash "$4" all > "$3.stdout" 2>&1; echo "rc=$?" > "$3.lrc"' _ "$G" "$ROOT" "$OUT" "$SB" "$TMO" </dev/null &
elif [[ $SC == tparent ]]; then
    # the same through `timeout` (launch L2.1: a killed tool left
    # `timeout` + the gate running): the launcher's parent is the timeout,
    # which outlives the intermediate shell — the launcher watches that too
    bash -c '"$6" -k 10 300 bash "$1" --root "$2" --out "$3" --timeout "$5" --bash "$4" all > "$3.stdout" 2>&1; echo "rc=$?" > "$3.lrc"' _ "$G" "$ROOT" "$OUT" "$SB" "$TMO" "$TMOCMD" </dev/null &
else
    # segtree with --warm: the watchdog's segment-killed path removes seg-1.ckk too (G4 review R10)
    WARM=(); [[ $SC == segtree ]] && WARM=( --warm )
    bash "$G" --root "$ROOT" --out "$OUT" --timeout "$TMO" --bash "$SB" "${WARM[@]}" all > "$OUT.stdout" 2>&1 </dev/null &
fi
P=$!
set +m
cur=""
for (( i = 0; i < 600; i++ )); do
    { read -r cur < "$OUT/seg-1.cur"; } 2>/dev/null
    [[ "$cur" == "run 2 "* ]] && break
    nap 0.1
done
say "cur=$cur"
nap 0.5
LP="" LW=""
{ read -r _ _ LP LW _ < "$OUT/.kt_gate"; } 2>/dev/null
[[ $SC == parent || $SC == tparent ]] || [[ "$LP" == "$P" ]] || say "warn=launcher pid $LP is not the driver's child $P"
say "launcher=$LP $LW"
if [[ -n "$SAMPLER" ]]; then
    env -i PATH="${SB%/*}:$PATH" SYSTEMROOT="${SYSTEMROOT:-}" "$SB" "$SAMPLER" "$OUT" 3 "${G%/*}/../ktest_proc.sh" > "$OUT.sample" 2>&1 </dev/null
fi
ms; t0=$REPLY
case $SC in
    term) kill -TERM "$LP" ;;
    int) kill -INT "$LP" ;;
    wdtimeout) wdkill ;;
    wdterm) wdkill; nap 0.3; kill -TERM "$LP" ;;
    kill) kill -KILL "$LP" ;;
    taskkill) MSYS2_ARG_CONV_EXCL='*' "$TK" /F /PID "$LW" >/dev/null 2>&1 ;;
    tree) MSYS2_ARG_CONV_EXCL='*' "$TK" /F /T /PID "$LW" >/dev/null 2>&1 ;;
    # without taskkill (Linux, BSD; launch L2.1): SIGKILL of the parent / of
    # the segment main — the parent watch / the exec'd watchdog must act
    parent|tparent) if [[ -x "$TK" ]]; then pw=""; { read -r pw < "/proc/$P/winpid"; } 2>/dev/null
                MSYS2_ARG_CONV_EXCL='*' "$TK" /F /PID "$pw" >/dev/null 2>&1
            else kill -KILL "$P"; fi ;;
    segtree) if [[ -x "$TK" ]]; then sw=""; { read -r _ sw _ < "$OUT/seg-1.pid"; } 2>/dev/null
                 MSYS2_ARG_CONV_EXCL='*' "$TK" /F /T /PID "$sw" >/dev/null 2>&1
             else sp=""; { read -r sp _ < "$OUT/seg-1.pid"; } 2>/dev/null; kill -KILL "$sp"; fi ;;
esac
say "sent=$?"
gone=n
for (( i = 0; i < 600; i++ )); do
    if [[ -e "$OUT/seg-1.result" ]] && ! kill -0 "$LP" 2>/dev/null; then gone=y; break; fi
    nap 0.1
done
ms; say "ms=$(( REPLY - t0 ))"
say "gone=$gone"
if [[ $SC != parent && $SC != tparent ]]; then wait "$P" 2>/dev/null; say "lrc=$?"; P=""; else P=""; fi
LP=""
EOF

# the sampler: SAMPLER OUT SECONDS PROC — in the SEGMENT's runtime: the children of
# the segment's main and of its watchdog, sampled for SECONDS (cygwin: its
# /proc/PID/ppid; elsewhere the process table of PROC = ktest_proc.sh, L2.1)
cat > "$TMP/sample.sh" <<'EOF'
OUT=$1 S=$2 PROC=${3:-} main="" wd="" known="" extra="" n=0 f="" p="" pp=""
{ read -r main _ < "$OUT/seg-1.pid"; } 2>/dev/null
{ [[ -c /dev/ptmx ]] && exec 3<>/dev/ptmx; } 2>/dev/null || exec 3</dev/null
if [[ -r /proc/$BASHPID/ppid || -z "$PROC" ]]; then
for f in /proc/[0-9]*; do
    pp=""; { read -r pp < "$f/ppid"; } 2>/dev/null
    [[ "$pp" == "$main" ]] || continue
    p="${f#/proc/}"; known+=" $p"
    a=(); { mapfile -d '' -t a < "$f/cmdline"; } 2>/dev/null
    [[ "${a[*]}" == *" --watchdog "* ]] && wd="$p"
done
end=$(( SECONDS + S ))
while (( SECONDS < end )); do
    for f in /proc/[0-9]*; do
        pp=""; { read -r pp < "$f/ppid"; } 2>/dev/null
        [[ -n "$pp" && ( "$pp" == "$main" || "$pp" == "$wd" ) ]] || continue
        p="${f#/proc/}"
        [[ " $known " == *" $p "* || " $extra " == *" $p("* ]] || extra+=" $p(ppid $pp)"
    done
    n=$(( n + 1 ))
    read -r -t 0.01 -u 3 _ 2>/dev/null
done
else
source "$PROC"
kt_proc_napfd && exec 3<&"$REPLY"   # a pty, else a FIFO of its own: no sleep fork per sample
kt_proc_snapshot --cmd
for p in "${!KT_PROC_PP[@]}"; do
    [[ "${KT_PROC_PP[$p]}" == "$main" ]] || continue
    known+=" $p"
    [[ "${KT_PROC_CMD[$p]}" == *" --watchdog "* ]] && wd="$p"
done
end=$(( SECONDS + S ))
while (( SECONDS < end )); do
    kt_proc_snapshot
    for p in "${!KT_PROC_PP[@]}"; do
        pp="${KT_PROC_PP[$p]}"
        [[ -n "$pp" && ( "$pp" == "$main" || "$pp" == "$wd" ) ]] || continue
        [[ " $known " == *" $p "* || " $extra " == *" $p("* ]] || extra+=" $p(ppid $pp)"
    done
    n=$(( n + 1 ))
    read -r -t 0.01 -u 3 _ 2>/dev/null || (( $? > 128 )) || sleep 0.01
done
fi
printf 'main=%s wd=%s known=[%s] samples=%s extra=[%s]\n' "$main" "$wd" "${known# }" "$n" "${extra# }"
EOF

# the scan: SCAN PROC TEXT [kill] — this runtime's processes whose command line
# has TEXT (PROC = ktest_proc.sh: /proc or ps, launch L2.1)
cat > "$TMP/scan.sh" <<'EOF'
source "$1"; shift
# what is LEFT: a lingering busybox timeout watcher is waited out (~1 s)
if [[ "${2:-}" == kill ]]; then kt_proc_pids "$1"; else kt_proc_pids_gone "$1"; fi
out="$REPLY"
[[ "${2:-}" == kill && -n "$out" ]] && kill -KILL $out 2>/dev/null
printf '%s\n' "$out"
EOF

# kt052_scan B — REPLY = what is left of this file's runs in B's runtime
kt052_scan() {
    REPLY="$(env -i PATH="${1%/*}:$PATH" SYSTEMROOT="${SYSTEMROOT:-}" "$1" "$TMP/scan.sh" "$LIB/ktest_proc.sh" "$TMP/" 2>/dev/null </dev/null)"
}
kt052_scan_kill() {
    env -i PATH="${1%/*}:$PATH" SYSTEMROOT="${SYSTEMROOT:-}" "$1" "$TMP/scan.sh" "$LIB/ktest_proc.sh" "$TMP/" kill >/dev/null 2>&1 </dev/null
}
kt052_cleanup() {
    kt052_scan_kill "$BASH"
    [[ -n "$OTHER" ]] && kt052_scan_kill "$OTHER"
    return 0
}
eval "$(trap -p EXIT | sed "s/^trap -- '/trap -- 'trap \"\" TERM INT HUP; kt052_cleanup; /")"
[[ "$(trap -p EXIT)" == *kt052_cleanup* ]] || trap 'trap "" TERM INT HUP; kt052_cleanup' EXIT
trap 'trap "" TERM INT HUP; exit 143' TERM
trap 'trap "" TERM INT HUP; exit 130' INT
trap 'trap "" TERM INT HUP; exit 129' HUP

# kt052_strays B — REPLY = `strays.sh list --all --match TMP/` in B's runtime
# (the marker rule, independent of the command-line scan above, review R14)
kt052_strays() {
    local i
    # where `timeout` is busybox's, up to 3 s for none: its watcher lingers ~1 s;
    # elsewhere one look, as always (launch L2.1)
    for (( i = 0; i < 6; i++ )); do
        REPLY="$(env -i PATH="${1%/*}:$PATH" SYSTEMROOT="${SYSTEMROOT:-}" "$1" "$LIB/tools/strays.sh" list --all --match "$TMP/" 2>&1 </dev/null)"
        [[ "$REPLY" == "strays: none"* ]] && return 0
        kt_proc_bbtimeout || return 0
        sleep 0.5
    done
}

# kt052_case N SCEN LAUNCHER_BASH SEGMENT_BASH [sample] — one scenario
kt052_case() {
    local n="$1" sc="$2" lb="$3" sb="$4" smp="" o="$TMP/o$1" d k v l1 l2 lr st intr last left1 left2 bad="" lim tmo=120 out s1 s2
    local -A D=()
    [[ "${5:-}" == sample ]] && smp="$TMP/sample.sh"
    [[ "$sc" == wdtimeout ]] && tmo=6
    env -i PATH="${lb%/*}:$PATH" SYSTEMROOT="${SYSTEMROOT:-}" WINDIR="${WINDIR:-}" \
        "$KT_TIMEOUT" -k 10 150 "$lb" "$TMP/drv.sh" "$sc" "$sb" "$o" "$R" "$G" "$TK" "$smp" "$tmo" "$KT_TIMEOUT" </dev/null >/dev/null 2>&1
    while IFS='=' read -r k v; do D["$k"]="$v"; done < "$o.drv" 2>/dev/null
    l1=""; { while IFS='=' read -r k v; do [[ "$k" == verdict ]] && l1="$v"; done < "$o/cells/001/result"; } 2>/dev/null
    l2=""; lr=""; { while IFS='=' read -r k v; do [[ "$k" == verdict ]] && l2="$v"; [[ "$k" == reason ]] && lr="$v"; done < "$o/cells/002/result"; } 2>/dev/null
    st=""; { while IFS='=' read -r k v; do [[ "$k" == status ]] && st="$v"; done < "$o/seg-1.result"; } 2>/dev/null
    intr="$(cat "$o/INTERRUPTED" 2>/dev/null)"
    out="$(cat "$o.stdout" 2>/dev/null)"
    last=""; [[ -f "$o.stdout" ]] && last="$(tail -1 "$o.stdout")"
    kt052_scan "$BASH"; left1="$REPLY"
    left2=""; [[ -n "$OTHER" ]] && { kt052_scan "$OTHER"; left2="$REPLY"; }
    kt052_strays "$BASH"; s1="$REPLY"
    s2="strays: none"; [[ -n "$OTHER" ]] && { kt052_strays "$OTHER"; s2="$REPLY"; }
    [[ "${D[gone]:-}" == y ]] || bad+="[launcher/segment not done in 60 s] "
    [[ "${D[cur]:-}" == "run 2 "* ]] || bad+="[cell 2 never ran: ${D[cur]:-}] "
    [[ "$l1" == PASS ]] || bad+="[cell 1: $l1] "
    if [[ "$sc" != wdtimeout ]]; then
        [[ "$l2" == INTERRUPTED ]] || bad+="[cell 2: $l2 ($lr)] "
        [[ -n "$intr" ]] || bad+="[no INTERRUPTED] "
    fi
    [[ -z "$left1$left2" ]] || bad+="[left: ${left1:+$BASH_VERSION: $left1 }${left2:+other: $left2}] "
    [[ "$s1" == "strays: none"* && "$s2" == "strays: none"* ]] || bad+="[strays.sh list --all: ${s1//$'\n'/ } | ${s2//$'\n'/ }] "
    case "$sc" in
        term)   [[ "$st" == stopped && "${D[lrc]:-}" == 143 && "$last" == "__GATE__:INTERRUPTED:2:1:"* && "$intr" == *"launcher: TERM"* ]] || bad+="[term: status=$st lrc=${D[lrc]:-} last=$last] "
                lim=15000 ;;
        int)    [[ "$st" == stopped && "${D[lrc]:-}" == 130 && "$last" == "__GATE__:INTERRUPTED:2:1:"* && "$intr" == *"launcher: INT"* ]] || bad+="[int: status=$st lrc=${D[lrc]:-} last=$last] "
                lim=15000 ;;
        parent|tparent) [[ "$st" == stopped && "$intr" == *"parent is gone"* ]] || bad+="[$sc: status=$st] "
                lim=15000 ;;
        kill|taskkill|tree)
                [[ "$st" == stopped && "$intr" == *"heartbeat stale"* && "$lr" == *"heartbeat stale"* ]] || bad+="[$sc: status=$st reason=$lr] "
                lim=40000 ;;
        segtree) [[ "$st" == segment-killed && "$intr" == *segment-killed* && "${D[lrc]:-}" == 1 && "$last" == "__GATE__:FAIL:2:1:"* ]] || bad+="[segtree: status=$st lrc=${D[lrc]:-} last=$last] "
                 [[ -e "$o/seg-1.ckk" ]] && bad+="[segtree --warm: seg-1.ckk left] "
                lim=15000 ;;
        wdtimeout)
                [[ "$st" == done && "$l2" == TIMEOUT && "${D[lrc]:-}" == 1 && "$out" == *"a rescue watchdog was started"* \
                   && "$last" == "__GATE__:FAIL:2:1:0:0:0:1:0:"* ]] || bad+="[wdtimeout: status=$st cell 2=$l2 ($lr) lrc=${D[lrc]:-} last=$last] "
                lim=30000 ;;
        wdterm) [[ "$st" == stopped && "${D[lrc]:-}" == 143 && "$out" == *"a rescue watchdog was started"* && "$intr" == *"launcher: TERM"* ]] \
                   || bad+="[wdterm: status=$st lrc=${D[lrc]:-} last=$last] "
                lim=40000 ;;
    esac
    (( ${D[ms]:-99999} <= lim )) || bad+="[took ${D[ms]:-?} ms > $lim] "
    if [[ -n "$smp" ]]; then
        local s; s="$(cat "$o.sample" 2>/dev/null)"
        [[ "$s" =~ wd=[0-9]+\ known=\[[0-9]+\ [0-9]+\]\ samples=([0-9]+)\ extra=\[\]$ ]] && (( BASH_REMATCH[1] >= KT052_MINSAMP )) \
            || bad+="[forks in the segment while a cell ran: $s] "
        D[sample]="$s"
    fi
    if [[ -n "$bad" ]]; then
        kt_test_fail "$bad | drv: $(tr '\n' ' ' < "$o.drv" 2>/dev/null) | INTERRUPTED: ${intr//$'\n'/; } | seg log: $(tr '\n' ' ' < "$o/seg-1.log" 2>/dev/null | cut -c1-400) | out: ${out//$'\n'/ | }"
        kt052_cleanup
    else
        kt_test_pass "done in ${D[ms]} ms; status=$st; cell 2: $l2 ($lr)${D[sample]:+; ${D[sample]}}"
    fi
    rm -rf -- "$o" "$o".* 2>/dev/null
}

# directions and their scenarios: both directions across runtimes get the
# full set (INT and the watchdog-loss + TERM case once, from this runtime);
# the same-runtime segment gets SIGKILL, the tree kill, INT and both
# watchdog-loss cases (without a second runtime: everything here)
DIRS=()
if [[ -n "$OTHER" ]]; then
    OV="$("$OTHER" -c 'printf %s "${BASH_VERSION%%(*}"' 2>/dev/null </dev/null)"
    DIRS=( "$SELF_B|$OTHER|${BASH_VERSION%%(*} -> $OV|term int kill taskkill parent tree segtree wdterm"
           "$OTHER|$SELF_B|$OV -> ${BASH_VERSION%%(*}|term kill taskkill parent tree segtree"
           "$SELF_B|$SELF_B|${BASH_VERSION%%(*} -> ${BASH_VERSION%%(*}|kill tree int tparent wdtimeout wdterm" )
else
    DIRS=( "$SELF_B|$SELF_B|${BASH_VERSION%%(*} -> ${BASH_VERSION%%(*}|term int kill taskkill parent tparent tree segtree wdtimeout wdterm" )
fi
i=0
for dir in "${DIRS[@]}"; do
    IFS='|' read -r lb sb label scen <<< "$dir"
    for sc in $scen; do
        i=$(( i + 1 ))
        smp=""; [[ "$sc" == term ]] && smp=sample
        case "$sc" in
            term) what="TERM to the launcher: STOP, the cell stopped, rc 143, __GATE__:INTERRUPTED; no fork in the segment while the cell ran" ;;
            int) what="INT (Ctrl-C) to the launcher: STOP, the cell stopped, rc 130, __GATE__:INTERRUPTED" ;;
            kill) what="SIGKILL of the launcher: the heartbeat goes stale, the segment stops the cell" ;;
            taskkill) what="taskkill /F of the launcher: the heartbeat goes stale, the segment stops the cell" ;;
            parent) what="the launcher's parent killed at the Windows level: the parent watch stops the run" ;;
            tparent) what="\`timeout\` between them, the shell above it killed: the parent watch sees through the timeout, stops the run" ;;
            tree) what="taskkill /F /T of the launcher: nothing of the run survives it unseen" ;;
            segtree) what="taskkill /F /T of the SEGMENT: the exec'd watchdog stops the cell, segment-killed, the gate FAILs (rc 1)" ;;
            wdtimeout) what="the watchdog KILLed during a cell: the launcher starts a rescue watchdog, --timeout is still enforced (TIMEOUT)" ;;
            wdterm) what="the watchdog KILLed, then TERM to the launcher: a rescue watchdog stops the cell, the segment's result is written, nothing left" ;;
        esac
        kt_test_start "[$label] $what"
        if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"; continue; fi
        # parent / segtree have a POSIX form (SIGKILL); taskkill / tree have none
        if [[ ! -x "$TK" && ( "$sc" == taskkill || "$sc" == tree ) ]]; then
            kt_test_pass "skipped: no taskkill ($TK)"
            continue
        fi
        kt052_case "$i" "$sc" "$lb" "$sb" $smp
    done
done

kt052_cleanup
kt_test_start "nothing of this file's runs is left in either runtime (by its tmp path, and strays.sh list --all)"
kt052_scan "$BASH"; l1="$REPLY"; l2=""
[[ -n "$OTHER" ]] && { kt052_scan "$OTHER"; l2="$REPLY"; }
kt052_strays "$BASH"; s1="$REPLY"; s2="strays: none"
[[ -n "$OTHER" ]] && { kt052_strays "$OTHER"; s2="$REPLY"; }
if [[ -z "$l1$l2" && "$s1" == "strays: none"* && "$s2" == "strays: none"* ]]; then kt_test_pass "none"; else kt_test_fail "left: [$l1] [$l2] | $s1 | $s2"; fi

kt_test_log "052_GateSignals.sh completed"
