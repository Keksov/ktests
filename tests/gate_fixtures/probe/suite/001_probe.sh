# the hermetic cell (GATE_PLAN 4.2) as a test file sees it (the runner's own
# per-file isolation on top: HOME and __KK_CFG_ETC are its kt_iso dir, under
# the cell's TMPDIR; USERPROFILE/ProgramData unset): every check is a test
source "$KTEST_SOURCE_PATH"
kt_test_init "GfxProbe" "$KT_TESTS_DIR" "$@"
gfx_check() { kt_test_start "$1"; if eval "$2"; then kt_test_pass "$1"; else kt_test_fail "$1: [$2] is false"; fi; }
gfx_check "HOME is under the cell, no .kbool" '[[ "$HOME" == */cells/[0-9][0-9][0-9]/* && ! -e "$HOME/.kbool" ]]'
gfx_check "TMPDIR is the cell's" '[[ "$TMPDIR" == */cells/[0-9][0-9][0-9]/tmp* ]]'
gfx_check "the config etc dir is under the cell" '[[ "$__KK_CFG_ETC" == */cells/[0-9][0-9][0-9]/* ]]'
gfx_check "USERPROFILE / ProgramData: unset or the cell's" '[[ ( -z "${USERPROFILE+x}" || "$USERPROFILE" == */cells/[0-9][0-9][0-9]/* ) && ( -z "${ProgramData+x}" || "$ProgramData" == */cells/[0-9][0-9][0-9]/* ) ]]'
gfx_check "KKLASS_CKK_DIR is the cell's" '[[ "$KKLASS_CKK_DIR" == */cells/[0-9][0-9][0-9]/ckk ]]'
gfx_check "no KBOOL_HOME / KBOOL_CONFIG" '[[ -z "${KBOOL_HOME+x}" && -z "${KBOOL_CONFIG+x}" ]]'
gfx_check "no caller function" '! declare -F gfx_caller_fn >/dev/null && ! declare -F kk.uses >/dev/null'
gfx_check "no BASH_ENV / CDPATH / GLOBIGNORE / VERBOSE_KKLASS" '[[ -z "${BASH_ENV:-}${CDPATH+x}${GLOBIGNORE+x}${VERBOSE_KKLASS+x}" ]]'
gfx_check "no caller variable, not the caller's VERBOSITY" '[[ -z "${GFX_CALLER_VAR+x}" && "${VERBOSITY:-}" != info ]]'
