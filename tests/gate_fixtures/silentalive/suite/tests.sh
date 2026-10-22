#!/usr/bin/env bash
# gate fixture "silentalive" (launch L2.7-G, 3c review): a runner that DID
# start but prints nothing for a long while — its only test file waits 18 s
# in silence (3x the KT_GATE_START_GRACE=6 the test gives), then passes. The
# start grace must see its test file's shell and leave the cell alone: PASS.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "gate fixture silentalive" "$@"
