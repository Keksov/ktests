#!/bin/bash
# FixtureAutoRestoreRegression - guards P4.1: the auto-restore-on-teardown handler
# used to never fire (registered name had a trailing space that declare -F could
# not match) and a PID-only handler name collided across multiple backups.
# Each check runs in a subshell so it can manipulate fixture globals in isolation.

if [[ -z "$_KTEST_SOURCED" ]]; then
    source "$(dirname "$0")/../ktest_source.sh" || source "$KTEST_SOURCE_PATH" || exit 1
fi

kt_test_init "FixtureAutoRestoreRegression" "$(dirname "$0")" "$@"

# This file's own fixture dir (kt_test_init). The inner blocks below must leave
# it alone and must not leak anything outside it (round 4, T6).
_kt029_outer="$_KT_TMPDIR"

# A single backed-up file must be auto-restored when teardown runs.
kt_test_start "backup is auto-restored on teardown"
_result="$(
    # Own scratch dir UNDER the fixture dir of this file, and REPLACE (not append)
    # the inherited list: the inner teardown then removes exactly this dir,
    # never the outer fixture dir, and nothing lands in $TMPDIR (round 4, T6/DT6).
    _KT_TMPDIR="$(mktemp -d "$_kt029_outer/inner.XXXXXX")"
    _KT_CREATED_TMPDIRS=("$_KT_TMPDIR")
    _KT_CLEANUP_HANDLERS=()
    _KT_BACKUP_SEQ=0
    _inner="$_KT_TMPDIR"
    f="$(mktemp "$_kt029_outer/f.XXXXXX")"; printf 'ORIGINAL' > "$f"
    kt_fixture_backup_file "$f" >/dev/null 2>&1
    printf 'MODIFIED' > "$f"
    kt_fixture_teardown >/dev/null 2>&1
    cat "$f"
    rm -f "$f"
    printf '\n%s' "$([[ -d "$_inner" ]] && echo left || echo removed)"
)"
_inner_state1="${_result##*$'\n'}"
_result="${_result%$'\n'*}"
if [[ "$_result" == "ORIGINAL" ]]; then
    kt_test_pass "backup is auto-restored on teardown"
else
    kt_test_fail "auto-restore did not fire (content was '$_result')"
fi

# Two backups in one process must each get their own handler and both restore.
kt_test_start "two backups in one process both auto-restore"
_result2="$(
    _KT_TMPDIR="$(mktemp -d "$_kt029_outer/inner.XXXXXX")"
    _KT_CREATED_TMPDIRS=("$_KT_TMPDIR")
    _KT_CLEANUP_HANDLERS=()
    _KT_BACKUP_SEQ=0
    _inner="$_KT_TMPDIR"
    a="$(mktemp "$_kt029_outer/a.XXXXXX")"; printf 'A_ORIG' > "$a"
    b="$(mktemp "$_kt029_outer/b.XXXXXX")"; printf 'B_ORIG' > "$b"
    kt_fixture_backup_file "$a" >/dev/null 2>&1
    kt_fixture_backup_file "$b" >/dev/null 2>&1
    printf 'A_MOD' > "$a"; printf 'B_MOD' > "$b"
    kt_fixture_teardown >/dev/null 2>&1
    printf '%s:%s' "$(cat "$a")" "$(cat "$b")"
    rm -f "$a" "$b"
    printf '\n%s' "$([[ -d "$_inner" ]] && echo left || echo removed)"
)"
_inner_state2="${_result2##*$'\n'}"
_result2="${_result2%$'\n'*}"
if [[ "$_result2" == "A_ORIG:B_ORIG" ]]; then
    kt_test_pass "two backups in one process both auto-restore"
else
    kt_test_fail "collision: expected 'A_ORIG:B_ORIG', got '$_result2'"
fi

# T6: an inner teardown removes exactly its own scratch dir (no tmp.* leak) ...
kt_test_start "each inner teardown removes its own scratch dir"
if [[ "$_inner_state1" == "removed" && "$_inner_state2" == "removed" ]]; then
    kt_test_pass "each inner teardown removes its own scratch dir"
else
    kt_test_fail "inner scratch dir left behind (block 1: '$_inner_state1', block 2: '$_inner_state2')"
fi

# ... and not the outer fixture dir it inherited the list of (round 4, T6/C13).
kt_test_start "inner teardowns leave the outer fixture dir alone"
if [[ -n "$_kt029_outer" && -d "$_kt029_outer" ]]; then
    kt_test_pass "inner teardowns leave the outer fixture dir alone"
else
    kt_test_fail "outer fixture dir '$_kt029_outer' removed by an inner teardown"
fi
