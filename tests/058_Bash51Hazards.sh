#!/usr/bin/env bash
# Bash51Hazards — static check of ktests's non-test code for the shapes that
# mean something else on bash 5.1 (launch L4.3 / L4.5, owner decision OG2:
# minimum bash = 5.1). A hit is reported as `file:line:text`.
#
#   A  a quoted redirect target `>&"$fd"` / `2>&"$fd"` / `<&"$fd"`: bash 5.1's
#      function printer (declare -f, export -f, set -a, and so every class body
#      that kk._fn_text round-trips) prints `>&"$fd"` as `&> "$fd"`, which
#      redirects stdout AND stderr into a FILE named like the descriptor.
#      Fix: `>&$fd` (unquoted) after a ^[0-9]+$ guarantee.
#   C1 `[[ -v a["$k"] ]]` and C2 `unset a["$k"]`: bash 5.1 expands the subscript
#      twice, so a key holding a quote, `]`, `$` is not found / not removed, and
#      the key `@` or `*` empties the whole array. Fix: `${a[$k]+x}` and
#      `unset 'a[$k]'`.
#
# Scanned: every *.sh of the repo outside tests/, docs/, experimental/ (comment
# lines are skipped). Each pattern is also checked against sample lines it
# must match (a typo in a pattern cannot turn the scan into a silent pass).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/.."
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Bash51Hazards" "$SCRIPT_DIR" "$@"

ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PAT_A='[0-9]?[<>]&"'
PAT_C1='\[\[ *(![[:space:]]*)?-v +[A-Za-z_][A-Za-z_0-9]*\[[^]]*\$'
PAT_C2='(^|[^A-Za-z0-9_])unset +(-v +)?[A-Za-z_][A-Za-z_0-9]*\[[^]]*\$'

# b51_scan PATTERN — HITS: "file:line:text" of every code line matching
b51_scan() {
    local line rest
    HITS=""
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        rest=${line#*:}; rest=${rest#*:}
        [[ $rest =~ ^[[:space:]]*# ]] && continue
        HITS+="${line#./}"$'\n'
    done < <(cd "$ROOT" && grep -rnE --include='*.sh' --exclude-dir=tests --exclude-dir=docs \
                 --exclude-dir=experimental --exclude-dir=.git -- "$1" . 2>/dev/null | LC_ALL=C sort)
}

# b51_case NAME PATTERN SAMPLE... — the pattern matches every SAMPLE and the repo has no hit
b51_case() {
    local name=$1 pat=$2 s; shift 2
    for s in "$@"; do
        if ! printf '%s\n' "$s" | grep -qE -- "$pat"; then
            kt_test_fail "$name: the pattern does not match its own sample [$s]"; return
        fi
    done
    b51_scan "$pat"
    if [[ -z $HITS ]]; then kt_test_pass "$name: no hit"; else kt_test_fail "$name:"$'\n'"${HITS%$'\n'}"; fi
}

kt_test_start "A: no quoted redirect target (>&\"\$fd\", 2>&\"\$fd\", <&\"\$fd\") in non-test code (bash 5.1 declare -f prints >&\"W\" as &> W)"
b51_case A "$PAT_A" 'printf x >&"$fd"' 'cmd 2>&"$fd"' 'cmd <&"$fd"' '{ x; } 1>&"${fd}"'

kt_test_start "C1: no [[ -v array[\"\$k\"] ]] in non-test code (bash 5.1 expands the subscript twice; use \${a[\$k]+x})"
b51_case C1 "$PAT_C1" '[[ -v a["$k"] ]]' '[[ ! -v seen["$f"] ]]' '[[ -v  A[$k] ]]'

kt_test_start "C2: no unquoted unset array[\"\$k\"] in non-test code (bash 5.1 expands the subscript twice; use unset 'a[\$k]')"
b51_case C2 "$PAT_C2" 'unset a["$k"]' '    unset -v A[$k]' 'x; unset __M["$key"]'

kt_test_log "058_Bash51Hazards.sh completed"
