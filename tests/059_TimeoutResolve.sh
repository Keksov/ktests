#!/usr/bin/env bash
# TimeoutResolve — ktest.sh resolves timeout(1) BY NAME at source time (launch
# L5.4-9, owner OG11 = c): KT_TIMEOUT = `timeout` where PATH has it, else
# `gtimeout` (macOS brew coreutils without gnubin on PATH), else "" with a
# reason in KT_TIMEOUT_WHY; kt_need_timeout is rc 0 / 1 accordingly. The test
# seam KT_TIMEOUT_NAMES names the candidates (`none`: nothing). An inherited
# KT_TIMEOUT never counts.
#
# Each case sources ktest.sh in a fresh bash with KT_TIMEOUT_NAMES set
# explicitly (or removed), so a caller's own knob never leaks into a case.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "TimeoutResolve" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
LIB="$(cd "$KTESTS_LIB_DIR" && pwd)"

# kt059_probe [NAME=VALUE...] — REPLY = "T=[KT_TIMEOUT] N=[kt_need_timeout rc] W=[KT_TIMEOUT_WHY]"
# of a fresh bash that sources ktest.sh with KT_TIMEOUT_NAMES removed, then NAME=VALUE set
kt059_probe() {
    REPLY="$(env -u KT_TIMEOUT_NAMES -u KTESTS_LIB_DIR "$@" bash -c \
        'source "$1/ktest.sh"; kt_need_timeout; printf "T=[%s] N=[%s] W=[%s]" "$KT_TIMEOUT" "$?" "$KT_TIMEOUT_WHY"' _ "$LIB" 2>&1 </dev/null)"
}

kt_test_start "default: KT_TIMEOUT is the bare name 'timeout' where PATH has a timeout (no path), kt_need_timeout rc 0, no reason"
if [[ -z "$(type -P timeout)" ]]; then
    kt_test_pass "SKIP: no timeout(1) on PATH here (the default is checked where it exists)"
else
    kt059_probe
    if [[ "$REPLY" == "T=[timeout] N=[0] W=[]" ]]; then kt_test_pass "$REPLY"; else kt_test_fail "[$REPLY] (want T=[timeout] N=[0] W=[])"; fi
fi

kt_test_start "KT_TIMEOUT_NAMES='kt-no-such gtimeout' with a gtimeout on PATH: KT_TIMEOUT = gtimeout, and \"\$KT_TIMEOUT\" -k 5 1 sleep 5 is rc 124"
if [[ -z "$(type -P timeout)" ]]; then
    kt_test_pass "SKIP: no timeout(1) on PATH for the gtimeout stub to run"
else
    # a stub script, not a copy or a link: busybox dispatches on argv[0]
    mkdir -p "$TMP/gbin"
    printf '%s\n' '#!/bin/sh' 'exec timeout "$@"' > "$TMP/gbin/gtimeout"
    chmod +x "$TMP/gbin/gtimeout"
    t0=$SECONDS
    o="$(env -u KT_TIMEOUT_NAMES -u KTESTS_LIB_DIR PATH="$TMP/gbin:$PATH" KT_TIMEOUT_NAMES="kt-no-such gtimeout" bash -c \
        'source "$1/ktest.sh"; printf "T=[%s] " "$KT_TIMEOUT"; "$KT_TIMEOUT" -k 5 1 sleep 5; printf "rc=%s" "$?"' _ "$LIB" 2>&1 </dev/null)"
    dt=$(( SECONDS - t0 ))
    if [[ "$o" == "T=[gtimeout] rc=124" ]] && (( dt < 5 )); then kt_test_pass "$o (${dt}s)"; else kt_test_fail "[$o] ${dt}s (want T=[gtimeout] rc=124 in < 5 s)"; fi
fi

kt_test_start "KT_TIMEOUT_NAMES=none (and an absent name): KT_TIMEOUT empty, kt_need_timeout rc 1, a reason in KT_TIMEOUT_WHY"
kt059_probe KT_TIMEOUT_NAMES=none; r1="$REPLY"
kt059_probe KT_TIMEOUT_NAMES=kt-no-such-timeout; r2="$REPLY"
if [[ "$r1" == "T=[] N=[1] W=["?*"]" && "$r2" == "$r1" ]]; then
    kt_test_pass "$r1"
else
    kt_test_fail "none: [$r1] absent name: [$r2] (want T=[] N=[1] W=[<a reason>], both the same)"
fi

kt_test_start "an inherited KT_TIMEOUT=/bogus (exported by the caller) is ignored: recomputed at source time"
kt059_probe; want="$REPLY"
kt059_probe KT_TIMEOUT=/bogus
if [[ "$REPLY" == "$want" && "$REPLY" != *bogus* ]]; then
    kt_test_pass "$REPLY"
else
    kt_test_fail "[$REPLY] (want [$want], the caller's /bogus dropped)"
fi

kt_test_log "059_TimeoutResolve.sh completed"
