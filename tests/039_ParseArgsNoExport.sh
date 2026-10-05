#!/bin/bash
# ParseArgsNoExport (ktests round 4, T7 / DT7, 2026-10-05).
#
# kt_runner_parse_args used to end with
#   export VERBOSITY MODE WORKERS TEST_SELECTION FAILED_TEST_FILES _KT_ASSERT_QUIET_MODE _KTEST_QUIET_MODE
# On bash 5.2 that `export` turns a prefix assignment (`MODE=single kt_runner_parse_args`)
# into a permanent global (MODE then stays `threaded`, the function's own value); on
# both bashes a plain call added the export attribute to the caller's globals. Nobody
# needs it: the single-test wrapper passes VERBOSITY and both quiet modes explicitly,
# the threaded runner exports in its own subshell. Each check runs in a subshell.

if [[ -z "$_KTEST_SOURCED" ]]; then
    source "$(dirname "$0")/../ktest_source.sh" || source "$KTEST_SOURCE_PATH" || exit 1
fi

kt_test_init "ParseArgsNoExport" "$(dirname "$0")" "$@"

_kt039_names=(VERBOSITY _KT_ASSERT_QUIET_MODE _KTEST_QUIET_MODE MODE WORKERS TEST_SELECTION)

# kt039_prefix NAME BEFORE PREFIX — value of NAME after `NAME=PREFIX kt_runner_parse_args`
# when it was BEFORE (non-exported) going in.
kt039_prefix() {
    local __n="$1" __before="$2" __prefix="$3"
    (
        declare +x "${_kt039_names[@]}" 2>/dev/null
        printf -v "$__n" '%s' "$__before"
        case "$__n" in
            VERBOSITY)             VERBOSITY="$__prefix" kt_runner_parse_args >/dev/null 2>&1 ;;
            _KT_ASSERT_QUIET_MODE) _KT_ASSERT_QUIET_MODE="$__prefix" kt_runner_parse_args >/dev/null 2>&1 ;;
            _KTEST_QUIET_MODE)     _KTEST_QUIET_MODE="$__prefix" kt_runner_parse_args >/dev/null 2>&1 ;;
            MODE)                  MODE="$__prefix" kt_runner_parse_args >/dev/null 2>&1 ;;
            WORKERS)               WORKERS="$__prefix" kt_runner_parse_args >/dev/null 2>&1 ;;
            TEST_SELECTION)        TEST_SELECTION="$__prefix" kt_runner_parse_args >/dev/null 2>&1 ;;
        esac
        printf '%s' "${!__n}"
    )
}

# NAME BEFORE PREFIX: BEFORE differs from both PREFIX and the value the function
# itself assigns (VERBOSITY keeps the prefix, MODE->threaded, WORKERS->8, TEST_SELECTION->"").
while read -r _n _before _prefix; do
    kt_test_start "prefix assignment of $_n does not persist"
    _after="$(kt039_prefix "$_n" "$_before" "$_prefix")"
    if [[ "$_after" == "$_before" ]]; then
        kt_test_pass "prefix assignment of $_n does not persist"
    else
        kt_test_fail "$_n=$_prefix kt_runner_parse_args left $_n='$_after' (was '$_before', bash $BASH_VERSION)"
    fi
done <<'EOF'
VERBOSITY info error
_KT_ASSERT_QUIET_MODE normal quiet
_KTEST_QUIET_MODE normal quiet
MODE single single
WORKERS 2 3
TEST_SELECTION 1 zz
EOF

# A plain call must not add the export attribute to the caller's globals.
_kt039_attrs="$(
    declare +x "${_kt039_names[@]}" 2>/dev/null
    kt_runner_parse_args --mode=single --workers=2 >/dev/null 2>&1
    for _n in "${_kt039_names[@]}" FAILED_TEST_FILES; do
        _d="$(declare -p "$_n" 2>/dev/null)"; _d="${_d#declare -}"; _d="${_d%% *}"
        [[ "$_d" == *x* ]] && printf '%s ' "$_n"
    done
    printf 'mode=%s workers=%s' "$MODE" "$WORKERS"
)"
kt_test_start "a plain call adds no export attribute"
if [[ "$_kt039_attrs" == "mode=single workers=2" ]]; then
    kt_test_pass "a plain call adds no export attribute"
else
    kt_test_fail "exported after a plain call / parsed values: '$_kt039_attrs'"
fi

# The parsed values still reach a child only when passed explicitly (the wrapper's way).
kt_test_start "explicitly passed VERBOSITY reaches a child"
_kt039_child="$(
    declare +x "${_kt039_names[@]}" 2>/dev/null
    kt_runner_parse_args --verbosity=info >/dev/null 2>&1
    printf '%s|' "$(bash -c 'printf %s "${VERBOSITY-unset}"')"
    VERBOSITY="$VERBOSITY" bash -c 'printf %s "${VERBOSITY-unset}"'
)"
if [[ "$_kt039_child" == "unset|info" ]]; then
    kt_test_pass "explicitly passed VERBOSITY reaches a child"
else
    kt_test_fail "child saw '$_kt039_child' (expected 'unset|info')"
fi
