#!/bin/bash
# fixture "tcenv" (test 055, tools/timing_check.sh --bash): what the suite
# wrapper sees when timing_check runs it in its --bash child — the caller's
# allowlisted / --pass-env variables, path values in the C:/ spelling
# (cygpath -m: the same folder in both runtimes), whether an exported
# function or a non-allowlisted variable arrived, the bash running it, the
# child's private spec dir under TMPDIR — dumped next to itself (the fixture
# root is a per-test copy). With TC055_HOLD set it marks HOLD.started and
# waits (up to 60 s) for the file HOLD before the suite runs: a run in flight
# for the signal cases.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
{
    printf 'BASH_V=%s\n' "${BASH_VERSION%%(*}"
    printf 'VAR=%s\n' "${TC055_VAR-<unset>}"
    printf 'KTVAR=%s\n' "${KT_TC055-<unset>}"
    printf 'SECRET=%s\n' "${TC055_SECRET_TOKEN-<unset>}"
    printf 'PLAIN=%s\n' "${TC055_PLAIN-<unset>}"
    printf 'LANG=%s\n' "${LANG-<unset>}"
    printf 'P_M=%s\n' "$(cygpath -m "${KT_TC055_P:-/nonexistent-unset}" 2>/dev/null)"
    printf 'TMPDIR_M=%s\n' "$(cygpath -m "${TMPDIR:-/nonexistent-unset}" 2>/dev/null)"
    printf 'HOME_M=%s\n' "$(cygpath -m "${HOME:-/nonexistent-unset}" 2>/dev/null)"
    declare -F tc055_fn >/dev/null && printf 'FN=%s\n' "$(tc055_fn)"
    __gfx_rx=""; for __gfx_d in "${TMPDIR:-/nonexistent}"/timing_check.*; do [[ -d "$__gfx_d" ]] && __gfx_rx+="${__gfx_d##*/} "; done
    printf 'RXDIRS=%s\n' "${__gfx_rx% }"
} > "$SCRIPT_DIR/.tc_env.$$" 2>&1
if [[ -n "${TC055_HOLD:-}" ]]; then
    : > "$TC055_HOLD.started"
    for (( __gfx_i = 0; __gfx_i < 600; __gfx_i++ )); do [[ -e "$TC055_HOLD" ]] && break; sleep 0.1; done
    : > "$TC055_HOLD.released"
fi
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "fixture tcenv" "$@"
