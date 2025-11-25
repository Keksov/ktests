#!/bin/bash
# kk-test-fixtures.sh - Fixture and resource management for tests
# Provides temporary directory management, setup/teardown, and cleanup coordination
#
# Requires: kk-test-core.sh to be sourced first

# Prevent multiple sourcing
if [[ -n "$_KK_TEST_FIXTURES_SOURCED" ]]; then
    return
fi
_KK_TEST_FIXTURES_SOURCED=1

# Ensure core framework is available
if [[ -z "$_KK_TEST_CORE_SOURCED" ]]; then
    echo "ERROR: kk-test-core.sh must be sourced before kk-test-fixtures.sh" >&2
    return 1
fi

# ============================================================================
# Global State
# ============================================================================

# Test ID for identifying test runs
declare -g KK_TEST_ID=""

# Test-specific temporary directory
declare -g KK_TEST_TMPDIR=""

# Base temporary directory
declare -g KK_TEST_TMPBASE=""

# Array of registered cleanup functions
declare -ga _KK_CLEANUP_HANDLERS=()

# Array of created temporary directories
declare -ga _KK_CREATED_TMPDIRS=()

# ============================================================================
# Temp Directory Management
# ============================================================================

# Initialize test-specific temporary directory
# Usage: kk_fixture_init_tmpdir "test_id" "/path/to/tests"
# Sets: KK_TEST_TMPDIR
kk_fixture_init_tmpdir() {
    local test_id="${1:-default}"
    local base_dir="${2:-./.tmp}"
    
    KK_TEST_ID="$test_id"
    KK_TEST_TMPBASE="$base_dir"
    
    # Ensure base directory exists
    [[ ! -d "$KK_TEST_TMPBASE" ]] && mkdir -p "$KK_TEST_TMPBASE"
    
    # Create test-specific directory
    KK_TEST_TMPDIR="$KK_TEST_TMPBASE/$test_id"
    mkdir -p "$KK_TEST_TMPDIR"
    
    _KK_CREATED_TMPDIRS+=("$KK_TEST_TMPDIR")
    
    kk_test_debug "Initialized test temp directory: $KK_TEST_TMPDIR"
    
    return 0
}

# Get the test temporary directory
# Usage: tmpdir=$(kk_fixture_tmpdir)
kk_fixture_tmpdir() {
    if [[ -z "$KK_TEST_TMPDIR" ]]; then
        kk_test_warning "Test temp directory not initialized. Run kk_fixture_init_tmpdir first."
        return 1
    fi
    echo "$KK_TEST_TMPDIR"
}

# Create a temporary file within the test directory
# Usage: file=$(kk_fixture_tmpfile "prefix")
kk_fixture_tmpfile() {
    local prefix="${1:-test}"
    
    if [[ -z "$KK_TEST_TMPDIR" ]]; then
        kk_test_error "Test temp directory not initialized"
        return 1
    fi
    
    local tmpfile
    tmpfile=$(mktemp "$KK_TEST_TMPDIR/${prefix}.XXXXXX")
    echo "$tmpfile"
    return 0
}

# Create a temporary directory within the test directory
# Usage: tmpdir=$(kk_fixture_tmpdir_create "subdir_name")
kk_fixture_tmpdir_create() {
    local name="${1:-tmpdir}"
    
    if [[ -z "$KK_TEST_TMPDIR" ]]; then
        kk_test_error "Test temp directory not initialized"
        return 1
    fi
    
    local tmpdir="$KK_TEST_TMPDIR/$name"
    mkdir -p "$tmpdir"
    echo "$tmpdir"
    return 0
}

# ============================================================================
# Setup and Teardown
# ============================================================================

# Setup test fixtures
# Usage: kk_fixture_setup "test_id"
kk_fixture_setup() {
    local test_id="${1:-default}"
    local script_dir="${2:-.}"
    
    # Initialize temp directory
    kk_fixture_init_tmpdir "$test_id" "$script_dir/.tmp"
    
    kk_test_debug "Fixture setup complete for test: $test_id"
}

# Teardown test fixtures and cleanup resources
# Usage: kk_fixture_teardown
kk_fixture_teardown() {
    local i
    
    # Call registered cleanup handlers in reverse order
    for ((i = ${#_KK_CLEANUP_HANDLERS[@]} - 1; i >= 0; i--)); do
        local handler="${_KK_CLEANUP_HANDLERS[$i]}"
        kk_test_debug "Executing cleanup handler: $handler"
        if declare -F "$handler" >/dev/null 2>&1; then
            "$handler" 2>/dev/null || true
        fi
    done
    
    # Clean up temp directories
    for tmpdir in "${_KK_CREATED_TMPDIRS[@]}"; do
        if [[ -d "$tmpdir" ]]; then
            rm -rf "$tmpdir" 2>/dev/null || true
            kk_test_debug "Cleaned up temp directory: $tmpdir"
        fi
    done
    
    # Clear handlers and directories
    _KK_CLEANUP_HANDLERS=()
    _KK_CREATED_TMPDIRS=()
    KK_TEST_TMPDIR=""
    KK_TEST_ID=""
}

# ============================================================================
# Cleanup Registration
# ============================================================================

# Register a cleanup handler function
# Handlers are called in reverse order during teardown
# Usage: kk_fixture_cleanup_register "cleanup_function_name"
kk_fixture_cleanup_register() {
    local handler="$1"
    
    if [[ -z "$handler" ]]; then
        kk_test_error "Cleanup handler name required"
        return 1
    fi
    
    _KK_CLEANUP_HANDLERS+=("$handler")
    kk_test_debug "Registered cleanup handler: $handler"
    return 0
}

# Unregister a cleanup handler
# Usage: kk_fixture_cleanup_unregister "cleanup_function_name"
kk_fixture_cleanup_unregister() {
    local handler="$1"
    local i
    
    # Find and remove the handler
    for ((i = 0; i < ${#_KK_CLEANUP_HANDLERS[@]}; i++)); do
        if [[ "${_KK_CLEANUP_HANDLERS[$i]}" == "$handler" ]]; then
            unset '_KK_CLEANUP_HANDLERS[$i]'
            kk_test_debug "Unregistered cleanup handler: $handler"
            # Reindex array
            _KK_CLEANUP_HANDLERS=("${_KK_CLEANUP_HANDLERS[@]}")
            return 0
        fi
    done
    
    kk_test_warning "Cleanup handler not found: $handler"
    return 1
}

# ============================================================================
# File Fixtures
# ============================================================================

# Create a fixture file with content
# Usage: kk_fixture_create_file "filename" "content"
kk_fixture_create_file() {
    local filename="$1"
    local content="$2"
    
    if [[ -z "$KK_TEST_TMPDIR" ]]; then
        kk_test_error "Test temp directory not initialized"
        return 1
    fi
    
    local filepath="$KK_TEST_TMPDIR/$filename"
    local dirname
    dirname=$(dirname "$filepath")
    
    [[ ! -d "$dirname" ]] && mkdir -p "$dirname"
    echo -n "$content" > "$filepath"
    
    kk_test_debug "Created fixture file: $filepath"
    echo "$filepath"
}

# Create a fixture directory structure
# Usage: kk_fixture_create_structure "/path/to/create" "dir1" "dir2/subdir"
kk_fixture_create_structure() {
    local base_dir="$1"
    shift
    
    if [[ -z "$KK_TEST_TMPDIR" ]]; then
        kk_test_error "Test temp directory not initialized"
        return 1
    fi
    
    for subdir in "$@"; do
        local fullpath="$base_dir/$subdir"
        mkdir -p "$fullpath"
        kk_test_debug "Created fixture directory: $fullpath"
    done
    
    return 0
}

# ============================================================================
# Backup/Restore Fixtures
# ============================================================================

# Backup a file or directory for restoration after test
# Usage: kk_fixture_backup_file "/path/to/file"
kk_fixture_backup_file() {
    local filepath="$1"
    
    if [[ ! -e "$filepath" ]]; then
        kk_test_error "File to backup does not exist: $filepath"
        return 1
    fi
    
    local backup_name
    backup_name=$(basename "$filepath")_backup_$$
    local backup_path="$KK_TEST_TMPDIR/$backup_name"
    
    if [[ -d "$filepath" ]]; then
        cp -r "$filepath" "$backup_path"
    else
        cp "$filepath" "$backup_path"
    fi
    
    kk_test_debug "Backed up file: $filepath -> $backup_path"
    
    # Register restore handler
    kk_fixture_cleanup_register "_kk_restore_file_$$ "
    eval "_kk_restore_file_$$ () { cp -r '$backup_path' '$filepath' 2>/dev/null || true; }"
    
    echo "$backup_path"
}

# Restore a backed-up file (manual restoration)
# Usage: kk_fixture_restore_file "/path/to/file" "$backup_path"
kk_fixture_restore_file() {
    local filepath="$1"
    local backup_path="$2"
    
    if [[ ! -e "$backup_path" ]]; then
        kk_test_error "Backup file does not exist: $backup_path"
        return 1
    fi
    
    if [[ -d "$backup_path" ]]; then
        rm -rf "$filepath"
        cp -r "$backup_path" "$filepath"
    else
        cp "$backup_path" "$filepath"
    fi
    
    kk_test_debug "Restored file: $filepath from $backup_path"
    return 0
}

# ============================================================================
# Exports for use in tests
# ============================================================================

readonly KK_TEST_FIXTURES_VERSION="1.0.0"

