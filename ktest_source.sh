#!/usr/bin/env bash
# ktest_source.sh - Helper to source ktest.sh reliably in all contexts
# Usage: source "$(dirname "$0")/../ktest_source.sh"
#
# This script handles sourcing ktest.sh correctly whether run directly or in bash -c context

# Try to find and source ktest.sh
_kt_source_framework() {
    local ktest_path=""
    
    # Method 1: Use KTESTS_LIB_DIR if available (set by test runner)
    if [[ -n "$KTESTS_LIB_DIR" && -f "$KTESTS_LIB_DIR/ktest.sh" ]]; then
        ktest_path="$KTESTS_LIB_DIR/ktest.sh"
    fi
    
    # Method 2: Try relative path from this file (BASH_SOURCE[0] is the ktest_source.sh file)
    if [[ -z "$ktest_path" ]]; then
        local this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "$this_dir/ktest.sh" ]]; then
            ktest_path="$this_dir/ktest.sh"
        fi
    fi
    
    # Method 3: Try relative path from SCRIPT_DIR if available
    if [[ -z "$ktest_path" && -n "$SCRIPT_DIR" ]]; then
        local script_parent="$(dirname "$SCRIPT_DIR")"
        if [[ -f "$script_parent/ktest.sh" ]]; then
            ktest_path="$script_parent/ktest.sh"
        fi
    fi
    
    # Method 4: Walk up directory tree looking for ktests/ktest.sh
    if [[ -z "$ktest_path" ]]; then
        local current_dir="$(pwd)"
        local max_depth=10
        local depth=0
        
        while [[ "$current_dir" != "/" && $depth -lt $max_depth ]]; do
            if [[ -f "$current_dir/ktests/ktest.sh" ]]; then
                ktest_path="$current_dir/ktests/ktest.sh"
                break
            fi
            current_dir="$(dirname "$current_dir")"
            ((depth++))
        done
    fi
    
    # If we found it, source it
    if [[ -n "$ktest_path" && -f "$ktest_path" ]]; then
        source "$ktest_path"
        return 0
    else
        echo "ERROR: Could not locate ktest.sh framework" >&2
        echo "  Searched in:" >&2
        [[ -n "$KTESTS_LIB_DIR" ]] && echo "    - KTESTS_LIB_DIR: $KTESTS_LIB_DIR" >&2
        [[ -n "$SCRIPT_DIR" ]] && echo "    - SCRIPT_DIR: $SCRIPT_DIR" >&2
        echo "    - Current working directory: $(pwd)" >&2
        echo "    - BASH_SOURCE[0]: ${BASH_SOURCE[0]}" >&2
        return 1
    fi
}

# Source the framework
_kt_source_framework
