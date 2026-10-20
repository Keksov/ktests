#!/usr/bin/env bash
# mkroot.sh ROOT NAME... — build a fake kbool root for the gate tests (050-052):
# ROOT/ktests = a copy of this ktests' library (*.sh, tools/*.sh), and for each
# NAME ROOT/NAME/tests = a copy of gate_fixtures/NAME/suite. The fixtures are
# stored as NAME/suite (never NAME/tests/tests.sh) so the master sweep's
# discovery (DIR/tests/tests.sh under the kbool root) never finds them.
# A name may be given as NAME=ID to place the fixture at ROOT/ID/tests (ID may
# hold slashes: a/x). No fork per file beyond mkdir/cp.
set -e
__gfx_src="${BASH_SOURCE[0]}"
__gfx_dir="${__gfx_src%/*}"; [[ "$__gfx_dir" == "$__gfx_src" ]] && __gfx_dir=.
__gfx_dir="$(cd "$__gfx_dir" && pwd)"
__gfx_lib="$(cd "$__gfx_dir/../.." && pwd)"
root="$1"; shift
mkdir -p "$root/ktests/tools"
cp "$__gfx_lib"/*.sh "$root/ktests/"
cp "$__gfx_lib"/tools/*.sh "$root/ktests/tools/"
for n in "$@"; do
    name="${n%%=*}"; id="${n#*=}"
    mkdir -p "$root/$id/tests"
    cp "$__gfx_dir/$name/suite/"* "$root/$id/tests/"
done
