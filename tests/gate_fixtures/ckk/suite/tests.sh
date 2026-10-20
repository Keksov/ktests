#!/bin/bash
# gate fixture "ckk" (ktests/tests/gate_fixtures, gate G3) — a suite wrapper as
# every kbool suite has one; mkroot.sh copies this dir to ROOT/ckk/tests/ (or
# ROOT/ID/tests: the ktests library is looked up upwards)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "gate fixture ckk" "$@"
