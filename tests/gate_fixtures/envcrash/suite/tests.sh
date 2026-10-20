#!/bin/bash
# gate fixture "envcrash" (gate G2 review R5): the FIRST run (no marker) is a
# runner that dies of a fork failure — cygwin's raw line, then gone without a
# summary: CRASH with the signature = ENV, re-run once; the second run passes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -e "$SCRIPT_DIR/.gfx_envcrash_attempted" ]]; then
    : > "$SCRIPT_DIR/.gfx_envcrash_attempted"
    echo "      0 [main] bash 4242 dofork: child -1 - CreateProcessW failed for 'C:\bin\bash.exe', errno 11" >&2
    kill -KILL $$
fi
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "gate fixture envcrash" "$@"
