#!/usr/bin/env bash
# gate fixture "leak" (gate G2): the wrapper leaves a detached `sleep` behind
# (outside ktests.sh's own run group, so only the gate's stray check sees it);
# its argv[0] carries the fixture root (a nonce per test run). Bounded: 30 s.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! ( exec -a gfx-probe sleep 0 ) </dev/null >/dev/null 2>&1; then
    # a multi-call binary (busybox; Alpine's coreutils) runs the applet its
    # argv[0] names: a renamed `sleep` does not run — a bash waiting 30 s on a
    # pty instead (launch L2.1)
    ( (exec -a "gfx-leak:$SCRIPT_DIR" "$BASH" -c 'exec 3<>/dev/ptmx; read -t 30 -u 3 _') </dev/null >/dev/null 2>&1 & )
else
    ( (exec -a "gfx-leak:$SCRIPT_DIR" sleep 30) </dev/null >/dev/null 2>&1 & )
fi
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "gate fixture leak" "$@"
