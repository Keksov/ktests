#!/usr/bin/env bash
# GateCli (gate G2). ktests/tools/gate.sh's command line: options and their
# values (the G3 options' too), suite resolution (all / id / unique
# last component; unknown and ambiguous are usage errors, rc 2, before
# anything runs — no OUT dir is made), KT_GATE_BASHES, the parent-watch
# opt-out (--nohup, nohup), the spec file a segment gets (paths, args, the
# caller's locale), the OUT marker files and the rotation of old runs.
#
# Every gate here runs on a fake root (gate_fixtures/mkroot.sh) in this
# file's private tmp; nothing runs outside it. Process hygiene: each gate is
# bounded by `timeout`, and the end checks that nothing carrying this file's
# tmp path is left (gate.sh's own processes carry it in their command lines).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GateCli" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
G="$LIB/tools/gate.sh"
CYGP=""; command -v cygpath >/dev/null 2>&1 && CYGP=1   # Windows (cygwin) path forms only with cygpath (launch L2.1)
MK="$LIB/tests/gate_fixtures/mkroot.sh"
unset KT_GATE_BASHES

# kt050_pids TEXT — REPLY = the pids (not this shell) whose command line contains TEXT
kt050_pids() { kt_proc_pids_gone "$1"; }   # what is LEFT (/proc or ps; a busybox timeout watcher waited out — launch L2.1)

# kt050_gate OUTFILE ARGS... — run gate.sh (bounded), rc in RC, output in OUTFILE
kt050_gate() {
    local of="$1"; shift
    timeout -k 10 120 bash "$G" "$@" > "$of" 2>&1 < /dev/null
    RC=$?
}

# a fake root: suites a/x, b/x (same last component), c/uniq, kcl and kcl/sub
F="$TMP/root"
bash "$MK" "$F" pass=a/x pass=b/x pass=c/uniq pass=kcl pass=kcl/sub warn=w

# ---- options -----------------------------------------------------------------
kt_test_start "--help prints the usage, rc 0"
kt050_gate "$TMP/h.out" --help
o="$(cat "$TMP/h.out")"
if [[ "$RC" == 0 && "$o" == *"gate.sh [options] SUITE... [-- ARGS...]"* && "$o" == *"__GATE__:VERDICT"* ]]; then
    kt_test_pass "rc 0, $(wc -l < "$TMP/h.out") lines"
else
    kt_test_fail "rc=$RC: ${o:0:300}"
fi

kt_test_start "usage errors: rc 2 and a message (no suite, unknown option, bad values, a value for a flag, internal roles)"
bad=""
while IFS='|' read -r want args; do
    read -r -a av <<< "$args"
    kt050_gate "$TMP/u.out" --root "$F" "${av[@]}"
    o="$(cat "$TMP/u.out")"
    [[ "$RC" == 2 && "$o" == *"$want"* ]] || bad+="[$args -> rc $RC: ${o:0:120}] "
done <<'EOF'
no suite given|
unknown option --bogus|--bogus all
--mode must be threaded, single or both|--mode fast all
--cwd must be neutral, suite or both|--cwd up all
--workers needs a number|--workers 0 all
--timeout needs whole seconds|--timeout 1.5 all
--timeout needs a value|all --timeout
--keep takes no value|--keep=1 all
--nohup takes no value|--nohup=yes all
--segment is internal|all --segment x
--bash /nonexistent/bash is not an executable file|--bash /nonexistent/bash all
EOF
if [[ -z "$bad" ]]; then kt_test_pass "11 cases"; else kt_test_fail "$bad"; fi

kt_test_start "the G3 options' values: rc 2 and a message for a bad one (no 'not yet implemented' left)"
bad=""
while IFS='|' read -r want args; do
    read -r -a av <<< "$args"
    kt050_gate "$TMP/g3.out" --root "$F" "${av[@]}"
    o="$(cat "$TMP/g3.out")"
    [[ "$RC" == 2 && "$o" == *"$want"* && "$o" != *"not yet implemented"* ]] || bad+="[$args -> rc $RC: ${o:0:120}] "
done <<'EOT'
--repeat needs a number 1-9999|--repeat 0 all
--repeat needs a number 1-9999|--repeat x all
--rerun-failed needs a number 0-99|--rerun-failed -1 all
--rerun-failed needs a value|all --rerun-failed
--compare needs a value|all --compare
--changed takes no value|--changed=1 all
--parallel takes no value|--parallel=1 all
--fail-fast takes no value|--fail-fast=yes all
--warm takes no value|--warm=1 all
--mode must be threaded, single or both|--mode=all all
--cwd must be neutral, suite or both|--cwd up all
no suite given (name suites, or all, or --changed)|--repeat 2
EOT
if [[ -z "$bad" ]]; then kt_test_pass "12 cases"; else kt_test_fail "$bad"; fi

# ---- suite resolution ----------------------------------------------------------
# the resolver alone (gate.sh sourced: nothing runs on source)
kt050_resolve() {
    ( source "$G" || exit 9
      kt_gate_parse --root "$F" "$@"
      _KT_GATE_CYGPATH=""; command -v cygpath >/dev/null 2>&1 && _KT_GATE_CYGPATH=1
      kt_gate_root
      kt_gate_resolve
      printf '%s\n' "${_KT_GATE_SEL[*]}" ) 2>&1
}
kt_test_start "resolution: all = discovery order; ids; a unique last component; order and duplicates of the arguments do not matter"
r1="$(kt050_resolve all)"; r2="$(kt050_resolve uniq a/x kcl/sub a/x)"; r3="$(kt050_resolve kcl c/uniq/tests/ ./w)"
r4="$(kt050_resolve sub)"
if [[ "$r1" == "a/x b/x c/uniq kcl kcl/sub w" && "$r2" == "a/x c/uniq kcl/sub" && "$r3" == "c/uniq kcl w" && "$r4" == "kcl/sub" ]]; then
    kt_test_pass "all=[$r1] [$r2] [$r3] [$r4]"
else
    kt_test_fail "all=[$r1] uniq,a/x,kcl/sub,a/x=[$r2] kcl,c/uniq/tests/,./w=[$r3] sub=[$r4]"
fi

kt_test_start "resolution: unknown and ambiguous suites are usage errors (rc 2) before anything runs — no OUT dir"
kt050_gate "$TMP/r.out" --root "$F" --out "$TMP/never1" a/x zzz
o1="$(cat "$TMP/r.out")"; rc1=$RC
kt050_gate "$TMP/r.out" --root "$F" --out "$TMP/never2" x
o2="$(cat "$TMP/r.out")"; rc2=$RC
if [[ "$rc1" == 2 && "$o1" == *'unknown suite "zzz"'* && "$o1" == *"a/x b/x c/uniq kcl kcl/sub w"* \
      && "$rc2" == 2 && "$o2" == *'ambiguous suite "x": a/x b/x'* && ! -e "$TMP/never1" && ! -e "$TMP/never2" ]]; then
    kt_test_pass "zzz: ${o1%%$'\n'*}; x: ${o2%%$'\n'*}"
else
    kt_test_fail "rc1=$rc1 [$o1] rc2=$rc2 [$o2] never1=$([[ -e "$TMP/never1" ]] && echo made) never2=$([[ -e "$TMP/never2" ]] && echo made)"
fi

kt_test_start "--out must be new or empty (rc 2), --root must exist (rc 2)"
mkdir -p "$TMP/full"; : > "$TMP/full/x"
kt050_gate "$TMP/r.out" --root "$F" --out "$TMP/full" w; o1="$(cat "$TMP/r.out")"; rc1=$RC
kt050_gate "$TMP/r.out" --root "$TMP/nope" w; o2="$(cat "$TMP/r.out")"; rc2=$RC
if [[ "$rc1" == 2 && "$o1" == *"is not empty"* && "$rc2" == 2 && "$o2" == *"no such directory"* ]]; then
    kt_test_pass "${o1%%$'\n'*} / ${o2%%$'\n'*}"
else
    kt_test_fail "rc1=$rc1 [$o1] rc2=$rc2 [$o2]"
fi

# ---- a real (tiny) run: header, spec, marker files ------------------------------
O="$TMP/out1"
kt_test_start "a run: rc 0, the header lines, one line per cell, the per-runtime summary, __GATE__ last; [WARN] one runtime only"
LC_ALL=C TZ=UTC kt050_gate "$TMP/run1.out" --root "$F" --out "$O" --timeout 60 --workers 2 --mode single c/uniq w -- -n 1
o="$(cat "$TMP/run1.out")"
last="$(tail -1 "$TMP/run1.out")"
if [[ "$RC" == 0 && "$o" == "gate "*" root="*" out="* && "$o" == *$'\n'"gate repos: "* && "$o" == *$'\n'"gate bashes: ${BASH_VERSION%%(*} "* \
      && "$o" == *"gate cells: 2 = 1 bash x 2 suite(s) (c/uniq w)  mode=single cwd=neutral timeout=60s workers=2 args: -n 1"* \
      && "$o" == *"[WARN] one runtime only"* \
      && "$o" == *"[1/2] ${BASH_VERSION%%(*} single   neutral c/uniq "*"PASS"*"2/2"* \
      && "$o" == *"[2/2] ${BASH_VERSION%%(*} single   neutral w "*"PASS"*"1/1  warn=1"* \
      && "$o" == *$'\n'"gate ${BASH_VERSION%%(*}: 2 cells  2 PASS  0 FAIL  0 FLAKY  0 ENV  0 TIMEOUT  0 STRAY  0 CRASH  0 NOTRUN  tests 3/3"* \
      && "$last" == "__GATE__:PASS:2:2:0:0:0:0:0:3:3" ]]; then
    kt_test_pass "$last"
else
    kt_test_fail "rc=$RC | ${o//$'\n'/ | }"
fi

kt_test_start "progress.txt holds the same lines; FINISHED holds the machine line; the marker and argv.txt exist"
p="$(cat "$O/progress.txt" 2>/dev/null)"; fin="$(cat "$O/FINISHED" 2>/dev/null)"
mk=""; { read -r mk < "$O/.kt_gate"; } 2>/dev/null
if [[ "$p" == "$o" && "$fin" == "$last" && "$mk" == "kt-gate 2 "* && -s "$O/argv.txt" && ! -e "$O/INTERRUPTED" && ! -e "$O/STOP" ]]; then
    kt_test_pass "marker [$mk]"
else
    kt_test_fail "progress differs: $([[ "$p" == "$o" ]] && echo no || echo yes) FINISHED [$fin] marker [$mk]"
fi

kt_test_start "the spec: mixed C:/... paths only (any mount prefix; review R11) — absolute POSIX paths without cygpath —, the cells in order, args, the caller's locale and TZ"
spec="$(source "$O/seg-1.spec" 2>&1
        printf 'out=%s\nroot=%s\nself=%s\n' "$KT_GATE_S_OUT" "$KT_GATE_S_ROOT" "$KT_GATE_S_SELF"
        printf 'cells=%s\n' "${KT_GATE_S_C_IDX[*]}:${KT_GATE_S_C_SUITE[*]}:${KT_GATE_S_C_MODE[*]}:${KT_GATE_S_C_CWD[*]}:${KT_GATE_S_C_REP[*]}"
        printf 'args=%s\n' "${KT_GATE_S_ARGS[*]}"
        printf 'misc=%s\n' "$KT_GATE_S_TIMEOUT $KT_GATE_S_WORKERS $KT_GATE_S_TOTAL $KT_GATE_S_KEEP $KT_GATE_S_HB_TICKS"
        printf 'env=%s\n' "${KT_GATE_S_ENV[@]}")"
bad=""
for k in out root self; do
    v="$(sed -n "s/^$k=//p" <<< "$spec")"
    if [[ -n "$CYGP" ]]; then [[ "$v" =~ ^[A-Za-z]:/ ]] || bad+="[$k=$v] "; else [[ "$v" == /* ]] || bad+="[$k=$v] "; fi
done
[[ "$spec" == *$'\ncells=1 2:c/uniq w:single single:neutral neutral:1 1\n'* ]] || bad+="[cells] "
[[ "$spec" == *$'\nargs=-n 1\n'* ]] || bad+="[args] "
[[ "$spec" == *$'\nmisc=60 2 2 0 30\n'* ]] || bad+="[misc] "
[[ "$spec" == *$'\nenv=LC_ALL=C'* && "$spec" == *$'\nenv=TZ=UTC'* ]] || bad+="[env: no LC_ALL=C / TZ=UTC] "
[[ "$spec" != *"env=HOME="* && "$spec" != *"env=TMPDIR="* && "$spec" != *"env=KT"* ]] || bad+="[env leaks HOME/TMPDIR/KT_] "
if [[ -z "$bad" ]]; then kt_test_pass "${spec//$'\n'/; }"; else kt_test_fail "$bad | ${spec//$'\n'/; }"; fi

kt_test_start "a passed cell keeps log/result/summary, its sandbox is removed; --keep keeps it"
O2="$TMP/out2"
kt050_gate "$TMP/run2.out" --root "$F" --out "$O2" --keep w
if [[ -f "$O/cells/001/result" && -f "$O/cells/001/log.txt" && -f "$O/cells/001/summary" && ! -e "$O/cells/001/home" \
      && "$RC" == 0 && -d "$O2/cells/001/home" && -d "$O2/cells/001/ckk" ]]; then
    kt_test_pass "removed without --keep, kept with it"
else
    kt_test_fail "rc=$RC out1 cell: $(ls "$O/cells/001" | tr '\n' ' ') out2 cell: $(ls "$O2/cells/001" 2>/dev/null | tr '\n' ' ')"
fi

# ---- runtimes: KT_GATE_BASHES, the other runtime ------------------------------
# the other cygwin runtime (MSYS2 vs Git for Windows), if there is one
OTHER=""
for b in /c/bin/msys64/usr/bin/bash.exe /c/msys64/usr/bin/bash.exe /c/bin/Git/usr/bin/bash.exe "/c/Program Files/Git/usr/bin/bash.exe"; do
    [[ -x "$b" ]] || continue
    v="$("$b" -c 'printf %s "$BASH_VERSION"' 2>/dev/null </dev/null)"
    [[ -n "$v" && "$v" != "$BASH_VERSION" ]] && { OTHER="$b"; OTHER_V="${v%%(*}"; break; }
done
kt_test_start "KT_GATE_BASHES='A;B' is the default for --bash (no [WARN]); --bash wins over it"
if [[ -n "$OTHER" ]]; then
    KT_GATE_BASHES="$BASH;$OTHER" kt050_gate "$TMP/b.out" --root "$F" --out "$TMP/out3" w
    o1="$(cat "$TMP/b.out")"; rc1=$RC
    KT_GATE_BASHES="$BASH;$OTHER" kt050_gate "$TMP/b.out" --root "$F" --out "$TMP/out4" --bash "$OTHER" w
    o2="$(cat "$TMP/b.out")"; rc2=$RC
    if [[ "$rc1" == 0 && "$o1" == *"gate bashes: ${BASH_VERSION%%(*} "*"  $OTHER_V "* && "$o1" != *"one runtime only"* \
          && "$o1" == *"__GATE__:PASS:2:2:"* && "$rc2" == 0 && "$o2" == *"gate cells: 1 = 1 bash"* && "$o2" == *"[1/1] $OTHER_V "* ]]; then
        kt_test_pass "both: ${o1##*$'\n'}; --bash: ${o2##*$'\n'}"
    else
        kt_test_fail "rc1=$rc1 rc2=$rc2 | ${o1//$'\n'/ | } || ${o2//$'\n'/ | }"
    fi
else
    kt_test_pass "skipped: no second bash runtime on this machine"
fi

kt_test_start "the parent watch is off with --nohup and under nohup (SIGHUP ignored on entry), on by default"
kt050_gate "$TMP/n1.out" --root "$F" --out "$TMP/out5" --nohup w; o1="$(cat "$TMP/n1.out")"; rc1=$RC
timeout -k 10 120 nohup bash "$G" --root "$F" --out "$TMP/out6" w > "$TMP/n2.out" 2>&1 < /dev/null; rc2=$?
o2="$(cat "$TMP/n2.out")"
if [[ "$rc1" == 0 && "$o1" == *"parent watch off (--nohup"* && "$rc2" == 0 && "$o2" == *"parent watch off (--nohup / SIGHUP ignored)"* \
      && "$o" != *"parent watch off"* ]]; then
    kt_test_pass "--nohup and nohup: off; the plain run: on"
else
    kt_test_fail "rc1=$rc1 rc2=$rc2 | ${o1//$'\n'/ | } || ${o2//$'\n'/ | }"
fi

# ---- rotation --------------------------------------------------------------------
# ---- rotation (review R3, F15) ------------------------------------------------
bash -c 'exit 0' & dead=$!; wait "$dead"
rt=none; [[ -r /proc/mounts ]] && while read -r a b c; do [[ "$b" == / ]] && { rt="$a"; break; }; done < /proc/mounts   # "none" without it, as gate.sh (launch L2.1)
# kt050_mark DIR PID START CREATED RUNTIME [complete|incomplete] — a v2 marker
kt050_mark() {
    mkdir -p "$1"
    printf 'kt-gate 2 %s 0 %s %s %s\n' "$2" "$3" "$4" "$5" > "$1/.kt_gate"
    case "${6:-complete}" in
        complete) : > "$1/seg-1.spec"; : > "$1/seg-1.result" ;;
        incomplete) : > "$1/seg-1.spec" ;;
    esac
}
now=$EPOCHSECONDS
kt_test_start "rotation never runs beside an explicit --out (it may hold the user's runs: head/new copies)"
P="$TMP/rot"
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do kt050_mark "$P/old$i" "$dead" "$(( 1000 + 10#$i ))" 1 "$rt"; done
kt050_gate "$TMP/rot.out" --root "$F" --out "$P/new" w
have="$(cd "$P" && ls -d */ | tr -d '/' | tr '\n' ' ')"
if [[ "$RC" == 0 && "$have" == "new old01 old02 old03 old04 old05 old06 old07 old08 old09 old10 old11 old12 " ]]; then
    kt_test_pass "13 dirs, none removed"
else
    kt_test_fail "rc=$RC left: [$have]"
fi
kt_test_start "rotation under the default root: the newest 10 stay; an older dir goes only when gate made it, its owner is dead and it is complete (or > 2 h old)"
D="$TMP/rt/kt-gate"
kt050_mark "$D/old00" "$$" 1000 1 "$rt"                         # owner alive
kt050_mark "$D/nc" "$dead" 1001 0 "$rt"                         # not made by gate
kt050_mark "$D/incold" "$dead" 1002 1 "$rt" incomplete          # incomplete, but > 2 h old
mkdir -p "$D/v1"; printf 'kt-gate 1 %s 0 1003 %s\n' "$dead" "$rt" > "$D/v1/.kt_gate"   # an old marker format
for i in 01 02 03 04 05 06 07 08 09 10; do kt050_mark "$D/d$i" "$dead" "$(( 1010 + 10#$i ))" 1 "$rt"; done
kt050_mark "$D/oth" "$dead" "$(( now - 100 ))" 1 other-runtime   # other runtime, young, unfinished
# other runtime, old, INTERRUPTED: its launcher alive (hb fresh) / gone (hb 10 min old) — R13
kt050_mark "$D/othlive" "$dead" 1004 1 other-runtime; : > "$D/othlive/INTERRUPTED"; : > "$D/othlive/hb"
kt050_mark "$D/othdead" "$dead" 1005 1 other-runtime; : > "$D/othdead/INTERRUPTED"; : > "$D/othdead/hb"
# touch -t (POSIX), not GNU's -d '10 minutes ago' (launch L2.1)
printf -v kt_ts '%(%Y%m%d%H%M.%S)T' $(( EPOCHSECONDS - 600 )); touch -t "$kt_ts" "$D/othdead/hb"
kt050_mark "$D/inc" "$dead" "$(( now - 100 ))" 1 "$rt" incomplete # incomplete, young
mkdir -p "$D/plain"
TMPDIR="$TMP/rt" kt050_gate "$TMP/rot2.out" --root "$F" w
have="$(cd "$D" && ls -d */ | tr -d '/' | tr '\n' ' ')"
new="$(sed -n 's|^gate .* out=\(.*\)$|\1|p' "$TMP/rot2.out" | head -1)"; new="${new##*/}"
# 19 marked; the 9 oldest beyond 10: old00 nc incold v1 othlive othdead d01 d02 d03 ->
# incold, othdead (other runtime, INTERRUPTED, hb stale), d01, d02, d03 go; old00 (alive), nc (not
# gate's), v1 (old marker), othlive (other runtime, hb fresh: its launcher lives) stay
want="d04 d05 d06 d07 d08 d09 d10 inc nc old00 oth othlive plain v1"
got="$(tr ' ' '\n' <<< "$have" | grep -v "^$new$" | grep . | sort | tr '\n' ' ')"
if [[ "$RC" == 0 && -n "$new" && "$have" == *"$new"* && "$got" == "$want " && "$new" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]]; then
    kt_test_pass "kept: $got+ $new"
else
    kt_test_fail "rc=$RC new=[$new] left: [$have] (want $want + new)"
fi
kt_test_start "the marker records that gate made the dir: CREATED=1 for a new --out and the default, 0 for an existing empty --out"
mkdir -p "$TMP/given"
kt050_gate "$TMP/m.out" --root "$F" --out "$TMP/given" w; rc1=$RC
m1=""; read -r m1 < "$TMP/given/.kt_gate"
m2=""; read -r m2 < "$TMP/out1/.kt_gate"
if [[ "$rc1" == 0 && "$m1" =~ ^kt-gate\ 2\ [0-9]+\ [0-9]+\ [0-9]+\ 0\  && "$m2" =~ ^kt-gate\ 2\ [0-9]+\ [0-9]+\ [0-9]+\ 1\  ]]; then
    kt_test_pass "[$m1] [$m2]"
else
    kt_test_fail "rc=$rc1 [$m1] [$m2]"
fi

# ---- the caller's shell state cannot redirect or break the launcher (R2) ------
kt_test_start "an exported CDPATH never redirects a relative --out / --root to another dir (data loss, review R2)"
mkdir -p "$TMP/decoy/outc" "$TMP/decoy/rootc" "$TMP/work"
: > "$TMP/decoy/outc/precious"
( cd "$TMP/work" && export CDPATH="$TMP/decoy" && timeout -k 10 120 bash "$G" --root "$F" --out outc w > "$TMP/cd1.out" 2>&1 < /dev/null; echo $? > "$TMP/cd1.rc" )
( cd "$TMP/work" && export CDPATH="$TMP/decoy" && timeout -k 10 120 bash "$G" --root rootc --out out2c w > "$TMP/cd2.out" 2>&1 < /dev/null; echo $? > "$TMP/cd2.rc" )
r1="$(cat "$TMP/cd1.rc")"; r2="$(cat "$TMP/cd2.rc")"; o2="$(cat "$TMP/cd2.out")"
dl="$(cd "$TMP/decoy/outc" && ls -A | tr '\n' ' ')"
if [[ "$r1" == 0 && -f "$TMP/work/outc/.kt_gate" && "$dl" == "precious " && "$r2" == 2 && "$o2" == *"--root rootc: no such directory"* \
      && ! -e "$TMP/work/out2c" ]]; then
    kt_test_pass "--out landed in the cwd, the decoy untouched; --root via CDPATH refused"
else
    kt_test_fail "rc1=$r1 rc2=$r2 decoy=[$dl] | $(cat "$TMP/cd1.out" | head -3 | tr '\n' ' ') | $o2"
fi
kt_test_start "exported SHELLOPTS/BASHOPTS (noclobber errexit nounset allexport failglob nullglob dotglob nocasematch) change nothing"
env SHELLOPTS=noclobber:errexit:nounset:allexport BASHOPTS=failglob:nullglob:dotglob:nocasematch:extglob \
    timeout -k 10 120 bash "$G" --root "$F" --out "$TMP/opts" w > "$TMP/opts.out" 2>&1 < /dev/null; rc1=$?
if [[ "$rc1" == 0 && "$(tail -1 "$TMP/opts.out")" == "__GATE__:PASS:1:1:0:0:0:0:0:1:1" ]]; then
    kt_test_pass "$(tail -1 "$TMP/opts.out")"
else
    kt_test_fail "rc=$rc1 | $(tr '\n' ' ' < "$TMP/opts.out" | cut -c1-600)"
fi
kt_test_start "--out with only a '..x' / '.x' entry is not empty (rc 2); a dir claimed by another gate's marker is refused"
mkdir -p "$TMP/dd1" "$TMP/dd2"; : > "$TMP/dd1/..x"; : > "$TMP/dd2/.x"
kt050_gate "$TMP/dd.out" --root "$F" --out "$TMP/dd1" w; r1=$RC; o1="$(cat "$TMP/dd.out")"
kt050_gate "$TMP/dd.out" --root "$F" --out "$TMP/dd2" w; r2=$RC
if [[ "$r1" == 2 && "$o1" == *"is not empty"* && "$r2" == 2 && "$(ls -A "$TMP/dd1")" == "..x" ]]; then
    kt_test_pass "rc 2 both"
else
    kt_test_fail "rc1=$r1 rc2=$r2 | $o1"
fi
kt_test_start "the default OUT is claimed by an atomic mkdir: STAMP-PID under \${TMPDIR}/kt-gate, CREATED=1"
TMPDIR="$TMP/rt3" kt050_gate "$TMP/d3.out" --root "$F" w
d3="$(ls -d "$TMP/rt3/kt-gate"/*/ 2>/dev/null | head -1)"; d3="${d3%/}"
m3=""; [[ -n "$d3" ]] && read -r m3 < "$d3/.kt_gate"
if [[ "$RC" == 0 && "${d3##*/}" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ && "$m3" =~ ^kt-gate\ 2\ .*\ 1\ [^\ ]+$ ]]; then
    kt_test_pass "${d3##*/}: $m3"
else
    kt_test_fail "rc=$RC dir=[$d3] marker=[$m3]"
fi

# ---- Ctrl-Z (review R13) ---------------------------------------------------------
kt_test_start "TSTP to the launcher: '[WARN] suspending a gate is not supported', ignored, the run goes on"
if [[ "$OSTYPE" != msys* && "$OSTYPE" != cygwin* && "$(trap -p TSTP)" == *"''"* ]]; then   # never skipped on cygwin
    # TSTP ignored when this file started (inherited: a FreeBSD ssh session —
    # launch L2.1): the launcher cannot trap it, there is nothing to see
    kt_test_pass "skipped: SIGTSTP is ignored in this environment (inherited) - no trap can be set"
else
R13="$TMP/r13"; bash "$MK" "$R13" hang
set -m
timeout -k 10 120 bash "$G" --root "$R13" --out "$TMP/o13" --timeout 3 all > "$TMP/o13.out" 2>&1 < /dev/null &
P13=$!
set +m
for (( i = 0; i < 100; i++ )); do [[ -e "$TMP/o13/seg-1.cur" ]] && break; sleep 0.1; done
sleep 0.5
lp=""; { read -r _ _ lp _ < "$TMP/o13/.kt_gate"; } 2>/dev/null
[[ -n "$lp" ]] && kill -TSTP "$lp" 2>/dev/null
wait "$P13"; rc=$?
o13="$(cat "$TMP/o13.out")"
if [[ "$rc" == 1 && "$o13" == *"[WARN] suspending a gate is not supported"* && "$o13" == *"TIMEOUT"* && "$o13" == *"__GATE__:FAIL:1:0:0:0:0:1:0:"* ]]; then
    kt_test_pass "rc 1 (the hang cell's TIMEOUT), the warning printed"
else
    kt_test_fail "rc=$rc lp=$lp | ${o13//$'\n'/ | }"
fi
fi

kt_test_start "--out inside the tree under test: a [WARN] (the segments source OUT/seg-N.spec: a private dir is needed), the run goes on; outside it: no warning (G4 review R11)"
kt050_gate "$TMP/oin.out" --root "$F" --out "$F/gate-out" c/uniq; rin=$RC
kt050_gate "$TMP/oout.out" --root "$F" --out "$TMP/gate-out-ok" c/uniq; rout=$RC
oin="$(cat "$TMP/oin.out")" oout="$(cat "$TMP/oout.out")"
rm -rf "$F/gate-out"
if [[ "$rin" == 0 && "$oin" == *"[WARN] --out is inside the tree under test"* && "$rout" == 0 && "$oout" != *"--out is inside"* ]]; then
    kt_test_pass "$(grep -m1 'inside the tree' "$TMP/oin.out")"
else
    kt_test_fail "rc=$rin/$rout | ${oin//$'\n'/ | }"
fi

kt_test_start "the default root is PRIVATE and the same for both launchers: TMPDIR unset -> %LOCALAPPDATA%/Temp, else the per-user folder (cygpath -F 28) — never MSYS2's /tmp, also with no environment at all (G4 review R13)"
if [[ -z "$CYGP" ]]; then
    # no cygpath (Linux, BSD, macOS): TMPDIR when set, else /tmp (launch L2.1)
    pt="$( source "$G" || exit 9
        unset TMPDIR LOCALAPPDATA; _kt_gate_ptmp; printf '%s|' "$REPLY"
        TMPDIR="$TMP/given"; _kt_gate_ptmp; printf '%s' "$REPLY" )"
    if [[ "$pt" == "/tmp|$TMP/given" ]]; then kt_test_pass "[$pt] (no cygpath: TMPDIR, else /tmp)"; else kt_test_fail "[$pt] want [/tmp|$TMP/given]"; fi
else
pt="$( source "$G" || exit 9; _KT_GATE_CYGPATH=1
    unset TMPDIR; LOCALAPPDATA="$(cygpath -m "$TMP/lad")"; mkdir -p "$TMP/lad/Temp"; _kt_gate_ptmp; printf '%s|' "$REPLY"
    unset LOCALAPPDATA; _kt_gate_ptmp; printf '%s|' "$REPLY"
    TMPDIR="$TMP/given"; _kt_gate_ptmp; printf '%s' "$REPLY" )"
pto=""
if [[ -n "$OTHER" ]]; then
    pto="$(env -i PATH="${OTHER%/*}:$PATH" SYSTEMROOT="${SYSTEMROOT:-}" WINDIR="${WINDIR:-}" "$OTHER" -c \
        'source "$1" || exit 9; _KT_GATE_CYGPATH=1; _kt_gate_ptmp; printf "%s|%s|%s" "${TMPDIR-unset}" "${LOCALAPPDATA-unset}" "$REPLY"' _ "$G" < /dev/null 2>&1)"
fi
want_la="$(cygpath -m "$TMP/lad")/Temp" want_f28="$(cygpath -m -F 28)/Temp"
IFS='|' read -r p1 p2 p3 <<< "$pt"
if [[ "$p1" == "$want_la" && "$p2" == "$want_f28" && "$p3" == "$(cygpath -m "$TMP/given")" \
      && ( -z "$OTHER" || "$pto" == "unset|unset|$want_f28" ) && "$p2$pto" != *msys64/tmp* ]]; then
    kt_test_pass "[$pt] other: [${pto:-no second runtime}]"
else
    kt_test_fail "[$pt] want [$want_la|$want_f28|…] other=[$pto]"
fi
fi
kt_test_start "a 5.2 and a 5.3 launcher (TMPDIR unset, the same LOCALAPPDATA) land in ONE default root, and --compare LAST from either finds the other's run (G4 review R13)"
if [[ -n "$OTHER" ]]; then
    LAD="$TMP/lad2"; mkdir -p "$LAD/Temp"; LADM="$(cygpath -m "$LAD")"
    ( unset TMPDIR; export LOCALAPPDATA="$LADM"; exec timeout -k 10 120 bash "$G" --root "$F" --bash "$BASH" c/uniq ) > "$TMP/sh1.out" 2>&1 < /dev/null; s1=$?
    env -i PATH="${OTHER%/*}:$PATH" SYSTEMROOT="${SYSTEMROOT:-}" WINDIR="${WINDIR:-}" timeout -k 10 120 "$OTHER" -c \
        'unset TMPDIR; export LOCALAPPDATA="$1"; exec "$2" "$3" --root "$4" --bash "$2" --compare LAST c/uniq' _ "$LADM" "$OTHER" "$G" "$F" \
        > "$TMP/sh2.out" 2>&1 < /dev/null; s2=$?
    ( unset TMPDIR; export LOCALAPPDATA="$LADM"; exec timeout -k 10 120 bash "$G" --root "$F" --bash "$BASH" --compare LAST c/uniq ) > "$TMP/sh3.out" 2>&1 < /dev/null; s3=$?
    o1="$(sed -n 's|^gate 20.* out=\(.*\)$|\1|p' "$TMP/sh1.out" | head -1)"
    o2="$(sed -n 's|^gate 20.* out=\(.*\)$|\1|p' "$TMP/sh2.out" | head -1)"
    o3="$(sed -n 's|^gate 20.* out=\(.*\)$|\1|p' "$TMP/sh3.out" | head -1)"
    c2="$(grep -m1 '^gate compare LAST (' "$TMP/sh2.out")"; c3="$(grep -m1 '^gate compare LAST (' "$TMP/sh3.out")"
    if [[ "$s1$s2$s3" == 000 && "$o1" == "$LADM/Temp/kt-gate/"* && "$o2" == "$LADM/Temp/kt-gate/"* && "$o3" == "$LADM/Temp/kt-gate/"* \
          && "$c2" == *"($o1)"* && "$c3" == *"($o2)"* ]]; then
        kt_test_pass "[${o1##*/}] [${o2##*/}] [${o3##*/}] — LAST across both ways"
    else
        kt_test_fail "rc=$s1$s2$s3 o=[$o1] [$o2] [$o3] c2=[$c2] c3=[$c3] | $(tr '\n' ' ' < "$TMP/sh2.out" | cut -c1-400)"
    fi
else
    kt_test_pass "skipped: no second bash runtime on this machine"
fi

kt_test_start "nothing of this file's gates is left (by its tmp path)"
kt050_pids "$TMP"
if [[ -z "$REPLY" ]]; then kt_test_pass "none"; else kt_test_fail "left: $REPLY"; fi

kt_test_log "050_GateCli.sh completed"
