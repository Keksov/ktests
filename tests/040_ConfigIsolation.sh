#!/bin/bash
# ConfigIsolation (kbool `uses` phase U3, owner decision U41 2026-10-09).
#
# Since U3 every kklass / kcl test loads kbool.sh, which reads the developer's
# configuration: KBOOL_CONFIG, ~/.kbool/config (else $USERPROFILE/.kbool/config),
# /etc/kbool/config (else $ProgramData/kbool/config). A `debug = debug` or a
# bogus `unitpath` there would change what the tests see. So the runner runs
# EVERY test file isolated: KBOOL_CONFIG, KBOOL_HOME, USERPROFILE, ProgramData
# and PROGRAMDATA unset; HOME and kbool's /etc hook (__KK_CFG_ETC) pointed at an
# empty folder of that file alone, removed afterwards. A test may still install
# its own config explicitly; a standalone `bash tests/X.sh` reads the
# environment as it is.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ConfigIsolation" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
TMP="$(cd "$TMP" && pwd)"
FX="$TMP/fx"; DEV="$TMP/dev"; RT="$TMP/rt"
mkdir -p "$FX" "$RT" "$DEV/home/.kbool" "$DEV/up/.kbool" "$DEV/pd/kbool" "$DEV/etc" "$DEV/kb"
for f in "$DEV/home/.kbool/config" "$DEV/up/.kbool/config" "$DEV/pd/kbool/config" "$DEV/etc/config" "$DEV/env.conf"; do
    printf '%s\n' 'debug = debug' "unitpath = $DEV/bogus/units" 'defines = DEVBOX' > "$f"
done
printf '%s\n' 'debug = quiet' 'defines = OWN' > "$TMP/own.conf"
# a developer BASH_ENV: bash runs it at the start of every non-interactive shell
printf '%s\n' "echo \"ran in \${KT_CLEAN_FILE:-a runner shell}\" >> '$TMP/bashenv.log'" > "$TMP/bashenv.sh"
rm -f "$TMP/bashenv.log"
KBOOL_ROOT=""
[[ -f "$KTESTS_LIB_DIR/../kbool.sh" ]] && KBOOL_ROOT="$(cd "$KTESTS_LIB_DIR/.." && pwd)"
FRAMEWORK="$(cd "$KTESTS_LIB_DIR" && pwd)/ktest.sh"

# The probe: a test file that records what it sees (KT040_OUT.<n>) and asserts
# the isolation. With kbool next to ktests it also loads kbool.sh.
for n in 1 2; do
    cat > "$FX/00${n}_Probe.sh" <<EOF
#!/bin/bash
[[ -n "\${_KTEST_SOURCED:-}" ]] || source "$FRAMEWORK"
kt_test_init "Probe$n" "\$(dirname "\$0")"
shopt -s nullglob dotglob
h=("\$HOME"/*)
printf 'home=%s n=%s cfg=%s up=%s pd=%s PD=%s kh=%s etc=%s\n' "\$HOME" "\${#h[@]}" "\${KBOOL_CONFIG-unset}" "\${USERPROFILE-unset}" \\
    "\${ProgramData-unset}" "\${PROGRAMDATA-unset}" "\${KBOOL_HOME-unset}" "\${__KK_CFG_ETC-unset}" > "\$KT040_OUT.$n"
"\$BASH" -c : 2>/dev/null      # a child of the test: no BASH_ENV may reach it (R6)
kt_test_start "isolated environment"
if [[ ! -e \$HOME && \${#h[@]} == 0 && \$HOME != "$DEV/home" && -z \${KBOOL_CONFIG+x}\${USERPROFILE+x}\${ProgramData+x}\${PROGRAMDATA+x}\${KBOOL_HOME+x} \\
      && -n \${__KK_CFG_ETC-} && ! -e \$__KK_CFG_ETC/config ]]; then
    kt_test_pass "isolated"
else
    kt_test_fail "not isolated: \$(<"\$KT040_OUT.$n")"
fi
if [[ -n "$KBOOL_ROOT" ]]; then
    source "$KBOOL_ROOT/kbool.sh"
    kk.config debug; d=\$?; kk.config unitpath; u=\$?; kk.defined DEVBOX; v=\$?
    printf 'debug=%s unitpath=%s devbox=%s verbose=%s\n' "\$d" "\$u" "\$v" "\${VERBOSE_KKLASS-unset}" >> "\$KT040_OUT.$n"
    kt_test_start "kbool sees no developer config"
    if [[ \$d == 1 && \$u == 1 && \$v == 1 && -z \${VERBOSE_KKLASS+x} ]]; then kt_test_pass "none"; else kt_test_fail "\$(tail -1 "\$KT040_OUT.$n")"; fi
fi
EOF
done
# a test that installs its own config explicitly
cat > "$FX/003_Own.sh" <<EOF
#!/bin/bash
[[ -n "\${_KTEST_SOURCED:-}" ]] || source "$FRAMEWORK"
kt_test_init "Own" "\$(dirname "\$0")"
kt_test_start "an explicitly installed config applies"
if [[ -z "$KBOOL_ROOT" ]]; then kt_test_pass "no kbool next to ktests"; else
    export KBOOL_CONFIG="$TMP/own.conf"
    source "$KBOOL_ROOT/kbool.sh"
    kk.config debug; d=\$RESULT; kk.defined OWN; o=\$?; kk.defined DEVBOX; v=\$?
    if [[ \$d == quiet && \$o == 0 && \$v == 1 ]]; then kt_test_pass "own"; else kt_test_fail "debug=\$d own=\$o devbox=\$v"; fi
fi
EOF

# kt040_run MODE FILE... — the nested runner in a subshell with the developer
# environment exported and THIS file's counters untouched; prints T:P:F|failed.
kt040_run() {
    local mode="$1"; shift
    (
        export HOME="$DEV/home" USERPROFILE="$DEV/up" ProgramData="$DEV/pd" PROGRAMDATA="$DEV/pd" \
               KBOOL_CONFIG="$DEV/env.conf" __KK_CFG_ETC="$DEV/etc" KBOOL_HOME="$DEV/kb" \
               TMPDIR="$RT" KT040_OUT="$TMP/seen.$mode" BASH_ENV="$TMP/bashenv.sh"
        TESTS_TOTAL=0; TESTS_PASSED=0; TESTS_FAILED=0; FAILED_TEST_FILES=()
        WORKERS=3 "kt_runner_execute_$mode" "$@" > "$TMP/run.$mode.out" 2>&1
        printf '%s:%s:%s|%s' "$TESTS_TOTAL" "$TESTS_PASSED" "$TESTS_FAILED" "${FAILED_TEST_FILES[*]}"
    )
}
if [[ -n "$KBOOL_ROOT" ]]; then WANT="5:5:0|"; else WANT="3:3:0|"; fi

for mode in sequential threaded; do
    rm -f "$TMP/seen.$mode".*
    got="$(kt040_run "$mode" "$FX/001_Probe.sh" "$FX/002_Probe.sh" "$FX/003_Own.sh")"
    kt_test_start "$mode runner: a developer config (debug = debug, a bogus unitpath, defines) in every lookup place changes nothing; an explicitly installed config still applies [U41]"
    if [[ "$got" == "$WANT" ]]; then
        kt_test_pass "$got"
    else
        kt_test_fail "got '$got' want '$WANT': $(grep -E 'FAIL|not isolated|debug=' "$TMP/run.$mode.out" | head -5 | tr '\n' '|')"
    fi

    kt_test_start "$mode runner: each file gets its OWN HOME under TMPDIR, never created (no process per file, R6), the /etc hook inside it; nothing left in TMPDIR [U41, R6]"
    s1="$(<"$TMP/seen.$mode.1")"; s2="$(<"$TMP/seen.$mode.2")"
    h1="${s1#home=}"; h1="${h1%% *}"; h2="${s2#home=}"; h2="${h2%% *}"
    e1="${s1##*etc=}"; e1="${e1%%$'\n'*}"
    shopt -s nullglob dotglob; left=("$RT"/*); shopt -u nullglob dotglob
    if [[ "$h1" == "$RT"/* && "$h2" == "$RT"/* && "$h1" != "$h2" && "$e1" == "$h1"/* && ! -e "$h1" && ! -e "$h2" && ${#left[@]} == 0 ]]; then
        kt_test_pass "h1=${h1#$RT/} h2=${h2#$RT/}"
    else
        kt_test_fail "h1='$h1' h2='$h2' etc1='$e1' left='${left[*]}'"
    fi
done

kt_test_start "a developer BASH_ENV runs nowhere under the runner (sequential and threaded): not in a worker, not in a test file's shell, not in a child the test starts [kbool uses U4 final review R6, critic_u4 C4]"
if [[ ! -e "$TMP/bashenv.log" ]]; then
    kt_test_pass "never ran"
else
    kt_test_fail "ran $(wc -l < "$TMP/bashenv.log") times: $(sort "$TMP/bashenv.log" | uniq -c | tr '\n' '|')"
fi

kt_test_start "a standalone 'bash tests/X.sh' is not isolated: it sees the developer environment as it is [U41]"
(
    export HOME="$DEV/home" USERPROFILE="$DEV/up" ProgramData="$DEV/pd" KBOOL_CONFIG="$DEV/env.conf" \
           __KK_CFG_ETC="$DEV/etc" KT040_OUT="$TMP/seen.direct"
    unset KBOOL_HOME
    "$BASH" "$FX/001_Probe.sh" >/dev/null 2>&1
)
s="$(<"$TMP/seen.direct.1")"
want="home=$DEV/home n=1 cfg=$DEV/env.conf up=$DEV/up pd=$DEV/pd"
[[ -n "$KBOOL_ROOT" ]] && want2=$'\n''debug=0 unitpath=0 devbox=0 verbose=debug' || want2=""
if [[ "$s" == "$want"* && "$s" == *"$want2" ]]; then kt_test_pass "sees the developer config"; else kt_test_fail "'${s//$'\n'/|}'"; fi

kt_test_start "the run folder (R6): kt_runner_iso_begin sweeps kt_iso.<pid> folders of dead runners (also the old kt_iso.<pid>.<n> shape), keeps a live runner's, creates and exports KT_ISO_ROOT with one empty HOME folder per suite file (one mkdir); a file runs with HOME = KT_ISO_ROOT/<its name>; kt_runner_iso_end removes it [U41, R6]"
RT2="$TMP/rt2"; mkdir -p "$RT2/kt_iso.999999" "$RT2/kt_iso.999998.123" "$RT2/kt_iso.$PPID" "$RT2/other"
# ktests round 5 review R6: a dead runner's folder is swept when it carries this
# bash install's owner marker, or (unmarked, the old shape) once a day old
kt_runner_iso_owner; printf '%s\n' "$REPLY" > "$RT2/kt_iso.999999/.kt_owner"
touch -d '2 days ago' "$RT2/kt_iso.999998.123"
got="$(
    TMPDIR="$RT2"
    kt_runner_iso_begin "$FX/004_Home.sh"
    r="$KT_ISO_ROOT"
    printf '%s\n' 'kt_test_init "Iso3" "$(dirname "$0")"' 'echo "HOME=$HOME" >> "$KT040_OUT"' \
        'kt_test_start "x"; kt_test_pass "x"' > "$FX/004_Home.sh"
    TESTS_TOTAL=0; TESTS_PASSED=0; TESTS_FAILED=0
    KT040_OUT="$TMP/seen.rt2" kt_runner_execute_sequential "$FX/004_Home.sh" >/dev/null 2>&1
    h="$(<"$TMP/seen.rt2")"; h="${h#HOME=}"
    printf 'root=%s exported=%s ' "${r#$RT2/}" "$(bash -c 'echo ${KT_ISO_ROOT:+yes}')"
    [[ -d "$r" && "$h" == "$r/004_Home.sh" && -d "$h" ]] && printf 'home-under-root '
    kt_runner_iso_end
    [[ -e "$r" ]] || printf 'removed '
    cd "$RT2" && ls -d kt_iso.* other 2>/dev/null | tr '\n' ' '
)"
rm -f "$FX/004_Home.sh"
want="root=kt_iso.$$ exported=yes home-under-root removed kt_iso.$PPID other "
if [[ "$got" == "$want" ]]; then kt_test_pass "$got"; else kt_test_fail "got '$got' want '$want'"; fi

kt_test_log "040_ConfigIsolation.sh completed"
