#!/usr/bin/env bash
# gate fixture "probe" (gate G2): the hermetic cell seen from inside. This
# wrapper dumps the CELL's environment (what the gate gave it, before the
# ktests runner isolates each test file further) next to itself — the fixture
# root is a per-test copy — for 051 to compare with what its caller had; the
# test file checks what a test file sees.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# the open fds (before any redirection; the glob's own dir fd, closed by the
# time it is looked at, is skipped)
__gfx_fds=""; for __gfx_f in /proc/$$/fd/*; do [[ -e "$__gfx_f" ]] && __gfx_fds+="${__gfx_f##*/} "; done
{ env; echo "PWD_AT_START=$PWD"; echo "FDS=${__gfx_fds% }"; declare -Fx; } > "$SCRIPT_DIR/.gfx_cell_env.$$" 2>&1
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "gate fixture probe" "$@"
