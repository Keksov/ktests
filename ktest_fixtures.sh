#!/bin/bash
# ktest_fixtures.sh - Fixture and resource management for tests
# Provides temporary directory management, setup/teardown, and cleanup coordination
#
# Requires: ktest_core.sh to be sourced first

# Prevent multiple sourcing
if [[ -n "$_KTEST_FIXTURES_SOURCED" ]]; then
    return
fi
_KTEST_FIXTURES_SOURCED=1

# Ensure core framework is available
if [[ -z "$_KTEST_CORE_SOURCED" ]]; then
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

# ============================================================================
# Temp Directory Management
# ============================================================================

# Initialize test-specific temporary directory
# Usage: kt_fixture_init_tmpdir "test_id" "/path/to/tests"
# Sets: _KT_TMPDIR
kt_fixture_init_tmpdir() {
    local test_id="${1:-default}"
    local base_dir="${2:-./.tmp}"
    
    _KT_ID="$test_id"
    _KT_TMPBASE="$base_dir"
    
    # Ensure base directory exists
    [[ ! -d "$_KT_TMPBASE" ]] && mkdir -p "$_KT_TMPBASE"
    
    # Create test-specific directory
    _KT_TMPDIR="$_KT_TMPBASE/$test_id"
    mkdir -p "$_KT_TMPDIR"
    
    _KT_CREATED_TMPDIRS+=("$_KT_TMPDIR")
    
    kt_test_debug "Initialized test temp directory: $_KT_TMPDIR"
    
    return 0
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
    
    # Clean up temp directories
    for tmpdir in "${_KT_CREATED_TMPDIRS[@]}"; do
        if [[ -d "$tmpdir" ]]; then
            rm -rf "$tmpdir" 2>/dev/null || true
            kt_test_debug "Cleaned up temp directory: $tmpdir"
        fi
    done
    
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
    
    local backup_name
    backup_name=$(basename "$filepath")_backup_$$
    local backup_path="$_KT_TMPDIR/$backup_name"
    
    if [[ -d "$filepath" ]]; then
        cp -r "$filepath" "$backup_path"
    else
        cp "$filepath" "$backup_path"
    fi
    
    kt_test_debug "Backed up file: $filepath -> $backup_path"
    
    # Register restore handler
    kt_fixture_cleanup_register "_kt_restore_file_$$ "
    eval "_kt_restore_file_$$ () { cp -r '$backup_path' '$filepath' 2>/dev/null || true; }"
    
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

