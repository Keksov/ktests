#!/bin/bash
# LocaleContract — the test corpus runs under UTF-8 (kcl decision D6,
# review 2026-09-06, finding X-LOCALE: TSH-04 / tregex T3).
#
# LANG and LC_ALL are empty in this environment, so before D6 every sweep ran in
# the C locale. There `${#s}` counts BYTES, `${s,,}` CORRUPTS multi-byte text on
# bash 5.2 (`ÄÖ` came back as two replacement bytes) and `.` in an ERE does not
# match a multi-byte character — while tstringhelper's and tregex's docs promise
# character semantics. ktest.sh now pins LC_ALL/LANG=C.UTF-8, so this file is
# the contract: if the pin is ever removed, these checks go red instead of the
# unit tests silently changing meaning.
#
# This file is UTF-8 encoded; `ÄÖ` below is 2 characters / 4 bytes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "LocaleContract" "$SCRIPT_DIR" "$@"

# ---------------------------------------------------------------------------
kt_test_start "LC_ALL is pinned to a UTF-8 locale [D6]"
if [[ "${LC_ALL:-}" == *[Uu][Tt][Ff]* ]]; then
    kt_test_pass "LC_ALL=$LC_ALL"
else
    kt_test_fail "LC_ALL='${LC_ALL:-<empty>}' (expected a UTF-8 locale)"
fi

kt_test_start "LANG is pinned too, so unsetting LC_ALL does not fall back to C [D6]"
if [[ "${LANG:-}" == *[Uu][Tt][Ff]* ]]; then
    kt_test_pass "LANG=$LANG"
else
    kt_test_fail "LANG='${LANG:-<empty>}' (expected a UTF-8 locale)"
fi

# ---------------------------------------------------------------------------
kt_test_start "\${#s} counts characters, not bytes [X-LOCALE]"
s="ÄÖ"
if [[ "${#s}" -eq 2 ]]; then
    kt_test_pass "len=2"
else
    kt_test_fail "len=${#s} (byte semantics: the C locale reports 4)"
fi

kt_test_start "\${s,,} / \${s^^} do not corrupt multi-byte text [TSH-04]"
s="ÄÖ"
lower="${s,,}"
upper="${lower^^}"
if [[ "$lower" == "äö" && "$upper" == "ÄÖ" ]]; then
    kt_test_pass "ÄÖ -> äö -> ÄÖ"
else
    kt_test_fail "lower='$lower' (want 'äö'), upper='$upper' (want 'ÄÖ')"
fi

kt_test_start "a substring index counts characters [X-LOCALE]"
s="äbc"
if [[ "${s:1:2}" == "bc" ]]; then
    kt_test_pass "\${s:1:2}='bc'"
else
    kt_test_fail "\${s:1:2}='${s:1:2}' (want 'bc')"
fi

kt_test_start "'.' in an ERE matches one multi-byte character [tregex T3]"
if [[ "äb" =~ ^.b$ ]]; then
    kt_test_pass "matched"
else
    kt_test_fail "'.' did not match a multi-byte character"
fi

# ---------------------------------------------------------------------------
kt_test_start "the locale is EXPORTED, so child processes inherit it [D6]"
child_len="$(bash -c 's="ÄÖ"; printf "%s" "${#s}"')"
if [[ "$child_len" == "2" ]]; then
    kt_test_pass "child reports len=2"
else
    kt_test_fail "child reports len=$child_len (locale not exported?)"
fi

kt_test_start "non-ASCII round-trips through a command substitution [D6]"
got="$(printf '%s' 'привет ÄÖ ✓')"
if [[ "$got" == 'привет ÄÖ ✓' ]]; then
    kt_test_pass "round-tripped"
else
    kt_test_fail "got '$got'"
fi

kt_test_log "030_LocaleContract.sh completed"
