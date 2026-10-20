#!/bin/bash
# gate fixture "leak" (gate G2): the wrapper leaves a detached `sleep` behind
# (outside ktests.sh's own run group, so only the gate's stray check sees it);
# its argv[0] carries the fixture root (a nonce per test run). Bounded: 30 s.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
( (exec -a "gfx-leak:$SCRIPT_DIR" sleep 30) </dev/null >/dev/null 2>&1 & )
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "gate fixture leak" "$@"
