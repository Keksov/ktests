#!/usr/bin/env bash
# ktest_fixtures.sh - Fixture and resource management for tests
# Provides temporary directory management, setup/teardown, and cleanup coordination
#
# Requires: ktest_core.sh to be sourced first

# Prevent multiple sourcing
if [[ -n "${_KTEST_FIXTURES_SOURCED:-}" ]]; then
    return
fi
declare -g _KTEST_FIXTURES_SOURCED=1

# Ensure core framework is available
if [[ -z "${_KTEST_CORE_SOURCED:-}" ]]; then
    echo "ERROR: ktest_core.sh must be sourced before ktest_fixtures.sh" >&2
    return 1
fi

# ============================================================================
# Global State
# ============================================================================

# Test ID for identifying test runs
declare -g _KT_ID=""

# Test-specific temporary directory
declare -g _KT_TMPDIR=""

# Base temporary directory
declare -g _KT_TMPBASE=""

# Array of registered cleanup functions
declare -ga _KT_CLEANUP_HANDLERS=()

# Array of created temporary directories
declare -ga _KT_CREATED_TMPDIRS=()

# Monotonic sequence so each backup gets a uniquely-named restore handler
# (a PID-only name collided when two files were backed up in one process).
declare -gi _KT_BACKUP_SEQ=0

# ============================================================================
# Temp Directory Management
# ============================================================================

# Initialize test-specific temporary directory
# Usage: kt_fixture_init_tmpdir "test_id" "/path/to/tests"
# Sets: _KT_TMPDIR
kt_fixture_init_tmpdir() {
    local test_id="${1:-default}"
    local base_dir="${2:-./.tmp}"

    # An ABSOLUTE base (ktests round 5, T8/DT8): a standalone `bash tests/X.sh`
    # passes a relative `$(dirname "$0")`; the fixture paths then depended on
    # the cwd of whoever used them (MSYS `ln -s` resolves a relative target from
    # the link's folder). No fork: $PWD is the cwd of this call — unless it is
    # unset or not absolute (review R8), then `pwd` (a fork only then). Drive
    # paths `C:/…` and `C:\…` are absolute; a drive-relative `c:x` is a plain
    # relative name to MSYS (it creates ./c:x), so it is joined like one.
    if [[ "$base_dir" != /* && "$base_dir" != [A-Za-z]:/* && "$base_dir" != [A-Za-z]:"\\"* ]]; then
        local __kt_pwd="${PWD:-}"
        [[ "$__kt_pwd" == /* ]] || __kt_pwd="$(pwd)"
        base_dir="${base_dir#./}"
        base_dir="${__kt_pwd%/}/$base_dir"
    fi

    _KT_ID="$test_id"
    _KT_TMPBASE="$base_dir"
    
    # Ensure base directory exists
    [[ ! -d "$_KT_TMPBASE" ]] && mkdir -p "$_KT_TMPBASE"
    
    # Create the test-specific directory: PER RUN, `<test_id>.<pid>` (ktests
    # round 6, S2): two concurrent runs of one file — two standalone runs, two
    # runs of one suite — each get their own; a fixed `<test_id>` was wiped by
    # the other run's setup and by the other runner's leftover sweep. A second
    # setup with the same id in THIS process keeps its dir.
    local __kt_d __kt_r __kt_n=0
    for __kt_d in "${_KT_CREATED_TMPDIRS[@]}"; do
        # `<id>.$$` or `<id>.$$.<n>` exactly
        [[ "$__kt_d" == "$_KT_TMPBASE/$test_id.$$"* ]] || continue
        __kt_r="${__kt_d#"$_KT_TMPBASE/$test_id.$$"}"
        [[ -z "$__kt_r" || ( "$__kt_r" == .[0-9]* && "${__kt_r#.}" != *[!0-9]* ) ]] || continue
        _KT_TMPDIR="$__kt_d"
        [[ -d "$_KT_TMPDIR" ]] || mkdir -p "$_KT_TMPDIR"
        if [[ ! -f "$_KT_TMPDIR.owner" ]]; then
            kt_fixture_owner_mark
            printf '%s\n' "$REPLY" > "$_KT_TMPDIR.owner" 2>/dev/null
        fi
        kt_test_debug "Reusing test temp directory: $_KT_TMPDIR"
        return 0
    done
    # Stale dirs of this id (round 3, T5/DT5: a run whose teardown never ran —
    # its own `trap … EXIT`, a killed shell) are wiped here with their owner
    # mark, so the leak stays bounded: see kt_fixture_stale_dir. The legacy
    # fixed name too, and a mark whose dir is gone (the dir is made first).
    [[ -d "$_KT_TMPBASE/$test_id" && ! -L "$_KT_TMPBASE/$test_id" ]] && rm -rf -- "$_KT_TMPBASE/$test_id"
    for __kt_d in "$_KT_TMPBASE/$test_id."[0-9]*; do
        if [[ "$__kt_d" == *.owner ]]; then
            [[ -f "$__kt_d" && ! -e "${__kt_d%.owner}" ]] && rm -f -- "$__kt_d"
            continue
        fi
        kt_fixture_stale_dir "$__kt_d" "$_KT_TMPBASE/$test_id." && rm -rf -- "$__kt_d" "$__kt_d.owner"
    done
    # `<id>.<pid>`; taken (the other runtime's live process with this pid:
    # its pids are not ours) -> `<id>.<pid>.<n>`. The owner mark is a SIBLING
    # file `<dir>.owner` (critic r6b): the fixture dir itself stays empty.
    _KT_TMPDIR="$_KT_TMPBASE/$test_id.$$"
    while [[ -e "$_KT_TMPDIR" || -e "$_KT_TMPDIR.owner" ]] && (( __kt_n < 50 )); do
        _KT_TMPDIR="$_KT_TMPBASE/$test_id.$$.$(( ++__kt_n ))"
    done
    mkdir -p "$_KT_TMPDIR"
    kt_fixture_owner_mark
    printf '%s\n' "$REPLY" > "$_KT_TMPDIR.owner" 2>/dev/null

    _KT_CREATED_TMPDIRS+=("$_KT_TMPDIR")
    
    kt_test_debug "Initialized test temp directory: $_KT_TMPDIR"
    
    return 0
}

# kt_fixture_owner_mark — REPLY = the owner mark a fixture dir's sibling
# `<dir>.owner` holds: the source of the `/` mount, i.e. the pid namespace (C:/bin/Git vs
# C:/bin/msys64 — two cygwin runtimes whose pids cannot see each other; the
# same mark as kt_runner_iso_owner). "none" without /proc/mounts. No fork;
# read once per process.
declare -g _KT_FX_OWNER_MARK=""
kt_fixture_owner_mark() {
    local a b c
    if [[ -z "$_KT_FX_OWNER_MARK" ]]; then
        if [[ -r /proc/mounts ]]; then
            while read -r a b c; do
                [[ "$b" == / ]] && { _KT_FX_OWNER_MARK="$a"; break; }
            done < /proc/mounts
        fi
        _KT_FX_OWNER_MARK="${_KT_FX_OWNER_MARK:-none}"
    fi
    REPLY="$_KT_FX_OWNER_MARK"
}

# kt_fixture_stale_dir DIR PREFIX — rc 0 when DIR (= PREFIX<pid>[.<n>], a
# per-run fixture dir) is STALE: its owner — the pid in its name — is gone.
# Same rules as the kt_iso dead-pid sweep: the owner is looked up with
# `kill -0` only when DIR's mark (the sibling `DIR.owner`; an inside
# `DIR/.kt_owner` of the first round-6 draft is read too) names THIS runtime;
# a dir of the other runtime (its live run is invisible to `kill -0` here) or
# one without a mark (legacy, or its mark not written yet) is stale only once
# it is older than a day (one `find -mmin`, only for such a dir). rc 1 for
# anything else (not a dir, a symlink, no pid in the name, a live owner). The
# caller removes DIR and DIR.owner together.
kt_fixture_stale_dir() {
    local d="$1" pid mark=""
    [[ -d "$d" && ! -L "$d" ]] || return 1
    pid="${d#"$2"}"
    [[ "$pid" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
    pid="${pid%%.*}"
    if [[ -f "$d.owner" ]]; then
        { IFS= read -r mark < "$d.owner"; } 2>/dev/null
    elif [[ -f "$d/.kt_owner" ]]; then
        { IFS= read -r mark < "$d/.kt_owner"; } 2>/dev/null
    fi
    kt_fixture_owner_mark
    if [[ "$mark" == "$REPLY" ]]; then
        kill -0 "$pid" 2>/dev/null && return 1
        return 0
    fi
    [[ -n "$(command find "$d" -maxdepth 0 -mmin +1440 2>/dev/null)" ]]
}

# Get the test temporary directory
# Usage: tmpdir=$(kt_fixture_tmpdir)
kt_fixture_tmpdir() {
    if [[ -z "$_KT_TMPDIR" ]]; then
        kt_test_warning "Test temp directory not initialized. Run kt_fixture_init_tmpdir first."
        return 1
    fi
    echo "$_KT_TMPDIR"
}

# Create a temporary file within the test directory
# Usage: file=$(kt_fixture_tmpfile "prefix")
kt_fixture_tmpfile() {
    local prefix="${1:-test}"
    
    if [[ -z "$_KT_TMPDIR" ]]; then
        kt_test_error "Test temp directory not initialized"
        return 1
    fi
    
    local tmpfile
    tmpfile=$(mktemp "$_KT_TMPDIR/${prefix}.XXXXXX")
    echo "$tmpfile"
    return 0
}

# Create a temporary directory within the test directory
# Usage: tmpdir=$(kt_fixture_tmpdir_create "subdir_name")
kt_fixture_tmpdir_create() {
    local name="${1:-tmpdir}"
    
    if [[ -z "$_KT_TMPDIR" ]]; then
        kt_test_error "Test temp directory not initialized"
        return 1
    fi
    
    local tmpdir="$_KT_TMPDIR/$name"
    mkdir -p "$tmpdir"
    echo "$tmpdir"
    return 0
}

# ============================================================================
# Setup and Teardown
# ============================================================================

# Setup test fixtures
# Usage: kt_fixture_setup "test_id"
kt_fixture_setup() {
    local test_id="${1:-default}"
    local script_dir="${2:-.}"
    
    # Initialize temp directory
    kt_fixture_init_tmpdir "$test_id" "$script_dir/.tmp"
    
    kt_test_debug "Fixture setup complete for test: $test_id"
}

# Teardown test fixtures and cleanup resources
# Usage: kt_fixture_teardown
kt_fixture_teardown() {
    local i
    
    # Call registered cleanup handlers in reverse order
    for ((i = ${#_KT_CLEANUP_HANDLERS[@]} - 1; i >= 0; i--)); do
        local handler="${_KT_CLEANUP_HANDLERS[$i]}"
        kt_test_debug "Executing cleanup handler: $handler"
        if declare -F "$handler" >/dev/null 2>&1; then
            "$handler" 2>/dev/null || true
        fi
    done
    
    # Clean up temp directories. A removal that fails is retried (round 6,
    # 046 under a full-load sweep): a NATIVE Windows handle opened without
    # FILE_SHARE_DELETE — a virus scanner or the search indexer reading a file
    # just written — makes `rm -rf` fail with "Device or resource busy" for as
    # long as it is held; the dir then outlived this shell and the runner's
    # sweep removed it with a misleading "own EXIT trap?" WARN. Up to 10 more
    # tries 0.3 s apart (fork-free naps on a pty; only when a try failed).
    local __kt_try __kt_w=""
    for tmpdir in "${_KT_CREATED_TMPDIRS[@]}"; do
        if [[ -d "$tmpdir" || -e "$tmpdir.owner" ]]; then
            rm -rf "$tmpdir" "$tmpdir.owner" 2>/dev/null || true
            for (( __kt_try = 0; __kt_try < 10; __kt_try++ )); do
                [[ -e "$tmpdir" || -e "$tmpdir.owner" ]] || break
                if [[ -z "$__kt_w" ]]; then
                    { exec {__kt_w}<>/dev/ptmx; } 2>/dev/null || __kt_w=x
                fi
                if [[ "$__kt_w" == x ]]; then
                    sleep 0.3 || :
                else
                    read -t 0.3 -u "$__kt_w" _ 2>/dev/null || :   # set -e safe
                fi
                rm -rf "$tmpdir" "$tmpdir.owner" 2>/dev/null || true
            done
            kt_test_debug "Cleaned up temp directory: $tmpdir"
        fi
    done
    [[ -n "$__kt_w" && "$__kt_w" != x ]] && exec {__kt_w}>&-
    
    # Clear handlers and directories
    _KT_CLEANUP_HANDLERS=()
    _KT_CREATED_TMPDIRS=()
    _KT_TMPDIR=""
    _KT_ID=""
}

# ============================================================================
# Cleanup Registration
# ============================================================================

# Register a cleanup handler function
# Handlers are called in reverse order during teardown
# Usage: kt_fixture_cleanup_register "cleanup_function_name"
kt_fixture_cleanup_register() {
    local handler="$1"
    
    if [[ -z "$handler" ]]; then
        kt_test_error "Cleanup handler name required"
        return 1
    fi
    
    _KT_CLEANUP_HANDLERS+=("$handler")
    kt_test_debug "Registered cleanup handler: $handler"
    return 0
}

# Unregister a cleanup handler
# Usage: kt_fixture_cleanup_unregister "cleanup_function_name"
kt_fixture_cleanup_unregister() {
    local handler="$1"
    local i
    
    # Find and remove the handler
    for ((i = 0; i < ${#_KT_CLEANUP_HANDLERS[@]}; i++)); do
        if [[ "${_KT_CLEANUP_HANDLERS[$i]}" == "$handler" ]]; then
            unset '_KT_CLEANUP_HANDLERS[$i]'
            kt_test_debug "Unregistered cleanup handler: $handler"
            # Reindex array
            _KT_CLEANUP_HANDLERS=("${_KT_CLEANUP_HANDLERS[@]}")
            return 0
        fi
    done
    
    kt_test_warning "Cleanup handler not found: $handler"
    return 1
}

# ============================================================================
# File Fixtures
# ============================================================================

# Create a fixture file with content
# Usage: kt_fixture_create_file "filename" "content"
kt_fixture_create_file() {
    local filename="$1"
    local content="$2"
    
    if [[ -z "$_KT_TMPDIR" ]]; then
        kt_test_error "Test temp directory not initialized"
        return 1
    fi
    
    local filepath="$_KT_TMPDIR/$filename"
    local dirname
    dirname=$(dirname "$filepath")
    
    [[ ! -d "$dirname" ]] && mkdir -p "$dirname"
    echo -n "$content" > "$filepath"
    
    kt_test_debug "Created fixture file: $filepath"
    echo "$filepath"
}

# Create a fixture directory structure
# Usage: kt_fixture_create_structure "/path/to/create" "dir1" "dir2/subdir"
kt_fixture_create_structure() {
    local base_dir="$1"
    shift
    
    if [[ -z "$_KT_TMPDIR" ]]; then
        kt_test_error "Test temp directory not initialized"
        return 1
    fi
    
    for subdir in "$@"; do
        local fullpath="$base_dir/$subdir"
        mkdir -p "$fullpath"
        kt_test_debug "Created fixture directory: $fullpath"
    done
    
    return 0
}

# ============================================================================
# Backup/Restore Fixtures
# ============================================================================

# Backup a file or directory for restoration after test
# Usage: kt_fixture_backup_file "/path/to/file"
kt_fixture_backup_file() {
    local filepath="$1"
    
    if [[ ! -e "$filepath" ]]; then
        kt_test_error "File to backup does not exist: $filepath"
        return 1
    fi
    
    local seq=$(( ++_KT_BACKUP_SEQ ))
    local backup_name
    backup_name=$(basename "$filepath")_backup_${$}_${seq}
    local backup_path="$_KT_TMPDIR/$backup_name"

    if [[ -d "$filepath" ]]; then
        cp -r "$filepath" "$backup_path"
    else
        cp "$filepath" "$backup_path"
    fi

    kt_test_debug "Backed up file: $filepath -> $backup_path"

    # Register + define the auto-restore handler under the SAME unique name so
    # teardown's `declare -F` actually finds it (the old name had a trailing
    # space and never matched). Paths are %q-escaped so spaces/quotes in a path
    # can't break the generated function body.
    local handler="_kt_restore_file_${$}_${seq}"
    kt_fixture_cleanup_register "$handler"
    eval "${handler}() { cp -r $(printf '%q' "$backup_path") $(printf '%q' "$filepath") 2>/dev/null || true; }"

    echo "$backup_path"
}

# Restore a backed-up file (manual restoration)
# Usage: kt_fixture_restore_file "/path/to/file" "$backup_path"
kt_fixture_restore_file() {
    local filepath="$1"
    local backup_path="$2"
    
    if [[ ! -e "$backup_path" ]]; then
        kt_test_error "Backup file does not exist: $backup_path"
        return 1
    fi
    
    if [[ -d "$backup_path" ]]; then
        rm -rf "$filepath"
        cp -r "$backup_path" "$filepath"
    else
        cp "$backup_path" "$filepath"
    fi
    
    kt_test_debug "Restored file: $filepath from $backup_path"
    return 0
}

# ============================================================================
# Exports for use in tests
# ============================================================================

readonly KT__FIXTURES_VERSION="1.0.0"

