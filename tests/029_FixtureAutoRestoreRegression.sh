#!/bin/bash
# FixtureAutoRestoreRegression - guards P4.1: the auto-restore-on-teardown handler
# used to never fire (registered name had a trailing space that declare -F could
# not match) and a PID-only handler name collided across multiple backups.
# Each check runs in a subshell so it can manipulate fixture globals in isolation.

if [[ -z "$_KTEST_SOURCED" ]]; then
    source "$(dirname "$0")/../ktest_source.sh" || source "$KTEST_SOURCE_PATH" || exit 1
fi

kt_test_init "FixtureAutoRestoreRegression" "$(dirname "$0")" "$@"

# A single backed-up file must be auto-restored when teardown runs.
kt_test_start "backup is auto-restored on teardown"
_result="$(
    _KT_TMPDIR="$(mktemp -d)"
    _KT_CLEANUP_HANDLERS=()
    _KT_BACKUP_SEQ=0
    f="$(mktemp)"; printf 'ORIGINAL' > "$f"
    kt_fixture_backup_file "$f" >/dev/null 2>&1
    printf 'MODIFIED' > "$f"
    kt_fixture_teardown >/dev/null 2>&1
    cat "$f"
    rm -f "$f"
)"
if [[ "$_result" == "ORIGINAL" ]]; then
    kt_test_pass "backup is auto-restored on teardown"
else
    kt_test_fail "auto-restore did not fire (content was '$_result')"
fi

# Two backups in one process must each get their own handler and both restore.
kt_test_start "two backups in one process both auto-restore"
_result2="$(
    _KT_TMPDIR="$(mktemp -d)"
    _KT_CLEANUP_HANDLERS=()
    _KT_BACKUP_SEQ=0
    a="$(mktemp)"; printf 'A_ORIG' > "$a"
    b="$(mktemp)"; printf 'B_ORIG' > "$b"
    kt_fixture_backup_file "$a" >/dev/null 2>&1
    kt_fixture_backup_file "$b" >/dev/null 2>&1
    printf 'A_MOD' > "$a"; printf 'B_MOD' > "$b"
    kt_fixture_teardown >/dev/null 2>&1
    printf '%s:%s' "$(cat "$a")" "$(cat "$b")"
    rm -f "$a" "$b"
)"
if [[ "$_result2" == "A_ORIG:B_ORIG" ]]; then
    kt_test_pass "two backups in one process both auto-restore"
else
    kt_test_fail "collision: expected 'A_ORIG:B_ORIG', got '$_result2'"
fi
