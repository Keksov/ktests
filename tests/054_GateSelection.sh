#!/bin/bash
# GateSelection (gate G3). Which cells ktests/tools/gate.sh runs:
#   --changed (DG6, GATE_PLAN 4.5) on a SCRATCH git fixture — a root repo with
#   a fake kcl/ tree (units ua, ub = `kk.uses ua`, ud; test files that use
#   ub / ua / ud, a bench.sh that uses ud) as a submodule-like nested repo:
#   nothing changed (rc 0, no cell, no OUT), a unit change (its suite + the
#   dependents through unit files, test files and bench.sh + kcl), a
#   test-only / docs-only change, an untracked file, a deleted unit file, a
#   core change (all), the submodule's commit moved, the union with named
#   suites;
#   --rerun-failed / FLAKY (rc 4), --repeat, --mode both, --cwd both (the cell
#   order), --fail-fast (SKIPPED), --warm (one .ckk dir per segment, visible
#   from the cells), --parallel (both runtimes at once: lines in completion
#   order).
#
# The git fixture lives in this file's private tmp (GIT_CEILING_DIRECTORIES
# keeps every git command inside it: the real repos are never read or
# written); each gate bounded by `timeout`; the end checks nothing carrying
# the tmp path is left.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GateSelection" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
G="$LIB/tools/gate.sh"
MK="$LIB/tests/gate_fixtures/mkroot.sh"
unset KT_GATE_BASHES
V="${BASH_VERSION%%(*}"
export GIT_CEILING_DIRECTORIES="$(cygpath -m "$TMP" 2>/dev/null || echo "$TMP")"
GC=( -c user.name=gate-test -c user.email=gate@test -c init.defaultBranch=main -c core.autocrlf=false
     -c advice.addEmbeddedRepo=false -c advice.detachedHead=false )

kt054_pids() {
    local f p
    local -a a
    REPLY=""
    for f in /proc/[0-9]*/cmdline; do
        a=()
        { mapfile -d '' -t a < "$f"; } 2>/dev/null || continue
        [[ "${a[*]}" == *"$1"* ]] || continue
        p="${f#/proc/}"; p="${p%/cmdline}"
        [[ "$p" == "$$" || "$p" == "$BASHPID" ]] && continue
        REPLY+="$p "
    done
    REPLY="${REPLY% }"
}
kt054_gate() {
    local of="$1"; shift
    timeout -k 10 150 bash "$G" "$@" > "$of" 2>&1 < /dev/null
    RC=$?
}
kt054_kv() {
    local k v
    REPLY=""
    while IFS='=' read -r k v; do [[ "$k" == "$2" ]] && { REPLY="$v"; return 0; }; done < "$1"
    return 1
}
kt054_line() {
    local l
    REPLY=""
    while IFS= read -r l; do [[ "$l" == "[$2/"* || "$l" == "[ $2/"* ]] && { REPLY="$l"; return 0; }; done <<< "$1"
    return 1
}

OTHER=""
for b in /c/bin/msys64/usr/bin/bash.exe /c/msys64/usr/bin/bash.exe /c/bin/Git/usr/bin/bash.exe "/c/Program Files/Git/usr/bin/bash.exe"; do
    [[ -x "$b" ]] || continue
    v="$("$b" -c 'printf %s "$BASH_VERSION"' 2>/dev/null)"
    [[ -n "$v" && "$v" != "$BASH_VERSION" ]] && { OTHER="$b"; break; }
done

# ---- the scratch git fixture --------------------------------------------------------
R="$TMP/groot"
bash "$MK" "$R" pass=kcl pass=kcl/ua pass=kcl/ub pass=kcl/uc pass=kcl/ud pass=kcl/ue pass=kcl/ug pass=kk pass=kkore
printf '#!/bin/bash\nkk.unit ua || return $__kk_unit_rc\n' > "$R/kcl/ua/ua.sh"
printf '#!/bin/bash\nkk.unit ub || return $__kk_unit_rc\nkk.uses kklass_pascal || return\nkk.uses ua || return\n' > "$R/kcl/ub/ub.sh"
printf '# a helper of the uc suite\nkk.uses ub || exit 1\n' > "$R/kcl/uc/tests/uc_helper.sh"
printf '#!/bin/bash\nkk.unit ud || return $__kk_unit_rc\n' > "$R/kcl/ud/ud.sh"
printf 'kk.uses --optional ua || true   # a test helper using ua directly\n' > "$R/kcl/ud/tests/ud_helper.sh"
printf 'kk.uses ud || exit 1\n' > "$R/kcl/ue/tests/ue_helper.sh"
printf '# run by the suite'"'"'s tests, as kcl/*/bench.sh are\nkk.uses ud || exit 1\n' > "$R/kcl/ug/bench.sh"
printf 'kcl\n' > "$R/kcl/README.md"
printf '#!/bin/bash\n' > "$R/kbool.sh"
mkdir -p "$R/docs"; printf 'docs\n' > "$R/docs/x.md"
printf 'readme\n' > "$R/README.md"
printf '[submodule "kcl"]\n\tpath = kcl\n\turl = ./kcl\n' > "$R/.gitmodules"
gok=1
{ git "${GC[@]}" -C "$R/kcl" init -q && git "${GC[@]}" -C "$R/kcl" add -A && git "${GC[@]}" -C "$R/kcl" commit -qm kcl \
  && git "${GC[@]}" -C "$R" init -q && git "${GC[@]}" -C "$R" add -A && git "${GC[@]}" -C "$R" commit -qm root; } > "$TMP/git.out" 2>&1 || gok=0
[[ -d "$R/.git" && -d "$R/kcl/.git" ]] || gok=0
# kt054_g ARGS... — git in the fixture only (never without its .git)
kt054_g() { [[ -d "$R/.git" ]] && git "${GC[@]}" "$@" >> "$TMP/git.out" 2>&1; }
# kt054_sel ARGS... — the selection alone (gate.sh sourced: nothing runs)
kt054_sel() {
    ( source "$G" || exit 9
      kt_gate_parse --root "$R" --changed "$@"
      _KT_GATE_CYGPATH=""; command -v cygpath >/dev/null 2>&1 && _KT_GATE_CYGPATH=1
      kt_gate_root; kt_gate_resolve; kt_gate_changed
      for id in "${_KT_GATE_ALL_IDS[@]}"; do [[ -n "${_KT_GATE_CHG_WHY["$id"]+x}" ]] && printf '%s ' "$id"; done
      printf '|%s\n' "${_KT_GATE_CHG_LINES[*]}" ) 2>&1
}

kt_test_start "the scratch git fixture: a root repo, kcl/ as a nested repo recorded as a gitlink (.gitmodules)"
if (( gok )) && [[ "$(git -C "$R" ls-files -s kcl 2>/dev/null)" == 160000\ * ]]; then
    kt_test_pass "$(git -C "$R" ls-files -s kcl)"
else
    kt_test_fail "$(tr '\n' ' ' < "$TMP/git.out")"
fi

kt_test_start "--changed, nothing changed: '[WARN] nothing changed', rc 0, no cell, no OUT dir, no machine line"
kt054_gate "$TMP/c0.out" --root "$R" --out "$TMP/c0out" --changed
o="$(cat "$TMP/c0.out")"
if [[ "$RC" == 0 && "$o" == *"gate changed: nothing changed"* && "$o" == *"[WARN] nothing changed: no suite selected, no cell runs (exit 0)"* \
      && ! -e "$TMP/c0out" && "$o" != *__GATE__* && "$o" != *"[1/"* ]]; then
    kt_test_pass "${o//$'\n'/ | }"
else
    kt_test_fail "rc=$RC | ${o//$'\n'/ | }"
fi

kt_test_start "a unit file change: its suite + the dependents (unit file uses it, test files use it or a dependent) + kcl; not the unrelated ue"
printf '# changed\n' >> "$R/kcl/ua/ua.sh"
s="$(kt054_sel)"
if [[ "${s%%|*}" == "kcl kcl/ua kcl/ub kcl/uc kcl/ud " && "$s" == *"kcl  <- unit file changed: kcl/ua/ua.sh"* \
      && "$s" == *"kcl/ub  <- unit ub uses ua (kcl/ub/ub.sh)"* && "$s" == *"kcl/uc  <- test uses ub (kcl/uc/tests/uc_helper.sh)"* \
      && "$s" == *"kcl/ud  <- test uses ua (kcl/ud/tests/ud_helper.sh)"* ]]; then
    kt_test_pass "${s%%|*}"
else
    kt_test_fail "$s"
fi
kt_test_start "--changed with a named suite: the union; the selection and its reasons printed before the first cell; summary.json 'changed'"
kt054_gate "$TMP/c1.out" --root "$R" --out "$TMP/c1out" --changed kk
o="$(cat "$TMP/c1.out")"
pre="${o%%$'\n'\[1/*}"
cj=""
NODE="$(type -P node 2>/dev/null)"
if [[ -n "$NODE" ]]; then
    cj="$("$NODE" -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(JSON.stringify(j.changed.paths)+" "+Object.keys(j.changed.suites).join(",")+" "+j.changed.all+" "+j.gate.options.changed)' \
        "$(cygpath -m "$TMP/c1out/summary.json" 2>/dev/null)" 2>&1)"
fi
if [[ "$RC" == 0 && "$o" == *"gate cells: 6 = 1 bash x 6 suite(s) (kcl kcl/ua kcl/ub kcl/uc kcl/ud kk)"* \
      && "$pre" == *"gate changed: 1 path(s) select 5 suite(s)"* && "$pre" == *"gate changed:   kk  <- named on the command line"* \
      && "$o" == *$'\n'"__GATE__:PASS:6:6:0:0:0:0:0:18:18" \
      && ( -z "$NODE" || "$cj" == '["kcl/ua/ua.sh"] kcl,kcl/ua,kcl/ub,kcl/uc,kcl/ud null true' ) ]]; then
    kt_test_pass "6 cells, json [$cj]"
else
    kt_test_fail "rc=$RC json=[$cj] | ${o//$'\n'/ | }"
fi
kt054_g -C "$R/kcl" checkout -q -- ua/ua.sh

kt_test_start "test-only change -> only its suite; a *.md in a unit dir -> its suite (doc tests); an untracked file counts"
printf '#\n' >> "$R/kcl/ub/tests/001_a.sh"; s1="$(kt054_sel)"; kt054_g -C "$R/kcl" checkout -q -- ub/tests/001_a.sh
printf 'doc\n' > "$R/kcl/ua/README.md"; s2="$(kt054_sel)"; rm -f "$R/kcl/ua/README.md"
printf 'n\n' > "$R/kcl/ue/notes.txt"; s3="$(kt054_sel)"; rm -f "$R/kcl/ue/notes.txt"
if [[ "${s1%%|*}" == "kcl/ub " && "${s2%%|*}" == "kcl/ua " && "${s3%%|*}" == "kcl/ue " && "$s3" == *"kcl/ue  <- changed: kcl/ue/notes.txt"* ]]; then
    kt_test_pass "[${s1%%|*}] [${s2%%|*}] [${s3%%|*}]"
else
    kt_test_fail "[$s1] [$s2] [$s3]"
fi
kt_test_start "a deleted unit file: its suite, kcl and the dependents of its unit (the file stem); a docs-only change outside kcl: no suite, rc 0"
rm -f "$R/kcl/ud/ud.sh"; s1="$(kt054_sel)"; kt054_g -C "$R/kcl" checkout -q -- ud/ud.sh
printf 'more\n' >> "$R/docs/x.md"
kt054_gate "$TMP/c2.out" --root "$R" --out "$TMP/c2out" --changed
o2="$(cat "$TMP/c2.out")"; rc2=$RC
kt054_g -C "$R" checkout -q -- docs/x.md
if [[ "${s1%%|*}" == "kcl kcl/ud kcl/ue kcl/ug " && "$rc2" == 0 && "$o2" == *"(no suite) <- docs/x.md"* \
      && "$o2" == *"[WARN] the changes select no suite: no cell runs (exit 0)"* && ! -e "$TMP/c2out" ]]; then
    kt_test_pass "[${s1%%|*}] docs: rc 0"
else
    kt_test_fail "[$s1] rc2=$rc2 | ${o2//$'\n'/ | }"
fi
kt_test_start "a core change (kbool.sh; an untracked file under ktests/) selects all"
printf '# x\n' >> "$R/kbool.sh"; s1="$(kt054_sel)"; kt054_g -C "$R" checkout -q -- kbool.sh
printf 'x\n' > "$R/ktests/new.txt"; s2="$(kt054_sel)"; rm -f "$R/ktests/new.txt"
all="kcl kcl/ua kcl/ub kcl/uc kcl/ud kcl/ue kcl/ug kk kkore "
if [[ "${s1%%|*}" == "$all" && "$s1" == *"all 9 suites, for kbool.sh"* && "${s2%%|*}" == "$all" && "$s2" == *"for ktests/new.txt"* ]]; then
    kt_test_pass "all 9, twice"
else
    kt_test_fail "[$s1] [$s2]"
fi
kt_test_start "the submodule's commit moved (committed in kcl, not in the root): the files of that diff select"
printf '# y\n' >> "$R/kcl/ud/ud.sh"
kt054_g -C "$R/kcl" commit -qam ud
s1="$(kt054_sel)"
st="$(git -C "$R" status --porcelain 2>/dev/null)"
kt054_g -C "$R/kcl" reset -q --hard HEAD~1
s2="$(kt054_sel)"
if [[ "${s1%%|*}" == "kcl kcl/ud kcl/ue kcl/ug " && "$s1" == *"kcl/ug  <- bench.sh uses ud (kcl/ug/bench.sh)"* && "$s1" == *"kcl/ue  <- test uses ud (kcl/ue/tests/ue_helper.sh)"* && "$st" == *kcl* \
      && "$s2" == *"nothing changed"* ]]; then
    kt_test_pass "[${s1%%|*}] then clean"
else
    kt_test_fail "[$s1] status=[$st] after reset [$s2]"
fi
kt_test_start "a worktree rename (porcelain ' R new old'): both paths kept whole — kcl/ue only, no mangled old path (G4 review R4)"
mv "$R/kcl/ue/tests/ue_helper.sh" "$R/kcl/ue/tests/ue_helper2.sh"
kt054_g -C "$R/kcl" add -N ue/tests/ue_helper2.sh
st="$(git -C "$R/kcl" status --porcelain 2>/dev/null)"
s1="$(kt054_sel)"
kt054_g -C "$R/kcl" rm -q --cached ue/tests/ue_helper2.sh
mv "$R/kcl/ue/tests/ue_helper2.sh" "$R/kcl/ue/tests/ue_helper.sh"
s2="$(kt054_sel)"
if [[ "$st" == " R "* && "${s1%%|*}" == "kcl/ue " && "$s1" == *"kcl/ue  <- changed: kcl/ue/tests/ue_helper2.sh"* && "$s1" != *"(no suite)"* \
      && "$s2" == *"nothing changed"* ]]; then
    kt_test_pass "[$st] -> [${s1%%|*}]"
else
    kt_test_fail "status=[$st] [$s1] after [$s2]"
fi
kt_test_start "the root README.md -> kkore (its doc examples, the doc map); .gitmodules -> all (G4 review R5)"
printf 'more\n' >> "$R/README.md"; s1="$(kt054_sel)"; kt054_g -C "$R" checkout -q -- README.md
printf '# x\n' >> "$R/.gitmodules"; s2="$(kt054_sel)"; kt054_g -C "$R" checkout -q -- .gitmodules
if [[ "${s1%%|*}" == "kkore " && "$s1" == *"kkore  <- doc examples (kkore 015 runs its doctest blocks): README.md"* \
      && "${s2%%|*}" == "$all" && "$s2" == *"for .gitmodules"* ]]; then
    kt_test_pass "[${s1%%|*}] [all for .gitmodules]"
else
    kt_test_fail "[$s1] [$s2]"
fi
kt_test_start "a deleted top-level script that is no unit file (HEAD has no kk.unit): 'deleted script', its suite only (G4 review R9)"
rm -f "$R/kcl/ug/bench.sh"; s1="$(kt054_sel)"; kt054_g -C "$R/kcl" checkout -q -- ug/bench.sh
if [[ "${s1%%|*}" == "kcl/ug " && "$s1" == *"kcl/ug  <- deleted script: kcl/ug/bench.sh"* ]]; then
    kt_test_pass "${s1%%|*}"
else
    kt_test_fail "[$s1]"
fi
kt_test_start "--changed on a dir that is not the top of a git work tree: usage error rc 2"
kt054_gate "$TMP/c3.out" --root "$R/kcl/ua" --changed
o3="$(cat "$TMP/c3.out")"
mkdir -p "$TMP/nogit/x/tests"; cp "$LIB/tests/gate_fixtures/pass/suite/"* "$TMP/nogit/x/tests/"; cp -r "$R/ktests" "$TMP/nogit/"
kt054_gate "$TMP/c4.out" --root "$TMP/nogit" --changed
o4="$(cat "$TMP/c4.out")"; rc4=$RC
if [[ "$rc4" == 2 && "$o4" == *"is not the top of a git work tree"* ]]; then
    kt_test_pass "rc 2"
else
    kt_test_fail "rc4=$rc4 | ${o4//$'\n'/ | } | ${o3//$'\n'/ | }"
fi

# ---- --rerun-failed / FLAKY ---------------------------------------------------------------
RF="$TMP/rootF"; bash "$MK" "$RF" flaky pass
kt054_gate "$TMP/f.out" --root "$RF" --out "$TMP/outF" --rerun-failed 2 all
of="$(cat "$TMP/f.out")"
kt054_line "$of" 1; l1="$REPLY"
kt054_kv "$TMP/outF/cells/001/result" reruns; rr="$REPLY"; kt054_kv "$TMP/outF/cells/001/result" rerun_pass; rp="$REPLY"
kt054_kv "$TMP/outF/cells/001/result" flaky; fl="$REPLY"
s1=""; { read -r s1 < "$TMP/outF/cells/001/rerun-1/summary"; } 2>/dev/null
kt_test_start "--rerun-failed 2: a file failing once is re-run alone (-n 2, a sandbox of its own) and passes -> FLAKY, exit 4, __GATE__:FLAKY"
if [[ "$RC" == 4 && "$l1" =~ \ flaky\ +FLAKY\ +3/4\  && "$l1" == *"(rerun 1 passed: 002_flaky.sh)"* \
      && "$of" == *"        [FAIL] gfx flaky: the first run fails (002_flaky.sh)"* && "$rr" == 1 && "$rp" == 1 && "$fl" == 002_flaky.sh \
      && "$s1" == "1 1 0 0" && -d "$TMP/outF/cells/001/rerun-1/home" \
      && "$of" == *"1 PASS  0 FAIL  1 FLAKY"* && "$of" == *$'\n'"gate FLAKY  out="*$'\n'"__GATE__:FLAKY:2:1:0:1:0:0:0:6:7" ]]; then
    kt_test_pass "[$l1]"
else
    kt_test_fail "rc=$RC reruns=$rr pass=$rp flaky=$fl rerun-1 summary=[$s1] | ${of//$'\n'/ | }"
fi
kt_test_start "without --rerun-failed the same first failure is a FAIL (rc 1); a file that fails every time stays FAIL after N reruns"
RF2="$TMP/rootF2"; bash "$MK" "$RF2" flaky fail
kt054_gate "$TMP/f2.out" --root "$RF2" --out "$TMP/outF2" flaky; r1=$RC
kt054_gate "$TMP/f3.out" --root "$RF2" --out "$TMP/outF3" --rerun-failed 2 fail; r2=$RC
o3="$(cat "$TMP/f3.out")"
kt054_kv "$TMP/outF3/cells/001/result" reruns; rr="$REPLY"; kt054_kv "$TMP/outF3/cells/001/result" verdict; vv="$REPLY"
if [[ "$r1" == 1 && "$(tail -1 "$TMP/f2.out")" == "__GATE__:FAIL:1:0:1:0:0:0:0:3:4" && "$r2" == 1 && "$vv" == FAIL && "$rr" == 2 \
      && "$o3" == *"(2 rerun(s) of 002_bad.sh 003_worse.sh failed (last: FAIL 1/4))"* && -d "$TMP/outF3/cells/001/rerun-2" ]]; then
    kt_test_pass "rc $r1 / $r2, reruns=$rr"
else
    kt_test_fail "r1=$r1 r2=$r2 verdict=$vv reruns=$rr | $(tail -1 "$TMP/f2.out") | ${o3//$'\n'/ | }"
fi

# ---- the matrix: --repeat, --mode both, --cwd both -------------------------------------------
RM="$TMP/rootM"; bash "$MK" "$RM" pass=a pass=b
kt054_gate "$TMP/m.out" --root "$RM" --out "$TMP/outM" --mode both --cwd both --repeat 2 a
om="$(cat "$TMP/m.out")"
order=""
for (( i = 1; i <= 8; i++ )); do
    f="$(printf '%s/outM/cells/%03d/result' "$TMP" "$i")"
    kt054_kv "$f" repeat; r="$REPLY"; kt054_kv "$f" mode; m="$REPLY"; kt054_kv "$f" cwd; c="$REPLY"
    order+="$r${m:0:1}${c:0:1} "
done
kt_test_start "--mode both --cwd both --repeat 2: 8 cells, order repeat > suite > mode > cwd, the repeat in the line (a#2), rc 0"
kt054_line "$om" 5; l5="$REPLY"
if [[ "$RC" == 0 && "$order" == "1tn 1ts 1sn 1ss 2tn 2ts 2sn 2ss " && "$l5" =~ \ threaded\ +neutral\ +a#2\ +PASS\ +3/3 \
      && "$om" == *"gate cells: 8 = 1 bash x 1 suite(s) x 2 modes x 2 cwds x 2 repeats (a)"* \
      && "$om" == *$'\n'"__GATE__:PASS:8:8:0:0:0:0:0:24:24" ]]; then
    kt_test_pass "[$order] [$l5]"
else
    kt_test_fail "rc=$RC order=[$order] | ${om//$'\n'/ | }"
fi

# ---- --fail-fast ----------------------------------------------------------------------------
RX="$TMP/rootX"; bash "$MK" "$RX" fail=a1 pass=b2 pass=c3
bl=( --bash "$BASH" ); [[ -n "$OTHER" ]] && bl+=( --bash "$OTHER" )
kt054_gate "$TMP/x.out" --root "$RX" --out "$TMP/outX" "${bl[@]}" --fail-fast all
ox="$(cat "$TMP/x.out")"
nsk=0; for f in "$TMP"/outX/cells/*/result; do kt054_kv "$f" verdict; [[ "$REPLY" == SKIPPED ]] && nsk=$(( nsk + 1 )); done
want=2; [[ -n "$OTHER" ]] && want=5
kt_test_start "--fail-fast: after the first hard failure the remaining cells (both runtimes) are SKIPPED, exit 1"
ff=""; { read -r ff < "$TMP/outX/FAILFAST"; } 2>/dev/null
if [[ "$RC" == 1 && "$nsk" == "$want" && "$ff" == "cell 1 FAIL ($V a1)" && "$ox" == *"gate fail-fast: $V: 2 cell(s) skipped (after cell 1 FAIL ($V a1))"* \
      && "$ox" == *"  2 skipped"* && "$ox" == *$'\n'"__GATE__:FAIL:$(( want + 1 )):0:1:0:0:0:0:2:5" ]]; then
    kt_test_pass "$nsk skipped"
else
    kt_test_fail "rc=$RC skipped=$nsk/$want FAILFAST=[$ff] | ${ox//$'\n'/ | }"
fi

kt_test_start "--fail-fast: FAILFAST has ONE writer — the first; a later failure, or one racing a writer that holds the lock, never overwrites it (G4 review R8)"
mkdir -p "$TMP/ffl1" "$TMP/ffl2"
ffo="$( source "$G" || exit 9
    KT_GATE_S_FAILFAST=1 _KT_GATE_VER=$V KT_GATE_S_C_SUITE=( s0 s1 s2 )
    KT_GATE_S_OUT="$TMP/ffl1"
    _kt_gate_seg_failfast 1 FAIL 0; _kt_gate_seg_failfast 2 TIMEOUT 1; _kt_gate_seg_failfast 3 PASS 2
    read -r a < "$TMP/ffl1/FAILFAST"
    KT_GATE_S_OUT="$TMP/ffl2"; mkdir "$TMP/ffl2/FAILFAST.lock"
    _kt_gate_seg_failfast 4 CRASH 1
    b=none; [[ -e "$TMP/ffl2/FAILFAST" ]] && read -r b < "$TMP/ffl2/FAILFAST"
    printf '%s|%s' "$a" "$b" )"
if [[ "$ffo" == "cell 1 FAIL ($V s0)|none" ]]; then kt_test_pass "$ffo"; else kt_test_fail "$ffo"; fi

# ---- --warm -----------------------------------------------------------------------------------
RW="$TMP/rootW"; bash "$MK" "$RW" ckk
kt054_gate "$TMP/w1.out" --root "$RW" --out "$TMP/outW1" --warm --keep --repeat 2 all; rw1=$RC
kt054_gate "$TMP/w2.out" --root "$RW" --out "$TMP/outW2" --keep --repeat 2 all; rw2=$RC
kt054_gate "$TMP/w3.out" --root "$RW" --out "$TMP/outW3" --warm --repeat 2 all; rw3=$RC
kt054_kv "$TMP/outW1/cells/001/result" ckk; k1="$REPLY"; kt054_kv "$TMP/outW1/cells/002/result" ckk; k2="$REPLY"
kt054_kv "$TMP/outW2/cells/001/result" ckk; k3="$REPLY"; kt054_kv "$TMP/outW2/cells/002/result" ckk; k4="$REPLY"
n1="$(wc -l < "$TMP/outW1/seg-1.ckk/cells.log" 2>/dev/null)"
n3="$(cat "$TMP/outW2/cells/001/ckk/cells.log" "$TMP/outW2/cells/002/ckk/cells.log" 2>/dev/null | wc -l)"
kt_test_start "--warm: the cells of a segment share one .ckk dir (seg-N.ckk: both cells wrote into it); without it each cell has its own; removed without --keep"
if [[ "$rw1$rw2$rw3" == 000 && "$k1" == seg-1.ckk && "$k2" == seg-1.ckk && "$n1" == 2 && "$k3" == cells/001/ckk \
      && "$k4" == cells/002/ckk && "$n3" == 2 && ! -e "$TMP/outW3/seg-1.ckk" && "$(cat "$TMP/w1.out")" == *"--warm (one .ckk dir per runtime)"* ]]; then
    kt_test_pass "warm: $k1 $k2 ($n1 lines); cold: $k3 $k4"
else
    kt_test_fail "rc=$rw1$rw2$rw3 warm=[$k1 $k2] lines=$n1 cold=[$k3 $k4] lines=$n3 w3 ckk: $(ls "$TMP/outW3" | tr '\n' ' ')"
fi

# ---- --parallel ------------------------------------------------------------------------------
kt_test_start "--parallel: both runtimes at once, the launcher relays lines as they come (a cell of runtime 2 before the last of runtime 1)"
if [[ -n "$OTHER" ]]; then
    RP="$TMP/rootP"; bash "$MK" "$RP" pass
    kt054_gate "$TMP/p.out" --root "$RP" --out "$TMP/outP" --bash "$BASH" --bash "$OTHER" --parallel --repeat 3 all
    op="$(cat "$TMP/p.out")"
    seq=""
    while IFS= read -r l; do [[ "$l" =~ ^\[\ *([0-9]+)/6\] ]] && seq+="${BASH_REMATCH[1]} "; done <<< "$op"
    first4="${seq%%4 *}"
    if [[ "$RC" == 0 && "$op" == *"gate options: --parallel (the runtimes at the same time"* && "${seq// /}" =~ ^[0-9]{6}$ \
          && "$first4" != *3* && "$op" == *$'\n'"__GATE__:PASS:6:6:0:0:0:0:0:18:18" ]]; then
        kt_test_pass "line order: $seq"
    else
        kt_test_fail "rc=$RC order=[$seq] | ${op//$'\n'/ | }"
    fi
else
    kt_test_pass "skipped: no second bash runtime on this machine"
fi

kt_test_start "nothing of this file's gates is left (by its tmp path)"
kt054_pids "$TMP"
if [[ -z "$REPLY" ]]; then kt_test_pass "none"; else kt_test_fail "left: $REPLY"; fi

kt_test_log "054_GateSelection.sh completed"
