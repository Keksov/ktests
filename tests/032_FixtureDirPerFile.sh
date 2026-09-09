#!/bin/bash
# FixtureDirPerFile (kcl review P8-F2, owner decision 2026-09-09).
#
# The per-file fixture directory used to be `<tests>/.tmp/<name passed to
# kt_test_init>`. Two files of one suite that pass the same name (or derive it
# from something shared) got the same directory, and under the 8-worker runner
# one file's EXIT teardown deleted the other's fixtures mid-run. The directory
# now also carries the test FILE's name, so a collision is impossible whatever
# name the file passes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "FixtureDirPerFile" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
mkdir -p "$TMP/suite"
for f in alpha beta; do
cat > "$TMP/suite/probe_$f.sh" <<'FIXEOF'
#!/bin/bash
source "$KTEST_SOURCE_PATH"
kt_test_init "SameName" "$(dirname "$0")"
kt_test_start "probe"
printf 'FIXDIR=%s\n' "$(kt_fixture_tmpdir)"
kt_test_pass "probe"
FIXEOF
done

kt_test_start "two files passing the same kt_test_init name get DIFFERENT fixture dirs [P8-F2]"
kt_runner_execute_single_test "$TMP/suite/probe_alpha.sh" >/dev/null 2>&1; a="$(printf '%s\n' "$output_content" | sed -n 's/^FIXDIR=//p')"
kt_runner_execute_single_test "$TMP/suite/probe_beta.sh"  >/dev/null 2>&1; b="$(printf '%s\n' "$output_content" | sed -n 's/^FIXDIR=//p')"
if [[ -n "$a" && -n "$b" && "$a" != "$b" ]]; then
    kt_test_pass "$(basename "$a") vs $(basename "$b")"
else
    kt_test_fail "alpha='$a' beta='$b'"
fi

kt_test_start "the fixture dir name carries the test file name [P8-F2]"
[[ "$a" == *probe_alpha* ]] && kt_test_pass "$(basename "$a")" || kt_test_fail "dir '$a' does not mention probe_alpha"

kt_test_start "this file's own fixture dir follows the same rule"
[[ "$TMP" == *032_FixtureDirPerFile* ]] && kt_test_pass "$(basename "$TMP")" || kt_test_fail "$TMP"

kt_test_log "032_FixtureDirPerFile.sh completed"
