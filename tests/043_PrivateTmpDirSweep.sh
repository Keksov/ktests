#!/bin/bash
# PrivateTmpDirSweep (ktests round 5, T11 / DT11, 2026-10-16).
#
# Eight kcl tstringhelper files made a private `<tests>/.tmp/<file name>` with
# `mkdir -p` and never removed it — a new tree entry on every run that the
# runner's leftover sweep (`.tmp/*.<file>`, the kt_test_init fixture shape) did
# not match. Those files now use kt_fixture_tmpdir_create; the runner also
# removes a still-present `.tmp/<file name>` of the file it just ran and says
# so — a dir named after ANOTHER file is not touched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "PrivateTmpDirSweep" "$SCRIPT_DIR" "$@"

TMP="$(kt_fixture_tmpdir)"
FX="$TMP/fx"
mkdir -p "$FX"

printf '%s\n' 'kt_test_init "Priv" "$(dirname "$0")"' \
    'mkdir -p "$(dirname "$0")/.tmp/leaky/sub"; : > "$(dirname "$0")/.tmp/leaky/sub/f"' \
    'kt_test_start "one"; kt_test_pass "one"' > "$FX/leaky.sh"
printf '%s\n' 'kt_test_init "Priv" "$(dirname "$0")"' \
    'd="$(dirname "$0")/.tmp/tidy"; mkdir -p "$d"; rm -rf -- "$d"' \
    'kt_test_start "one"; kt_test_pass "one"' > "$FX/tidy.sh"

# kt043_run FILE — the single-file runner with THIS file's counters saved
kt043_run() {
    local st=$TESTS_TOTAL sp=$TESTS_PASSED sf=$TESTS_FAILED
    kt_runner_execute_single_test "$1" >/dev/null 2>&1
    R_COUNTS="$count_total:$count_passed:$count_failed"
    TESTS_TOTAL=$st; TESTS_PASSED=$sp; TESTS_FAILED=$sf
}

kt_test_start "a left .tmp/<file name> is removed by the runner with a WARN; the verdict is unchanged [T11]"
mkdir -p "$FX/.tmp/other"
kt043_run "$FX/leaky.sh"
wline="$(printf '%s\n' "$output_content" | grep -m1 '^\[WARN\]')"
if [[ ! -e "$FX/.tmp/leaky" && -d "$FX/.tmp/other" && "$R_COUNTS" == "1:1:0" \
      && "$wline" == "[WARN] leaky.sh: private dir .tmp/leaky left behind - removed by the runner"* ]]; then
    kt_test_pass "$R_COUNTS; $wline"
else
    kt_test_fail "leaky left=$([[ -e "$FX/.tmp/leaky" ]] && echo yes || echo no) other=$([[ -d "$FX/.tmp/other" ]] && echo kept || echo GONE) counts=$R_COUNTS warn=[$wline]"
fi

kt_test_start "a file that removes its own private dir gets no WARN [T11]"
kt043_run "$FX/tidy.sh"
if [[ "$R_COUNTS" == "1:1:0" && "$output_content" != *"[WARN]"* ]]; then
    kt_test_pass "$R_COUNTS, no WARN"
else
    kt_test_fail "counts=$R_COUNTS out=[${output_content//$'\n'/ | }]"
fi
rm -rf -- "$FX/.tmp"

# review R2: a file named `.sh` (or `..sh`) has an empty (or `.`) name — the
# sweep must not turn into `rm -rf <tests>/.tmp/` and take every other dir
FX2="$TMP/fx2"
mkdir -p "$FX2/.tmp/Other.001_x" "$FX2/.tmp/keep"
: > "$FX2/.tmp/keep/f"
for n in .sh ..sh; do
    printf '%s\n' 'kt_test_start "one"; kt_test_pass "one"' > "$FX2/$n"
done
kt_test_start "files named .sh and ..sh: the private-dir sweep removes nothing else and prints no WARN [R2]"
kt043_run "$FX2/.sh";  o1="$output_content"
kt043_run "$FX2/..sh"; o2="$output_content"
if [[ -d "$FX2/.tmp/Other.001_x" && -f "$FX2/.tmp/keep/f" && "$o1$o2" != *"private dir"* ]]; then
    kt_test_pass "other dirs kept, no WARN"
else
    kt_test_fail "Other=$([[ -d "$FX2/.tmp/Other.001_x" ]] && echo kept || echo GONE) keep=$([[ -f "$FX2/.tmp/keep/f" ]] && echo kept || echo GONE) out=[${o1//$'\n'/ | } || ${o2//$'\n'/ | }]"
fi
rm -rf -- "$FX2"

kt_test_log "043_PrivateTmpDirSweep.sh completed"
