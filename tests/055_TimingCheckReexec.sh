#!/usr/bin/env bash
# TimingCheckReexec (gate G4, found_in_G0; review round 1 R1):
# tools/timing_check.sh --bash B runs itself again under B as a CHILD started
# with `env -i`, which gets what it needs from a spec file in a private dir
# (`mktemp -d` under TMPDIR, never ktests/.tmp) named by a `--reexec SPEC`
# argument — the environment does not cross cygwin runtimes (G0 §8), and the
# old `exec env TC_REEXEC=1 …` lost its guard and the caller's variables on
# the way. The child gets an ALLOWLIST (KT_* KBOOL_* KKLASS_* VERBOSE_KKLASS*,
# LANG, LC_*, TZ, TMPDIR, HOME, the Windows basics) plus each --pass-env NAME
# — nothing else: no secret-looking variable, no other one, no exported
# function. Pinned for the same runtime and — when a second bash runtime
# exists — across runtimes (run under 5.2 this is 5.2 -> 5.3, under 5.3 the
# other direction): the values arrive (a /tmp path and TMPDIR/HOME as the
# same folders), suite and test file run under B, --log lands at the
# caller's path, the header names the re-run, the spec dir lives in TMPDIR
# while the child runs and is gone afterwards; the private dir is also gone
# after a --bash that is no bash (rc 2), after a SIGKILLed child and after a
# TERM to the parent (passed on to the child: its run in flight is stopped,
# nothing left in either runtime); `--reexec` without a spec is rc 2.
#
# On a fake root (gate_fixtures/mkroot.sh) in this file's private tmp; every
# run bounded by `timeout`, no storm (--storm 0).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "TimingCheckReexec" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
MK="$LIB/tests/gate_fixtures/mkroot.sh"
V="${BASH_VERSION%%(*}"
R="$TMP/root"
TAG="${TMP##*/}/root"      # in every command line of the fixture runs, in either spelling
TRUE="$(type -P true)"   # /usr/bin/true, /bin/true (busybox): any non-bash executable
bash "$MK" "$R" tcenv
TC="$R/ktests/tools/timing_check.sh"
SUITE="$R/tcenv/tests"
mkdir -p "$TMP/home" "$TMP/tdir"

tc055_fn() { printf 'fn-ok'; }
# kt055_m PATH — the mixed C:/ spelling (cygpath -m); PATH as is without cygpath (launch L2.1)
kt055_m() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
P="/tmp/kt055-$$-nonexistent"
P_M="$(kt055_m "$P")"; TD_M="$(kt055_m "$TMP/tdir")"; H_M="$(kt055_m "$TMP/home")"
VAR="a b'c\"d \$e"

OTHER="" OV=""
for b in /c/bin/msys64/usr/bin/bash.exe /c/msys64/usr/bin/bash.exe /c/bin/Git/usr/bin/bash.exe "/c/Program Files/Git/usr/bin/bash.exe"; do
    [[ -x "$b" ]] || continue
    OV="$("$b" -c 'printf %s "${BASH_VERSION%%(*}"' 2>/dev/null </dev/null)"
    [[ -n "$OV" && "$OV" != "$V" ]] && { OTHER="$b"; break; }
done

# kt055_pids TEXT [BASH] — REPLY = pids whose command line holds TEXT (in
# this runtime, or — with BASH — in that bash's runtime)
kt055_pids() {
    # ktest_proc.sh in that bash: /proc or ps (launch L2.1)
    local scan='source "$1"; kt_proc_pids "$2"; printf %s "$REPLY"'
    if [[ -n "${2:-}" ]]; then
        REPLY="$("$2" -c "$scan" _ "$LIB/ktest_proc.sh" "$1" < /dev/null 2>/dev/null)"
    else
        REPLY="$(bash -c "$scan" _ "$LIB/ktest_proc.sh" "$1" < /dev/null 2>/dev/null)"
    fi
}
# kt055_rxleft — REPLY = the private spec dirs left in the caller's TMPDIR
kt055_rxleft() {
    local d
    REPLY=""
    for d in "$TMP/tdir"/timing_check.*; do [[ -e "$d" ]] && REPLY+="${d##*/} "; done
    REPLY="${REPLY% }"
}
# the polluted caller: every case runs from it
kt055_caller() {
    export TC055_VAR="$VAR" KT_TC055=kt-ok KT_TC055_P="$P" TC055_SECRET_TOKEN=s3cr3t TC055_PLAIN=plain \
        LANG=C.UTF-8 HOME="$TMP/home" TMPDIR="$TMP/tdir" TC_REEXEC=1
    export -f tc055_fn
    cd "$TMP" || exit 99
}

# kt055_run TAG BASH SUITE_ARG — timing_check --bash BASH --pass-env TC055_VAR;
# RC, OUT, DUMP (the suite wrapper's view), FBASH (the test file's bash)
kt055_run() {
    local tag="$1" b="$2" s="$3" f
    rm -f -- "$SUITE"/.tc_env.* "$SUITE"/.tc_file_bash.*
    (
        kt055_caller
        exec timeout -k 10 120 bash "$TC" --bash "$b" --pass-env TC055_VAR --storm 0 --reps 1 --timeout 60 \
            --log "$TMP/log.$tag" "$s"
    ) > "$TMP/out.$tag" 2>&1 < /dev/null
    RC=$?
    OUT="$(cat "$TMP/out.$tag")"
    DUMP=""; for f in "$SUITE"/.tc_env.*; do [[ -f "$f" ]] && DUMP+="$(cat "$f")"$'\n'; done
    FBASH=""; for f in "$SUITE"/.tc_file_bash.*; do [[ -f "$f" ]] && FBASH+="$(cat "$f")"; done
}
# kt055_check TAG TARGET_VERSION — every expectation; REPLY = what is wrong
kt055_check() {
    local tag="$1" tv="$2" bad="" left
    [[ "$RC" == 0 ]] || bad+="[rc=$RC] "
    [[ "$OUT" == *"# timing_check: bash $tv"*" (re-executed from bash $V), suite "*"/tcenv/tests, targets SUITE,"* ]] || bad+="[header] "
    [[ "$OUT" =~ storm=0\ +rep=1\ +SUITE\ +PASS ]] || bad+="[no PASS line] "
    [[ "$DUMP" == *$'\n'"VAR=$VAR"$'\n'* || "$DUMP" == "VAR=$VAR"$'\n'* ]] || bad+="[--pass-env VAR] "
    grep -qx "KTVAR=kt-ok" <<< "$DUMP" || bad+="[KT_ var] "
    grep -qx "SECRET=<unset>" <<< "$DUMP" || bad+="[a secret-named var arrived] "
    grep -qx "PLAIN=<unset>" <<< "$DUMP" || bad+="[a non-allowlisted var arrived] "
    grep -q "^FN=" <<< "$DUMP" && bad+="[an exported function arrived] "
    grep -qx "BASH_V=$tv" <<< "$DUMP" || bad+="[suite bash] "
    grep -qx "LANG=C.UTF-8" <<< "$DUMP" || bad+="[LANG] "
    grep -qxF "P_M=$P_M" <<< "$DUMP" || bad+="[/tmp path: want $P_M] "
    grep -qxF "TMPDIR_M=$TD_M" <<< "$DUMP" || bad+="[TMPDIR] "
    grep -qxF "HOME_M=$H_M" <<< "$DUMP" || bad+="[HOME] "
    grep -qE "^RXDIRS=timing_check\.[^ ]+$" <<< "$DUMP" || bad+="[spec dir not in TMPDIR while running] "
    [[ "$FBASH" == "$tv" ]] || bad+="[test file bash '$FBASH'] "
    grep -q "^# timing_check: bash $tv" "$TMP/log.$tag" 2>/dev/null || bad+="[--log file] "
    kt055_rxleft; [[ -z "$REPLY" ]] || bad+="[spec dir left: $REPLY] "
    left=( "$R/ktests/.tmp"/timing_check.* )
    [[ -e "${left[0]}" ]] && bad+="[something in ktests/.tmp: ${left[*]##*/}] "
    REPLY="$bad"
}

kt_test_start "same runtime: the child (env -i) gets the allowlist + --pass-env, not a secret-named / other var / function; paths, log, header; the spec dir in TMPDIR, gone after"
kt055_run same "$(kt055_m "$BASH")" root/tcenv
kt055_check same "$V"
if [[ -z "$REPLY" ]]; then
    kt_test_pass "${OUT%%$'\n'*}"
else
    kt_test_fail "$REPLY| ${OUT//$'\n'/ | } | dump: ${DUMP//$'\n'/ }"
fi

kt_test_start "across runtimes: the same for the other bash (the allowlist + --pass-env arrive, nothing else; the same folders)"
if [[ -n "$OTHER" ]]; then
    kt055_run other "$(kt055_m "$OTHER")" "$SUITE"
    kt055_check other "$OV"
    if [[ -z "$REPLY" ]]; then
        kt_test_pass "${OUT%%$'\n'*}"
    else
        kt_test_fail "$REPLY| ${OUT//$'\n'/ | } | dump: ${DUMP//$'\n'/ }"
    fi
else
    kt_test_pass "skipped: no second bash runtime on this machine"
fi

kt_test_start "--bash that is no bash (/usr/bin/true): rc 2 'its spec was never read', the private dir removed"
out="$( ( kt055_caller; exec timeout -k 10 60 bash "$TC" --bash "$TRUE" --storm 0 --reps 1 root/tcenv ) 2>&1 < /dev/null )"; rc=$?
kt055_rxleft
if [[ "$rc" == 2 && "$out" == *"did not run timing_check (its spec was never read"* && -z "$REPLY" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "rc=$rc left='$REPLY' | $out"
fi

# kt055_held TAG BASH — timing_check in the background on a suite that waits
# for $TMP/hold.TAG; returns once the suite wrapper started (PID = the parent)
kt055_held() {
    local tag="$1" b="$2" i
    rm -f -- "$TMP/hold.$tag" "$TMP/hold.$tag".*
    (
        kt055_caller
        export TC055_HOLD="$TMP/hold.$tag"
        exec timeout -k 10 150 bash "$TC" --bash "$b" --pass-env TC055_HOLD --storm 0 --reps 1 --timeout 120 root/tcenv
    ) > "$TMP/out.$tag" 2>&1 < /dev/null &
    PID=$!
    for (( i = 0; i < 600; i++ )); do [[ -e "$TMP/hold.$tag.started" ]] && return 0; sleep 0.1; done
    return 1
}
# kt055_release TAG — let a held suite go and wait (bounded) for whatever of
# it is still running in this runtime (and, with BASH, in that one)
kt055_release() {
    local i
    : > "$TMP/hold.$1"
    for (( i = 0; i < 300; i++ )); do
        kt055_pids "$TAG" "${2:-}"; [[ -z "$REPLY" ]] && break
        sleep 0.1
    done
}

kt_test_start "a SIGKILLed child: the parent ends, its EXIT trap removes the private dir"
if kt055_held kill "$(kt055_m "$BASH")"; then
    cp=""; for d in "$TMP/tdir"/timing_check.*; do [[ -f "$d/pid" ]] && read -r cp < "$d/pid"; done
    [[ "$cp" =~ ^[0-9]+$ ]] && kill -KILL "$cp" 2>/dev/null
    wait "$PID"; rc=$?
    kt055_rxleft; left="$REPLY"
    kt055_release kill
    if [[ "$cp" =~ ^[0-9]+$ && "$rc" != 0 && -z "$left" ]]; then
        kt_test_pass "child $cp killed, parent rc $rc, nothing left in TMPDIR"
    else
        kt_test_fail "child='$cp' rc=$rc left='$left' | $(cat "$TMP/out.kill")"
    fi
else
    kill -TERM "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; kt055_release kill
    kt_test_fail "the held suite never started | $(cat "$TMP/out.kill")"
fi

kt_test_start "a TERM to the parent is passed on to the child of the other runtime (same runtime without one): rc 143, the run in flight stopped, the private dir gone, nothing left"
TB="$BASH"; [[ -n "$OTHER" ]] && TB="$OTHER"
if kt055_held term "$(kt055_m "$TB")"; then
    # the TERM goes to timing_check itself (its private dir's owner file), not
    # to the `timeout` around it: uutils timeout -k answers a TERM it receives
    # with 124 (0.12.0) or 125 (0.2.2) whatever the child does (launch OG8-o1);
    # timeout then passes the parent's own exit status on, on every flavour
    op=""; for d in "$TMP/tdir"/timing_check.*; do [[ -f "$d/owner" ]] && read -r op _ < "$d/owner"; done
    if [[ "$op" =~ ^[0-9]+$ ]]; then kill -TERM "$op" 2>/dev/null; else kill -TERM "$PID" 2>/dev/null; fi
    wait "$PID"; rc=$?
    released=no; [[ -e "$TMP/hold.term.released" ]] && released=yes
    kt055_rxleft; left="$REPLY"
    for (( i = 0; i < 50; i++ )); do
        kt055_pids "$TAG" "$([[ -n "$OTHER" ]] && printf %s "$OTHER")"; procs="$REPLY"
        [[ -z "$procs" ]] && break
        sleep 0.1
    done
    kt055_release term "$([[ -n "$OTHER" ]] && printf %s "$OTHER")"
    if [[ "$rc" == 143 && "$released" == no && -z "$left" && -z "$procs" ]]; then
        kt_test_pass "rc 143 under $TB; the held suite stopped before its release; nothing left"
    else
        kt_test_fail "rc=$rc released=$released left='$left' procs='$procs' | $(cat "$TMP/out.term")"
    fi
else
    kill -TERM "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; kt055_release term "$OTHER"
    kt_test_fail "the held suite never started | $(cat "$TMP/out.term")"
fi

kt_test_start "a killed parent's private dir is swept by the next --bash run: dead owner of this runtime and an other-runtime one > 24 h go; a live owner, a young other-runtime one and an unmarked dir stay (G4 review R13)"
RTN="$(bash -c 'r=none; [[ -r /proc/mounts ]] && while read -r a b c; do [[ $b == / ]] && { r=$a; break; }; done < /proc/mounts; printf %s "$r"')"
dead="$(bash -c 'echo $$')"
mkdir -p "$TMP/tdir/timing_check.sw_dead" "$TMP/tdir/timing_check.sw_live" "$TMP/tdir/timing_check.sw_oyoung" \
         "$TMP/tdir/timing_check.sw_oold" "$TMP/tdir/timing_check.sw_plain"
printf '%s %s %s\n' "$dead" "$RTN" "$(( EPOCHSECONDS - 100 ))" > "$TMP/tdir/timing_check.sw_dead/owner"
printf '%s %s %s\n' "$$" "$RTN" "$(( EPOCHSECONDS - 100 ))" > "$TMP/tdir/timing_check.sw_live/owner"
printf '%s %s %s\n' 4242 other-runtime "$(( EPOCHSECONDS - 100 ))" > "$TMP/tdir/timing_check.sw_oyoung/owner"
printf '%s %s %s\n' 4242 other-runtime "$(( EPOCHSECONDS - 90000 ))" > "$TMP/tdir/timing_check.sw_oold/owner"
( kt055_caller; exec timeout -k 10 60 bash "$TC" --bash "$TRUE" --storm 0 --reps 1 root/tcenv ) > /dev/null 2>&1 < /dev/null
kt055_rxleft; left="$REPLY"
rm -rf "$TMP/tdir"/timing_check.sw_*
if [[ "$left" == "timing_check.sw_live timing_check.sw_oyoung timing_check.sw_plain" ]]; then
    kt_test_pass "left: $left"
else
    kt_test_fail "left: [$left]"
fi

kt_test_start "--reexec without a readable spec: rc 2, a message, nothing run"
out="$(timeout -k 10 60 bash "$TC" --reexec "$TMP/no-such.spec" 2>&1 < /dev/null)"; rc=$?
if [[ "$rc" == 2 && "$out" == *"--reexec needs a readable spec file"* && "$out" != *"# timing_check:"* ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "rc=$rc | $out"
fi
