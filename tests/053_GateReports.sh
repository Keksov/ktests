#!/usr/bin/env bash
# GateReports (gate G3). ktests/tools/gate.sh's reports (GATE_PLAN 4.4, DG8):
# OUT/cells.tsv (the header, one row per planned cell, no tab/newline in a
# value) and OUT/summary.json (valid JSON — checked with node — with the
# gate/bashes/totals/cells/verdict fields), --compare (unchanged / changed
# totals / suites added and removed / LAST = the newest FINISHED run under
# the default OUT root / an unreadable or garbled base is a usage error, rc
# 2, before any run), an INTERRUPTED run still writing its partial reports,
# and the sanitising of names with a tab, a quote, a backslash, non-ASCII.
#
# All on fake roots (gate_fixtures/mkroot.sh) in this file's private tmp;
# each gate bounded by `timeout`; the end checks nothing carrying the tmp
# path is left.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GateReports" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
G="$LIB/tools/gate.sh"
MK="$LIB/tests/gate_fixtures/mkroot.sh"
unset KT_GATE_BASHES
V="${BASH_VERSION%%(*}"
NODE="$(type -P node 2>/dev/null)"
# git never walks out of this tmp (a fake root is not a repository of its own)
export GIT_CEILING_DIRECTORIES="$(cygpath -m "$TMP" 2>/dev/null || echo "$TMP")"
GC=( -c user.name=gate-test -c user.email=gate@test -c init.defaultBranch=main -c core.autocrlf=false )

kt053_pids() { kt_proc_pids_gone "$1"; }   # what is LEFT (/proc or ps; a busybox timeout watcher waited out — launch L2.1)
# kt053_gate OUTFILE ARGS... — gate.sh bounded; RC; the output in OUTFILE
kt053_gate() {
    local of="$1"; shift
    "$KT_TIMEOUT" -k 10 150 bash "$G" "$@" > "$of" 2>&1 < /dev/null
    RC=$?
}
kt053_kv() {
    local k v
    REPLY=""
    while IFS='=' read -r k v; do [[ "$k" == "$2" ]] && { REPLY="$v"; return 0; }; done < "$1"
    return 1
}
# kt053_tsv FILE — the rows of a cells.tsv: TSV_H (header fields), TSV_N
# (rows), TSV["R:COL"] (R = 1..), TSV_BAD (rows whose field count is not the
# header's, or with an empty field)
declare -A TSV=()
kt053_tsv() {
    local line r=0 i
    local -a F=()
    TSV=() TSV_H=() TSV_N=0 TSV_BAD=""
    { IFS= read -r line; IFS=$'\x1f' read -r -a TSV_H <<< "${line//$'\t'/$'\x1f'}"
      while IFS= read -r line; do
          r=$(( r + 1 ))
          IFS=$'\x1f' read -r -a F <<< "${line//$'\t'/$'\x1f'}"$'\x1f'
          (( ${#F[@]} == ${#TSV_H[@]} )) || TSV_BAD+="row $r: ${#F[@]} fields; "
          for (( i = 0; i < ${#TSV_H[@]}; i++ )); do
              [[ -n "${F[i]}" ]] || TSV_BAD+="row $r: empty ${TSV_H[i]}; "
              TSV["$r:${TSV_H[i]}"]="${F[i]}"
          done
      done; } < "$1"
    TSV_N=$r
}
# kt053_js JSONFILE EXPR... — REPLY = node's JSON.stringify of each EXPR
# (over `j` = the parsed file), one per line; rc 1 when node cannot parse it
cat > "$TMP/q.js" <<'EOF'
const fs = require("fs");
let j;
try { j = JSON.parse(fs.readFileSync(process.argv[2], "utf8")); }
catch (e) { console.log("PARSE-ERROR " + e.message); process.exit(1); }
for (const e of process.argv.slice(3)) {
    let v; try { v = eval(e); } catch (x) { v = "EVAL-ERROR " + x.message; }
    console.log(JSON.stringify(v));
}
EOF
QJS="$(cygpath -m "$TMP/q.js" 2>/dev/null || echo "$TMP/q.js")"
kt053_js() {
    local f="$1"; shift
    f="$(cygpath -m "$f" 2>/dev/null || echo "$f")"
    REPLY="$("$NODE" "$QJS" "$f" "$@" 2>&1)"
}
COLS="idx bash_version bash_path mode cwd suite repeat verdict rc total passed failed warn fail_lines strays attempts duration_ms log reruns rerun_pass flaky reason"

# ---- A: a mixed run: cells.tsv rows, summary.json ------------------------------
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RA="$TMP/rootA"; OA="$TMP/outA"
bash "$MK" "$RA" pass warn fail flaky empty
git "${GC[@]}" -C "$RA" init -q && git "${GC[@]}" -C "$RA" add -A && git "${GC[@]}" -C "$RA" commit -qm fixture
: > "$RA/untracked.txt"
kt053_gate "$TMP/a.out" --root "$RA" --out "$OA" --rerun-failed 1 all
oa="$(cat "$TMP/a.out")"
kt053_tsv "$OA/cells.tsv"
fi   # kt_need_timeout (setup)
kt_test_start "cells.tsv: the header (G2's result columns + reruns rerun_pass flaky reason), one row per cell in run order, no empty value"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
if [[ "${TSV_H[*]}" == "$COLS" && "$TSV_N" == 5 && -z "$TSV_BAD" \
      && "${TSV[1:suite]} ${TSV[2:suite]} ${TSV[3:suite]} ${TSV[4:suite]} ${TSV[5:suite]}" == "empty fail flaky pass warn" \
      && "${TSV[1:idx]}${TSV[2:idx]}${TSV[3:idx]}${TSV[4:idx]}${TSV[5:idx]}" == 12345 && "${TSV[1:bash_version]}" == "$V" ]]; then
    kt_test_pass "${#TSV_H[@]} columns, $TSV_N rows"
else
    kt_test_fail "header [${TSV_H[*]}] rows=$TSV_N bad=[$TSV_BAD] suites ${TSV[1:suite]} ${TSV[2:suite]} ${TSV[3:suite]}"
fi
fi   # kt_need_timeout
kt_test_start "cells.tsv: the verdicts and counts of a mixed run (NOTRUN, FAIL after a rerun, FLAKY, PASS, PASS warn=1); rc 1"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
if [[ "$RC" == 1 && "${TSV[1:verdict]}" == NOTRUN && "${TSV[2:verdict]}" == FAIL && "${TSV[2:reruns]}" == 1 \
      && "${TSV[2:rerun_pass]}" == 0 && "${TSV[2:total]}/${TSV[2:passed]}/${TSV[2:failed]}" == 5/2/3 && "${TSV[2:fail_lines]}" == 3 \
      && "${TSV[3:verdict]}" == FLAKY && "${TSV[3:reruns]}" == 1 && "${TSV[3:rerun_pass]}" == 1 && "${TSV[3:flaky]}" == 002_flaky.sh \
      && "${TSV[3:total]}/${TSV[3:passed]}" == 4/3 && "${TSV[4:verdict]}" == PASS && "${TSV[4:flaky]}" == - && "${TSV[4:reason]}" == - \
      && "${TSV[5:verdict]}" == PASS && "${TSV[5:warn]}" == 1 && "${TSV[4:log]}" == cells/004/log.txt && "${TSV[1:mode]}" == threaded \
      && "${TSV[1:cwd]}" == neutral && "${TSV[1:repeat]}" == 1 ]]; then
    kt_test_pass "${TSV[2:verdict]} ${TSV[3:verdict]} (${TSV[3:reason]})"
else
    kt_test_fail "rc=$RC | $(tr '\t' '|' < "$OA/cells.tsv" | tr '\n' ' ') | ${oa//$'\n'/ | }"
fi
fi   # kt_need_timeout
if ! kt_need_timeout; then
    kt_test_start "summary.json is valid JSON (node)"
    kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
elif [[ -n "$NODE" ]]; then
    # the OUT in the mixed C:/ form with cygpath, an absolute POSIX path without (launch L2.1)
    outform='j.gate.out.indexOf(":") == 1'; command -v cygpath >/dev/null 2>&1 || outform='j.gate.out.startsWith("/")'
    kt053_js "$OA/summary.json" 'Object.keys(j).join(",")' 'Object.keys(j.gate).join(",")' "j.gate.out.endsWith(\"outA\") && j.gate.root.endsWith(\"rootA\") && $outform" \
        'j.gate.argv' 'j.gate.repos' 'j.bashes[0].version' 'j.totals' 'j.cells.length' 'j.cells[2].flaky' 'j.cells[2].verdict' \
        'j.cells[1].fails.length' 'j.verdict+" "+j.exit' 'j.machine' 'typeof j.cells[0].idx+" "+typeof j.cells[0].rc+" "+j.cells[0].attempt1' \
        '/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d{4}$/.test(j.gate.started) && j.gate.finished >= j.gate.started' 'j.gate.options.rerun_failed'
    mapfile -t J <<< "$REPLY"
    kt_test_start "summary.json is valid JSON (node) with gate{started,finished,root,out,argv,repos{name:{sha,dirty}},options}, bashes, totals per bash, cells, verdict"
    sha="$(git -C "$RA" rev-parse --short HEAD)"
    want_tot="{\"$V\":{\"cells\":5,\"PASS\":2,\"FAIL\":1,\"FLAKY\":1,\"ENV\":0,\"TIMEOUT\":0,\"STRAY\":0,\"CRASH\":0,\"NOTRUN\":1,\"INTERRUPTED\":0,\"SKIPPED\":0,\"UNSTARTED\":0,\"passed_tests\":9,\"total_tests\":13,"
    if [[ "${J[0]}" == '"gate,bashes,totals,cells,machine,exit,verdict"' && "${J[1]}" == '"started,finished,root,out,argv,repos,options"' \
          && "${J[2]}" == true \
          && "${J[3]}" == *'"--rerun-failed","1","all"]' && "${J[4]}" == "{\"rootA\":{\"sha\":\"$sha\",\"dirty\":true}}" \
          && "${J[5]}" == "\"$V\"" && "${J[6]}" == "$want_tot"* && "${J[7]}" == 5 && "${J[8]}" == '["002_flaky.sh"]' \
          && "${J[9]}" == '"FLAKY"' && "${J[10]}" == 3 && "${J[11]}" == '"FAIL 1"' && "${J[12]}" == "\"${oa##*$'\n'}\"" \
          && "${J[13]}" == '"number number null"' && "${J[14]}" == true && "${J[15]}" == 1 ]]; then
        kt_test_pass "${J[0]}"
    else
        kt_test_fail "${REPLY//$'\n'/ | }"
    fi
else
    kt_test_start "summary.json is valid JSON (node)"
    kt_test_pass "skipped: no node on this machine"
fi
kt_test_start "the reports are written before the verdict line; FINISHED written; the cell results unchanged by them"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt053_kv "$OA/cells/003/result" flaky; fl="$REPLY"
if [[ -s "$OA/cells.tsv" && -s "$OA/summary.json" && -f "$OA/FINISHED" && "$fl" == 002_flaky.sh \
      && "$oa" == *$'\n'"gate FAIL  out="*$'\n'"__GATE__:FAIL:5:2:1:1:0:0:0:9:13" ]]; then
    kt_test_pass "${oa##*$'\n'}"
else
    kt_test_fail "flaky=[$fl] | ${oa//$'\n'/ | }"
fi
fi   # kt_need_timeout

# ---- B: --compare -----------------------------------------------------------------
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RB="$TMP/rootB"; OB1="$TMP/outB1"
bash "$MK" "$RB" pass warn
kt053_gate "$TMP/b1.out" --root "$RB" --out "$OB1" all; rb1=$RC
kt053_gate "$TMP/b2.out" --root "$RB" --out "$TMP/outB2" --compare "$OB1" all; rb2=$RC
ob2="$(cat "$TMP/b2.out")"
fi   # kt_need_timeout (setup)
kt_test_start "--compare DIR, the same tree: 'totals unchanged', rc 0; compare.txt; summary.json compare.unchanged"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
cj=""
if [[ -n "$NODE" ]]; then kt053_js "$TMP/outB2/summary.json" 'j.compare.unchanged' 'j.compare.changes.length' 'j.compare.base'; cj="${REPLY//$'\n'/ }"; fi
if [[ "$rb1" == 0 && "$rb2" == 0 && "$ob2" == *"gate compare: base "*"/outB1/cells.tsv"* \
      && "$ob2" == *$'\n'"gate compare "*"/outB1: totals unchanged ($V 4/4)"$'\n'"gate PASS  out="* \
      && "$(head -1 "$TMP/outB2/compare.txt")" == *"totals unchanged"* && ( -z "$NODE" || "$cj" == "true 0 \""*"/outB1\"" ) ]]; then
    kt_test_pass "$(grep 'totals unchanged' "$TMP/b2.out")"
else
    kt_test_fail "rc=$rb1/$rb2 json=[$cj] | ${ob2//$'\n'/ | }"
fi
fi   # kt_need_timeout
# a changed total (a test more in pass), a suite added (flaky... no: fail, new id),
# a suite removed (warn): compare is informational — the exit stays the run's
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
cp "$RB/pass/tests/002_b.sh" "$RB/pass/tests/003_c.sh"
mkdir -p "$RB/newsuite/tests"; cp "$LIB/tests/gate_fixtures/pass/suite/"* "$RB/newsuite/tests/"
kt053_gate "$TMP/b3.out" --root "$RB" --out "$TMP/outB3" --compare "$OB1/cells.tsv" newsuite pass; rb3=$RC
ob3="$(cat "$TMP/b3.out")"
fi   # kt_need_timeout (setup)
kt_test_start "--compare FILE.tsv: changed total/passed, a suite added; a base suite this run does not plan is reported apart, not a change, not in the sums (G4 review R6); informational (rc 0)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
cj=""
if [[ -n "$NODE" ]]; then kt053_js "$TMP/outB3/summary.json" 'j.compare.unchanged' 'j.compare.changes.map(c=>c.kind+":"+c.suite+":"+JSON.stringify(c.base)+":"+JSON.stringify(c.new)).join(" ")' 'j.compare.base_only.map(c=>c.suite+":"+JSON.stringify(c.base)).join(" ")'; cj="${REPLY//$'\n'/ }"; fi
if [[ "$rb3" == 0 && "$ob3" == *"gate compare "*"/outB1/cells.tsv: 2 change(s) ($V 3/3 -> 7/7); 1 base key(s) not in this run, not compared"* \
      && "$ob3" == *$'\n'"        $V threaded neutral pass  total 3 -> 4  passed 3 -> 4"* \
      && "$ob3" == *$'\n'"        $V threaded neutral newsuite  added (3/3)"* \
      && "$ob3" == *$'\n'"        $V threaded neutral warn  base only (was 1/1): not in this run"* \
      && ( -z "$NODE" || "$cj" == 'false "added:newsuite:null:{\"total\":3,\"passed\":3} changed:pass:{\"total\":3,\"passed\":3}:{\"total\":4,\"passed\":4}" "warn:{\"total\":1,\"passed\":1}"' ) ]]; then
    kt_test_pass "2 changes + 1 base-only key"
else
    kt_test_fail "rc=$rb3 json=[$cj] | ${ob3//$'\n'/ | }"
fi
fi   # kt_need_timeout
kt_test_start "--compare: only a base-only key differs -> 'totals unchanged' over the planned keys; a base row that never ran there (UNSTARTED, '-') is 'not run in the base', not 'added' (G4 review R6, F10b)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
kt053_gate "$TMP/b4.out" --root "$RB" --out "$TMP/outB4" --compare "$OB1" warn; rb4=$RC
ob4="$(cat "$TMP/b4.out")"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{for(i=1;i<=NF;i++)c[$i]=i; print; next} $c["suite"]=="pass"{$c["verdict"]="UNSTARTED"; $c["total"]="-"; $c["passed"]="-"} {print}' "$OB1/cells.tsv" > "$TMP/unstarted.tsv"
kt053_gate "$TMP/b5.out" --root "$RB" --out "$TMP/outB5" --compare "$TMP/unstarted.tsv" pass; rb5=$RC
ob5="$(cat "$TMP/b5.out")"
if [[ "$rb4" == 0 && "$ob4" == *"/outB1: totals unchanged ($V 1/1); 1 base key(s) not in this run, not compared"* \
      && "$rb5" == 0 && "$ob5" == *"/unstarted.tsv: 1 change(s) ($V 0/0 -> 4/4); 1 base key(s) not in this run, not compared"* \
      && "$ob5" == *$'\n'"        $V threaded neutral pass  not run in the base (now 4/4)"* && "$ob5" != *added* ]]; then
    kt_test_pass "$(grep 'gate compare ' "$TMP/b4.out" | tail -1) | $(grep '^gate compare ' "$TMP/b5.out" | tail -1)"
else
    kt_test_fail "rc=$rb4/$rb5 | ${ob4//$'\n'/ | } || ${ob5//$'\n'/ | }"
fi
fi   # kt_need_timeout
# LAST: the newest FINISHED run under the default OUT root (TMPDIR/kt-gate); a
# newer dir without FINISHED is no candidate
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RT="$TMP/rt"; mkdir -p "$RT"
TMPDIR="$RT" kt053_gate "$TMP/l1.out" --root "$RB" pass; rl1=$RC
l1dir="$(ls -d "$RT/kt-gate"/*/ 2>/dev/null | head -1)"; l1dir="${l1dir%/}"
mkdir -p "$RT/kt-gate/zz-unfinished"
printf 'kt-gate 2 1 0 %s 1 none\n' "$(( EPOCHSECONDS + 100 ))" > "$RT/kt-gate/zz-unfinished/.kt_gate"
cp "$l1dir/cells.tsv" "$RT/kt-gate/zz-unfinished/cells.tsv"
TMPDIR="$RT" kt053_gate "$TMP/l2.out" --root "$RB" --compare LAST pass; rl2=$RC
ol2="$(cat "$TMP/l2.out")"
fi   # kt_need_timeout (setup)
kt_test_start "--compare LAST = the newest FINISHED run under \${TMPDIR}/kt-gate (an unfinished newer one is skipped)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
if [[ "$rl1" == 0 && "$rl2" == 0 && -n "$l1dir" && "$ol2" == *"gate compare LAST ("*"${l1dir##*/}): totals unchanged ($V 4/4)"* \
      && "$ol2" != *zz-unfinished* ]]; then
    kt_test_pass "$(grep 'gate compare LAST' "$TMP/l2.out")"
else
    kt_test_fail "rc=$rl1/$rl2 l1=[$l1dir] | ${ol2//$'\n'/ | }"
fi
fi   # kt_need_timeout
# kt053_fake DIR STAMP TSV — a finished gate run dir (CREATED=0: rotation never removes it)
kt053_fake() {
    mkdir -p "$1"; printf 'kt-gate 2 1 0 %s 0 none\n' "$2" > "$1/.kt_gate"; : > "$1/FINISHED"; cp "$3" "$1/cells.tsv"
}
kt_test_start "--compare LAST: an unreadable newest candidate is skipped (a note), a same-stamp tie goes to the later name; no base at all -> [WARN], the run goes on without a compare, rc 0 (G4 review R3)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
RT2="$TMP/rt2"; S0=$(( EPOCHSECONDS + 1000 ))
{ head -1 "$OB1/cells.tsv"; printf '1\t2\t3\n'; } > "$TMP/garbled_last.tsv"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1{for(i=1;i<=NF;i++)c[$i]=i; print; next} $c["suite"]=="pass"{$c["total"]=9; $c["passed"]=9} {print}' "$l1dir/cells.tsv" > "$TMP/nine.tsv"
kt053_fake "$RT2/kt-gate/zz-bad" $(( S0 + 200 )) "$TMP/garbled_last.tsv"
kt053_fake "$RT2/kt-gate/t-a" $(( S0 + 100 )) "$l1dir/cells.tsv"
kt053_fake "$RT2/kt-gate/t-b" $(( S0 + 100 )) "$TMP/nine.tsv"
TMPDIR="$RT2" kt053_gate "$TMP/l3.out" --root "$RB" --out "$TMP/outL3" --compare LAST pass; rl3=$RC
ol3="$(cat "$TMP/l3.out")"
mkdir -p "$TMP/rt_none"
TMPDIR="$TMP/rt_none" kt053_gate "$TMP/l4.out" --root "$RB" --out "$TMP/outL4" --compare LAST pass; rl4=$RC
ol4="$(cat "$TMP/l4.out")"
cj=""
if [[ -n "$NODE" ]]; then kt053_js "$TMP/outL4/summary.json" 'typeof j.compare' 'j.verdict'; cj="${REPLY//$'\n'/ }"; fi
if [[ "$rl3" == 0 && "$ol3" == *"gate compare: a LAST candidate skipped (unreadable): zz-bad: "*"is garbled"* \
      && "$ol3" == *"gate compare LAST ("*"/t-b): 1 change(s) ($V 9/9 -> 4/4)"* \
      && "$rl4" == 0 && "$ol4" == *"[WARN] --compare LAST: no base (no readable finished gate run under "*"running without a compare"* \
      && "$ol4" != *"gate compare LAST ("* && "$ol4" == *$'\n'"__GATE__:PASS:1:1:"* && ( -z "$NODE" || "$cj" == "\"undefined\" \"PASS\"" ) ]]; then
    kt_test_pass "$(grep -m1 'skipped' "$TMP/l3.out") | $(grep -m1 'WARN' "$TMP/l4.out")"
else
    kt_test_fail "rc=$rl3/$rl4 json=[$cj] | ${ol3//$'\n'/ | } || ${ol4//$'\n'/ | }"
fi
fi   # kt_need_timeout
kt_test_start "an unreadable / garbled explicit base is a usage error (rc 2) before any run — no OUT dir"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
mkdir -p "$TMP/emptydir"
printf 'a\tb\n1\t2\n' > "$TMP/notgate.tsv"
{ head -1 "$OB1/cells.tsv"; printf '1\t2\t3\n'; } > "$TMP/garbled.tsv"
{ head -1 "$OB1/cells.tsv"; sed -n 2p "$OB1/cells.tsv" | awk -F'\t' 'BEGIN{OFS="\t"} {$10="x"; print}'; } > "$TMP/garbled2.tsv"
{ head -1 "$OB1/cells.tsv"; sed -n 2p "$OB1/cells.tsv" | awk -F'\t' 'BEGIN{OFS="\t"} {$10="1234567890123456789"; print}'; } > "$TMP/garbled3.tsv"
: > "$TMP/empty.tsv"
bad=""; n=0
for base in "$TMP/nonexistent" "$TMP/emptydir" "$TMP/notgate.tsv" "$TMP/garbled.tsv" "$TMP/garbled2.tsv" "$TMP/garbled3.tsv" "$TMP/empty.tsv"; do
    n=$(( n + 1 ))
    kt053_gate "$TMP/u.out" --root "$RB" --out "$TMP/never$n" --compare "$base" pass
    o="$(cat "$TMP/u.out")"
    [[ "$RC" == 2 && "$o" == "gate: --compare "* && ! -e "$TMP/never$n" ]] || bad+="[$base -> rc $RC: ${o:0:160}] "
done
if [[ -z "$bad" ]]; then kt_test_pass "$n bases refused"; else kt_test_fail "$bad"; fi
fi   # kt_need_timeout

# ---- C: an INTERRUPTED run writes its partial reports ------------------------------
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RC_="$TMP/rootC"; OC="$TMP/outC"
bash "$MK" "$RC_" pass=a1 hang=b2
"$KT_TIMEOUT" -k 10 120 bash "$G" --root "$RC_" --out "$OC" --timeout 60 all > "$TMP/c.out" 2>&1 < /dev/null &
PC=$!
for (( i = 0; i < 300; i++ )); do
    cur=""; { read -r cur < "$OC/seg-1.cur"; } 2>/dev/null
    [[ -f "$OC/cells/001/result" && "$cur" == "run 2 "* ]] && break
    sleep 0.1
done
sleep 0.5
lp=""; { read -r _ _ lp _ < "$OC/.kt_gate"; } 2>/dev/null
[[ -n "$lp" ]] && kill -TERM "$lp" 2>/dev/null
wait "$PC"; rcc=$?
kt053_tsv "$OC/cells.tsv"
fi   # kt_need_timeout (setup)
kt_test_start "INTERRUPTED (TERM): exit 143, cells.tsv with what finished (1 PASS, 2 INTERRUPTED), summary.json, no FINISHED"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
cj=""
if [[ -n "$NODE" ]]; then kt053_js "$OC/summary.json" 'j.verdict+" "+j.exit' 'j.cells.map(c=>c.verdict).join(",")' "j.totals['$V'].INTERRUPTED"; cj="${REPLY//$'\n'/ }"; fi
if [[ "$rcc" == 143 && "$TSV_N" == 2 && "${TSV[1:verdict]}" == PASS && "${TSV[2:verdict]}" == INTERRUPTED && -z "$TSV_BAD" \
      && -f "$OC/INTERRUPTED" && ! -f "$OC/FINISHED" && ( -z "$NODE" || "$cj" == '"INTERRUPTED 143" "PASS,INTERRUPTED" 1' ) ]]; then
    kt_test_pass "${TSV[1:verdict]} ${TSV[2:verdict]} json=[$cj]"
else
    kt_test_fail "rc=$rcc rows=$TSV_N bad=[$TSV_BAD] json=[$cj] | $(tr '\n' ' ' < "$TMP/c.out" | cut -c1-900)"
fi
fi   # kt_need_timeout

# ---- D: sanitising -------------------------------------------------------------------
# a suite id with a quote (single mode: the threaded runner cannot take a quote
# in its path — a known runner limit), a failed file whose name holds a tab and
# a quote, a [FAIL] message with a quote, a backslash, a tab and non-ASCII
if kt_need_timeout; then   # setup: needs timeout (its cases SKIP without it)
RD="$TMP/rootD"; OD="$TMP/outD"
bash "$MK" "$RD" 'pass=q"z'
FD="$RD/q\"z/tests/002_t"$'\t''a"b.sh'
rm -f "$RD/q\"z/tests/002_b.sh"
printf '%s\n' 'source "$KTEST_SOURCE_PATH"' 'kt_test_init "GfxQuote" "$KT_TESTS_DIR" "$@"' \
    'kt_test_start "q"; kt_test_fail $'"'"'a "quoted" back\\slash\ttab and \xc3\xbcn'"'"'' > "$FD"
kt053_gate "$TMP/d.out" --root "$RD" --out "$OD" --mode single --rerun-failed 1 all
kt053_tsv "$OD/cells.tsv"
fi   # kt_need_timeout (setup)
kt_test_start "sanitising: cells.tsv keeps one line per cell and its field count (tab -> space) with a quoted suite id, a tab in a file name"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
nl=$(( $(wc -l < "$OD/cells.tsv") ))   # BSD wc pads the count (launch L2.1)
if [[ "$RC" == 1 && "$nl" == 2 && "$TSV_N" == 1 && -z "$TSV_BAD" && "${TSV[1:suite]}" == 'q"z' \
      && "${TSV[1:reason]}" == '1 rerun(s) of 002_t a"b.sh failed (last: FAIL 0/1)' ]]; then
    kt_test_pass "suite [${TSV[1:suite]}] reason [${TSV[1:reason]}]"
else
    kt_test_fail "rc=$RC lines=$nl bad=[$TSV_BAD] suite=[${TSV[1:suite]}] reason=[${TSV[1:reason]}] | $(tr '\n' ' ' < "$TMP/d.out" | cut -c1-600)"
fi
fi   # kt_need_timeout
kt_test_start "sanitising: summary.json escapes quote / backslash / tab, passes UTF-8 through (node reads back the exact strings)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
elif [[ -n "$NODE" ]]; then
    kt053_js "$OD/summary.json" 'j.cells[0].suite' 'j.cells[0].fails[0]' 'j.cells[0].reason'
    want1='"q\"z"'
    want2='"[FAIL] a \"quoted\" back\\slash\ttab and '$'\xc3\xbc''n (002_t\ta\"b.sh)"'
    want3='"1 rerun(s) of 002_t\ta\"b.sh failed (last: FAIL 0/1)"'
    mapfile -t J <<< "$REPLY"
    if [[ "${J[0]}" == "$want1" && "${J[1]}" == "$want2" && "${J[2]}" == "$want3" ]]; then
        kt_test_pass "${J[1]}"
    else
        kt_test_fail "got [${J[*]}] want [$want1 $want2 $want3]"
    fi
else
    kt_test_pass "skipped: no node on this machine"
fi
kt_test_start "summary.json is valid UTF-8 for a strict decoder: a [FAIL] message with the bytes \xff\xfe gets U+FFFD, valid UTF-8 stays (G4 review R7)"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
RU="$TMP/rootU"; OU="$TMP/outU"
bash "$MK" "$RU" pass=u8
rm -f "$RU/u8/tests/002_b.sh"
printf '%s\n' 'source "$KTEST_SOURCE_PATH"' 'kt_test_init "GfxBytes" "$KT_TESTS_DIR" "$@"' \
    'kt_test_start "b"; kt_test_fail $'"'"'bad \xff\xfe and \xc3\xbc ok'"'"'' > "$RU/u8/tests/002_bytes.sh"
kt053_gate "$TMP/u8.out" --root "$RU" --out "$OU" all
if [[ -n "$NODE" ]]; then
    js="$("$NODE" -e 'const b=require("fs").readFileSync(process.argv[1]); let s; try { s=new TextDecoder("utf-8",{fatal:true}).decode(b); } catch(e) { console.log("NOT UTF-8: "+e.message); process.exit(0); } const j=JSON.parse(s); console.log(JSON.stringify(j.cells[0].fails[0]))' \
        "$(cygpath -m "$OU/summary.json" 2>/dev/null || echo "$OU/summary.json")" 2>&1)"
    want='"[FAIL] bad '$'\xef\xbf\xbd\xef\xbf\xbd'' and '$'\xc3\xbc'' ok (002_bytes.sh)"'
    if [[ "$RC" == 1 && "$js" == "$want" ]]; then kt_test_pass "$js"; else kt_test_fail "rc=$RC got [$js] want [$want]"; fi
else
    kt_test_pass "skipped: no node on this machine"
fi
fi   # kt_need_timeout
kt_test_start "the escape function: every control character, newline, quote, backslash; the tsv value function: no tab/newline/CR, '' -> -"
S=$'l1\nl2\r\t"q"\\b\x01\x02\x07\x08\x0b\x0c\x1b\x1f end \xc3\xa4\xe2\x82\xac'
printf '%s' "$S" > "$TMP/raw.txt"
( source "$G" || exit 9
  _kt_gate_jstr "$S"; printf '{"s": %s}\n' "$REPLY" > "$TMP/esc.json"
  _kt_gate_tsv_val $'a\tb\nc\rd'; printf '%s|' "$REPLY"; _kt_gate_tsv_val ""; printf '%s\n' "$REPLY" ) > "$TMP/tv.out" 2>&1
if [[ -n "$NODE" ]]; then
    # the raw file's path reaches node through the environment (an argument
    # holding a /path would be rewritten by the MSYS argument conversion)
    KT053_RAW="$(cygpath -m "$TMP/raw.txt" 2>/dev/null || echo "$TMP/raw.txt")" \
        kt053_js "$TMP/esc.json" "j.s === require('fs').readFileSync(process.env.KT053_RAW,'utf8')" 'j.s.length'
    js="${REPLY//$'\n'/ }"
else
    js="true skipped"
fi
if [[ "$js" == "true "* && "$(cat "$TMP/tv.out")" == "a b c d|-" && "$(cat "$TMP/esc.json")" != *$'\x01'* ]]; then
    kt_test_pass "node round trip: $js"
else
    kt_test_fail "node=[$js] tsv=[$(cat "$TMP/tv.out")] json=[$(cat -v "$TMP/esc.json")]"
fi

kt_test_start "human lines: a suite id's control characters become '?', a long id is cut at 40 chars with '...'; --help prints the header comment only (G4 review R9)"
L60="$(printf 'x%.0s' {1..60})"
hs="$( source "$G" || exit 9
    _kt_gate_hsuite $'a\tb\nc\x1bd'; printf '%s|' "$REPLY"
    _kt_gate_hsuite "kcl/$L60"; printf '%s|%s' "$REPLY" "${#REPLY}" )"
hl="$(bash "$G" --help 2>&1)"
if [[ "$hs" == "a?b?c?d|kcl/${L60:0:33}...|40" && "$hl" == "gate.sh — the phase gate"* && "$hl" != *_KT_GATE_SOURCED* && "$hl" != *$'\n'"fi"* ]]; then
    kt_test_pass "$hs | help: $(wc -l <<< "$hl") lines"
else
    kt_test_fail "[$hs] help tail: $(tail -3 <<< "$hl" | tr '\n' ' ')"
fi
kt_test_start "nothing of this file's gates is left (by its tmp path)"
kt053_pids "$TMP"
if [[ -z "$REPLY" ]]; then kt_test_pass "none"; else kt_test_fail "left: $REPLY"; fi

kt_test_log "053_GateReports.sh completed"
