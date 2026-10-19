#!/bin/bash
# ConcurrentFixtureRuns (ktests round 6, S2; 2026-10-18). The fixture dir was
# `<tests>/.tmp/<Name>.<file>` — the same for every run of a file: a second
# run's setup wiped the first run's LIVE dir as "stale" and the runner's
# leftover sweep removed `.tmp/*.<file>` of a run still at work (critic F5:
# two concurrent `bash 027_….sh` -> one FAILs). Now the dir is per run,
# `<Name>.<file>.<pid>` with an owner mark (the sibling `<dir>.owner` = the
# runtime; the dir itself starts empty), and only
# a dir whose owner is gone is wiped / swept (kt_fixture_stale_dir).
#
# The standalone runs drop the runner variables this file inherits (a real
# `bash FILE`). Every run here ends by itself: the hold fixture waits at most ~10 s for its
# partner, each run is under `timeout -k 30 60`, all are waited for.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ConcurrentFixtureRuns" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
FX="$TMP/fx"
mkdir -p "$FX/tests" "$TMP/sync" "$TMP/iso"
export KT046_LIB="$LIB" KT046_SYNC="$TMP/sync"

# the hold fixture: a token in its fixture dir, announce, wait (fork-free, at
# most ~10 s) until two runs have announced, hold 0.5 s, then the token must
# still be its own
cat > "$FX/tests/001_hold.sh" <<'FIXEOF'
source "${KTEST_SOURCE_PATH:-$KT046_LIB/ktest_source.sh}"
kt_test_init "Hold" "${KT_TESTS_DIR:-$(dirname "$0")}"
D="$(kt_fixture_tmpdir)"
# isolation witness: at its OWN teardown the dir must still be there (a run
# whose live dir was taken by the other run would see it GONE)
kt046_mark() { if [[ -d "$D" ]]; then echo "present ${D##*/}"; else echo "GONE ${D##*/}"; fi >> "$KT046_SYNC/teardown"; }
kt_fixture_cleanup_register kt046_mark
echo "$$" > "$D/token"
: > "$KT046_SYNC/ready.$$"
exec {w}<>/dev/ptmx 2>/dev/null || exec {w}</dev/null
for (( i = 0; i < 100; i++ )); do
    r=( "$KT046_SYNC"/ready.* )
    (( ${#r[@]} >= 2 )) && break
    read -t 0.1 -u $w _ || (( $? > 128 )) || sleep 0.1
done
read -t 0.5 -u $w _ || (( $? > 128 )) || sleep 0.5
kt_test_start "my fixture dir survives a concurrent run of the same file"
if [[ "$(cat "$D/token" 2>/dev/null)" == "$$" ]]; then echo "HOLD:ok:${D##*/}"; kt_test_pass "${D##*/}"; else echo "HOLD:bad:${D##*/}"; kt_test_fail "token of ${D##*/} is [$(cat "$D/token" 2>/dev/null)], not $$"; fi
FIXEOF

kt046_left() { local e o=""; for e in "$FX/tests/.tmp/"* "$FX/tests/.tmp/".[!.]*; do [[ -e "$e" ]] && o+="${e##*/} "; done; printf '%s' "${o% }"; }

# kt046_isolated TEXT — rc 0 when both hold runs reached their own teardown with
# their dir PRESENT (no run lost its live dir) and every [WARN] in TEXT is the
# runner's fixture-dir WARN for such a dir: one whose owner's own removal failed
# (a native Windows handle without FILE_SHARE_DELETE — a virus scanner — on a
# file in it, beyond the teardown's retries: the dir outlived its owner and the
# runner removed it; seen once in a full-load master sweep, 2026-10-19).
# REPLY = what was seen.
kt046_isolated() {
    local l d np re='fixture dir \.tmp/(Hold\.001_hold\.[0-9.]+) left behind'
    REPLY=""
    grep -q '^GONE' "$KT046_SYNC/teardown" 2>/dev/null && { REPLY="$(tr '\n' ' ' < "$KT046_SYNC/teardown")"; return 1; }
    np="$(grep -c '^present ' "$KT046_SYNC/teardown" 2>/dev/null)"
    [[ "$np" == 2 ]] || { REPLY="teardowns: $np"; return 1; }
    while IFS= read -r l; do
        [[ "$l" == *"[WARN]"* ]] || continue
        [[ "$l" =~ $re ]] || { REPLY="other WARN: $l"; return 1; }
        d="${BASH_REMATCH[1]}"
        grep -qx "present $d" "$KT046_SYNC/teardown" || { REPLY="WARN for $d, not present at its owner's teardown"; return 1; }
        REPLY+="(owner-side leftover swept: $d) "
    done <<< "$1"
    return 0
}

kt_test_start "two concurrent standalone runs of one file: both pass, each has its own dir, nothing is left [S2]"
rm -rf "$FX/tests/.tmp" "$TMP/sync/"*
timeout -k 30 60 env -u KK_OUTPUT_COUNTS -u KT_TESTS_DIR -u KTEST_SOURCE_PATH -u VERBOSITY -u _KTEST_QUIET_MODE -u _KT_ASSERT_QUIET_MODE bash "$FX/tests/001_hold.sh" > "$TMP/s1.out" 2>&1 &
p1=$!
timeout -k 30 60 env -u KK_OUTPUT_COUNTS -u KT_TESTS_DIR -u KTEST_SOURCE_PATH -u VERBOSITY -u _KTEST_QUIET_MODE -u _KT_ASSERT_QUIET_MODE bash "$FX/tests/001_hold.sh" > "$TMP/s2.out" 2>&1 &
p2=$!
wait "$p1"; r1=$?; wait "$p2"; r2=$?
o1="$(cat "$TMP/s1.out")"; o2="$(cat "$TMP/s2.out")"
left="$(kt046_left)"
iso=no; kt046_isolated "$o1$o2" && iso=yes; why="$REPLY"
if [[ "$o1" == *"HOLD:ok:"* && "$o2" == *"HOLD:ok:"* && "$o1$o2" != *"[FAIL]"* && "$r1" == 0 && "$r2" == 0 && -z "$left" && "$iso" == yes ]]; then
    kt_test_pass "rc $r1/$r2: ${o1//$'\n'/ } || ${o2//$'\n'/ }"
else
    kt_test_fail "rc $r1/$r2 left=[$left] isolated=$iso [$why] | ${o1//$'\n'/ | } || ${o2//$'\n'/ | }"
fi

for mode in single threaded; do
    kt_test_start "two concurrent runs of one suite ($mode): both pass, nothing is left [S2]"
    rm -rf "$FX/tests/.tmp" "$TMP/sync/"*
    TMPDIR="$TMP/iso" timeout -k 30 60 env -u KTESTS_LIB_DIR bash "$LIB/ktests.sh" "$FX/tests" H '/[0-9][0-9][0-9]_' -m "$mode" -v info > "$TMP/r1.out" 2>&1 &
    p1=$!
    TMPDIR="$TMP/iso" timeout -k 30 60 env -u KTESTS_LIB_DIR bash "$LIB/ktests.sh" "$FX/tests" H '/[0-9][0-9][0-9]_' -m "$mode" -v info > "$TMP/r2.out" 2>&1 &
    p2=$!
    wait "$p1"; r1=$?; wait "$p2"; r2=$?
    o1="$(cat "$TMP/r1.out")"; o2="$(cat "$TMP/r2.out")"
    left="$(kt046_left)"
    iso=no; kt046_isolated "$o1"$'\n'"$o2" && iso=yes; why="$REPLY"
    if [[ "$r1" == 0 && "$r2" == 0 && "$o1$o2" != *"[FAIL]"* && "$iso" == yes \
          && "$(grep -c 'survives a concurrent run' <<< "$o1"$'\n'"$o2")" -ge 2 && -z "$left" ]]; then
        kt_test_pass "rc $r1/$r2, no FAIL, each run kept its live dir, nothing left ${why:+— $why}"
    else
        kt_test_fail "rc $r1/$r2 left=[$left] isolated=$iso [$why] | $(grep -a -E 'FAIL|WARN|Passed|Failed' <<< "$o1" | tr '\n' ' ') || $(grep -a -E 'FAIL|WARN|Passed|Failed' <<< "$o2" | tr '\n' ' ')"
    fi
done


# ---- the owner mark is a sibling file: the fixture dir starts empty ----------
kt_test_start "a fresh fixture dir is empty (the owner mark is the sibling <dir>.owner); teardown removes both [S2, critic r6b]"
rm -rf "$TMP/empty"
got="$(bash -c 'source "$1/ktest.sh"; kt_fixture_setup "E.x" "$2"; d="$_KT_TMPDIR"
printf "[%s] " "$(ls -A "$d")"; [[ -f "$d.owner" ]] && printf "mark=%s " "$(cat "$d.owner")"
kt_fixture_teardown; printf "after=[%s]" "$(ls -A "$2/.tmp")"' _ "$LIB" "$TMP/empty" 2>&1)"
kt_fixture_owner_mark
if [[ "$got" == "[] mark=$REPLY after=[]" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "got [$got] (want '[] mark=$REPLY after=[]')"
fi
rm -rf "$TMP/empty"

# a removal that FAILS at teardown — on Windows a native handle opened
# without FILE_SHARE_DELETE (a virus scanner reading a file just written)
# makes `rm -rf` fail with "Device or resource busy" while it is held — is
# retried, so the dir does not outlive its owner (the full-load master sweep
# of 2026-10-19 swept such a dir with a WARN). The `rm` shim fails twice; the
# shell runs under set -e (the retry loop must not end the teardown).
kt_test_start "teardown retries a failed removal (a busy file in the dir): dir and mark are gone, even under set -e [S2]"
rm -rf "$TMP/busy"
got="$(bash -c 'source "$1/ktest.sh"; kt_fixture_setup "B.x" "$2"; echo x > "$_KT_TMPDIR/f"
n=0; rm() { (( ++n <= 2 )) && return 1; command rm "$@"; }
set -e; kt_fixture_teardown; set +e
printf "calls=%s left=[%s]" "$n" "$(ls -A "$2/.tmp")"' _ "$LIB" "$TMP/busy" 2>&1)"
if [[ "$got" == "calls=3 left=[]" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "got [$got] (want 'calls=3 left=[]')"
fi
rm -rf "$TMP/busy"

# ---- the stale rules, in one setup -------------------------------------------
# a pid that is gone: a finished child of this shell
bash -c ':' & dead=$!; wait "$dead"
kt_fixture_owner_mark; own="$REPLY"
kt_test_start "setup wipes a dir of a gone owner (mark as sibling or, from the first draft, inside) with its mark, the legacy fixed name and a mark without its dir; keeps a live owner's and the other runtime's (young) dir [S2]"
B="$TMP/rules/.tmp"
rm -rf "$TMP/rules"; mkdir -p "$B/R.x.$dead" "$B/R.x.$$" "$B/R.x.$dead.1" "$B/R.x" "$B/R.x.77777" "$B/R.x.77778" "$B/R.xx.$dead" "$B/R.x.abc"
for d in "$B/R.x.$dead" "$B/R.x.$$" "$B/R.xx.$dead"; do printf '%s\n' "$own" > "$d.owner"; done
printf '%s\n' "$own" > "$B/R.x.$dead.1/.kt_owner"                    # first-draft inside mark
printf '%s\n' "$own" > "$B/R.x.$dead.3.owner"                        # a mark whose dir is gone
printf '%s\n' "C:/some/other/runtime" > "$B/R.x.77777.owner"
printf '%s\n' "C:/some/other/runtime" > "$B/R.x.77778/.kt_owner"     # other runtime, inside mark
got="$(bash -c 'source "$1/ktest.sh"; kt_fixture_setup "R.x" "$2"; printf "%s" "${_KT_TMPDIR##*/}"; printf " %s" "$(cat "$_KT_TMPDIR.owner")"' _ "$LIB" "$TMP/rules" 2>&1)"
gone=""; kept=""
for n in "R.x.$dead" "R.x.$dead.owner" "R.x.$dead.1" "R.x" "R.x.$dead.3.owner"; do [[ -e "$B/$n" ]] && kept+="$n " || gone+="$n "; done
other=""
for n in "R.x.$$" "R.x.$$.owner" "R.x.77777" "R.x.77777.owner" "R.x.77778" "R.xx.$dead" "R.xx.$dead.owner" "R.x.abc"; do [[ -e "$B/$n" ]] || other+="$n "; done
if [[ "$got" == "R.x."[0-9]*" $own" && -z "$kept" && -z "$other" ]]; then
    kt_test_pass "new dir $got; wiped: $gone; live, foreign, other-id, non-pid dirs kept"
else
    kt_test_fail "got=[$got] (want R.x.<pid> $own) not wiped=[$kept] wrongly gone=[$other]"
fi

kt_test_start "kt_fixture_stale_dir: own runtime + dead pid -> stale (sibling or inside mark); live pid, foreign young, unmarked young -> not stale [S2]"
res=""
for n in "R.x.$$" "R.x.77777" "R.x.77778"; do kt_fixture_stale_dir "$B/$n" "$B/R.x." && res+="$n:stale " || res+="$n:kept "; done
mkdir -p "$B/R.x.$dead"; printf '%s\n' "$own" > "$B/R.x.$dead.owner"
kt_fixture_stale_dir "$B/R.x.$dead" "$B/R.x." && res+="dead:stale " || res+="dead:kept "
mkdir -p "$B/R.x.$dead.1"; printf '%s\n' "$own" > "$B/R.x.$dead.1/.kt_owner"
kt_fixture_stale_dir "$B/R.x.$dead.1" "$B/R.x." && res+="dead-inside:stale " || res+="dead-inside:kept "
mkdir -p "$B/R.x.$dead.2"
kt_fixture_stale_dir "$B/R.x.$dead.2" "$B/R.x." && res+="unmarked:stale " || res+="unmarked:kept "
if [[ "$res" == "R.x.$$:kept R.x.77777:kept R.x.77778:kept dead:stale dead-inside:stale unmarked:kept " ]]; then
    kt_test_pass "$res"
else
    kt_test_fail "$res"
fi
rm -rf "$TMP/rules"

kt_test_log "046_ConcurrentFixtureRuns.sh completed"
