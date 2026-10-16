#!/bin/bash
# FixtureBaseAbsolute (ktests round 5, T8 / DT8, 2026-10-16).
#
# 159 test files pass `$(dirname "$0")` to kt_test_init — RELATIVE when a file
# is run standalone as `bash tests/NNN_X.sh`. The fixture dir was then relative
# too, and MSYS `ln -s` (copy mode) resolves a relative target from the LINK's
# folder: 017's symlink test fell into its fallback, passed there and passed
# AGAIN in its final if/else (standalone __COUNTS__:13:14:0, runner 13/13; the
# test could never fail). Now:
#   - kt_fixture_setup makes the fixture base absolute once, for every caller;
#   - 017's symlink test does exactly one pass/fail (ktests has no skip: when
#     symlinks are unavailable it is one pass with a "symlinks unavailable" note).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "FixtureBaseAbsolute" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"
FX="$TMP/fx"
mkdir -p "$FX/tests"
# a framework entry next to the copied tests, as in a real suite layout
printf 'source %q\n' "$LIB/ktest.sh" > "$FX/ktest_source.sh"

cat > "$FX/tests/probe.sh" <<'FIXEOF'
source "$(dirname "$0")/../ktest_source.sh"
kt_test_init "Probe" "$(dirname "$0")"
printf 'FIXDIR=%s\n' "$(kt_fixture_tmpdir)"
kt_test_start "probe"; kt_test_pass "probe"
FIXEOF

kt_test_start "a relative script dir gives an ABSOLUTE fixture dir, removed at teardown [T8]"
out="$(cd "$FX" && KK_OUTPUT_COUNTS=1 bash tests/probe.sh 2>&1)"
fixdir="$(printf '%s\n' "$out" | sed -n 's/^FIXDIR=//p')"
want="$(cd "$FX" && pwd)/tests/.tmp/Probe.probe"
left="$(cd "$FX/tests" && ls -A .tmp 2>/dev/null)"
if [[ "$fixdir" == "$want" && "$out" == *"__COUNTS__:1:1:0"* && -z "$left" ]]; then
    kt_test_pass "$fixdir"
else
    kt_test_fail "fixdir='$fixdir' want='$want' left=[$left] out=[${out//$'\n'/ | }]"
fi

kt_test_start "kt_fixture_setup with a relative base: the fixture dir is absolute [T8]"
out="$(cd "$FX" && bash -c '
source "$1"
kt_fixture_setup "Rel.x" "tests"
printf "%s" "$(kt_fixture_tmpdir)"
kt_fixture_teardown' _ "$LIB/ktest.sh" 2>&1)"
if [[ "$out" == "$(cd "$FX" && pwd)/tests/.tmp/Rel.x" && ! -e "$FX/tests/.tmp/Rel.x" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi

# review R8: the join trusts no broken $PWD, and knows drive paths. The
# children refuse a mkdir outside this fixture (a wrong join must not create
# /tests/.tmp at the MSYS root).
KT041_GUARD='mkdir() { local a; for a; do case $a in -*) ;; "$G"*|[A-Za-z]:*|[!/]*) ;; *) echo "refused mkdir $a" >&2; return 1 ;; esac; done; command mkdir "$@"; }'
kt_test_start "a relative base with \$PWD unset or not absolute: joined to the real cwd [R8]"
fxabs="$(cd "$FX" && pwd)"
got=""
for how in 'unset PWD' 'PWD=zz'; do
    got+="$(cd "$FX" && G="$fxabs" bash -c "source \"\$1\"; $KT041_GUARD; $how"'
kt_fixture_setup "Pw.x" "tests"; printf "%s|" "$(kt_fixture_tmpdir)"; kt_fixture_teardown' _ "$LIB/ktest.sh" 2>&1)"
done
if [[ "$got" == "$fxabs/tests/.tmp/Pw.x|$fxabs/tests/.tmp/Pw.x|" ]]; then
    kt_test_pass "both: $fxabs/tests/.tmp/Pw.x"
else
    kt_test_fail "got '$got'"
fi

kt_test_start "drive paths: C:/… and C:\\… are absolute (kept), a drive-relative c:x is relative to the cwd (MSYS reads it so) [R8]"
mixed="$(cygpath -m "$FX" 2>/dev/null)"; [[ -n "$mixed" ]] || mixed="C:/kt041/none"
win="${mixed//\//\\}"
got="$(cd "$FX" && G="$fxabs" bash -c 'source "$1"; eval "$4"
for b in "$2/tests" "$3\\tests" "c:rel"; do
    kt_fixture_setup "Dr.x" "$b"; printf "%s|" "$_KT_TMPDIR"; kt_fixture_teardown
done' _ "$LIB/ktest.sh" "$mixed" "$win" "$KT041_GUARD" 2>&1)"
want="$mixed/tests/.tmp/Dr.x|$win\\tests/.tmp/Dr.x|$fxabs/c:rel/.tmp/Dr.x|"
if [[ "$got" == "$want" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "got '$got' want '$want'"
fi

# 017 copied next to its own framework entry and run standalone with a
# RELATIVE $0, the way a developer runs it: every started test passes once.
cp "$SCRIPT_DIR/017_AdvancedFileSystemAssertions.sh" "$FX/tests/"
kt_test_start "017 standalone (relative \$0): one verdict per test, counts equal the runner's [T8]"
out="$(cd "$FX" && KK_OUTPUT_COUNTS=1 bash tests/017_AdvancedFileSystemAssertions.sh 2>&1)"
counts="$(printf '%s\n' "$out" | grep -a '^__COUNTS__:' | tail -n 1)"
st=$TESTS_TOTAL sp=$TESTS_PASSED sf=$TESTS_FAILED
kt_runner_execute_single_test "$FX/tests/017_AdvancedFileSystemAssertions.sh" >/dev/null 2>&1
rcounts="$count_total:$count_passed:$count_failed"
TESTS_TOTAL=$st; TESTS_PASSED=$sp; TESTS_FAILED=$sf
IFS=':' read -r _ t p f <<< "$counts"
if [[ -n "$t" && "$t" == "$p" && "$f" == 0 && "$t:$p:$f" == "$rcounts" ]]; then
    kt_test_pass "standalone $t:$p:$f == runner $rcounts"
else
    kt_test_fail "standalone '$counts' runner '$rcounts'"
fi

kt_test_start "017's symlink test cannot pass when the link is missing [T8]"
# the final check of that test, isolated: a missing link must FAIL
sed -n '/^kt_test_start "File assertions with symbolic links"/,/^# Test with hidden files/p' \
    "$SCRIPT_DIR/017_AdvancedFileSystemAssertions.sh" > "$FX/sym.body"
cat > "$FX/tests/sym.sh" <<FIXEOF
source "\$(dirname "\$0")/../ktest_source.sh"
kt_test_init "Sym" "\$(dirname "\$0")"
TMPDIR=\$(kt_fixture_tmpdir)
ln() { return 0; }    # "succeeds" but makes no link
source "$FX/sym.body"
FIXEOF
out="$(cd "$FX" && KK_OUTPUT_COUNTS=1 bash tests/sym.sh 2>&1)"
counts="$(printf '%s\n' "$out" | grep -a '^__COUNTS__:' | tail -n 1)"
if [[ "$counts" == "__COUNTS__:1:0:1" ]]; then
    kt_test_pass "missing link -> $counts"
else
    kt_test_fail "missing link -> '$counts' (want __COUNTS__:1:0:1)"
fi

kt_test_log "041_FixtureBaseAbsolute.sh completed"
