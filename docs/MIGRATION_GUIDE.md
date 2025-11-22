# KK Testing Framework - Migration Guide

Quick guide to migrate your existing test suites to the unified framework.

## Why Migrate?

- 85-91% reduction in duplicated code per test suite
- Single source of truth for testing utilities
- Better maintenance - fix bugs once, not 7 times
- Access to 30+ assertion helpers
- Automatic resource cleanup

## Quick Migration (15 min)

### Step 1: Copy Template

```bash
cp templates/common.sh.template your_tests/common.sh
```

### Step 2: Update Module Name

```bash
# Edit: your_tests/common.sh
# Change line:
# MODULE_NAME="your_module_name"
```

### Step 3: Verify

```bash
# Run your existing tests
cd your_tests
./test_suite.sh -v info

# All tests should pass without modification!
```

That's it! Your tests now use the framework.

## Before and After

### Before (Old common.sh)
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKLASS_DIR="$SCRIPT_DIR/.."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
# ... 200+ more lines of duplicated code ...

test_start() { ... }
test_pass() { ... }
test_fail() { ... }
parse_args() { ... }
# ... many more functions ...
```

### After (New common.sh with framework)
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/.."

KKTESTS_DIR="$(dirname "$MODULE_DIR")/kktests"
source "$KKTESTS_DIR/lib/kk-test.sh"

kk_test_init "module_name" "$SCRIPT_DIR"
kk_runner_parse_args "$@"
```

**Reduction: ~91% less code in common.sh**

## Your Tests Don't Change

Your existing test files work **exactly as before**:

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

test_start "My test"
test_pass "Test passed"
test_fail "Test failed"

# All old function names work unchanged!
```

## New Features (Optional)

Once migrated, you can use new assertion helpers:

### Before (manual checks)
```bash
if [[ "$result" == "expected" ]]; then
    test_pass "Values match"
else
    test_fail "Values don't match"
fi
```

### After (with assertions)
```bash
kk_assert_equals "expected" "$result" "Values match"
```

## Test Each Suite

### Test Suite 1: kklass/tests
```bash
cp templates/common.sh.template kklass/tests/common.sh
# Edit: MODULE_NAME="kklass"
./kklass/tests/kklass_tests.sh -v info
```

### Test Suite 2: kcl/tfile/tests
```bash
cp templates/common.sh.template kcl/tfile/tests/common.sh
# Edit: MODULE_NAME="tfile"
./kcl/tfile/tests/tests_tfile.sh -v info
```

### Repeat for Others
- kcl/tstringlist/tests
- kcl/tlist/tests
- kcl/tpath/tests
- kcl/tstringhelper/tests
- kcl/tdirectory/tests

## Handling Issues

### Issue: Framework not found
```bash
# Check the path in your common.sh
KKTESTS_DIR="$(dirname "$MODULE_DIR")/kktests"

# Should resolve to: /c:/projects/kkbot/lib/kktests
```

### Issue: Tests not running
```bash
# Verify directory structure
ls -la kktests/lib/kk-test*.sh
ls -la kktests/templates/common.sh.template

# Run with full path if needed
source "/c:/projects/kkbot/lib/kktests/lib/kk-test.sh"
```

### Issue: Backward compatibility
All original function names are aliased:
- `test_start()` → works
- `test_pass()` → works
- `test_fail()` → works
- `parse_args()` → works
- `init_test_tmpdir()` → works

No code changes needed!

## Gradual Enhancement

After migration, you can optionally enhance your tests:

### Add Fixtures
```bash
# Before
TEST_TMP_DIR="/tmp/test_$$"
mkdir -p "$TEST_TMP_DIR"
cleanup() { rm -rf "$TEST_TMP_DIR"; }
trap cleanup EXIT

# After
init_test_tmpdir "001"
# Framework handles it automatically
```

### Use Assertions
```bash
# Before
if [[ -f "$file" ]]; then
    test_pass "File created"
else
    test_fail "File not created"
fi

# After
kk_assert_file_exists "$file" "File created"
```

### Register Cleanup
```bash
cleanup_service() {
    kill "$SERVICE_PID" 2>/dev/null || true
}
kk_fixture_cleanup_register "cleanup_service"
# Runs automatically on EXIT
```

## Rollback

If you need to revert:
```bash
# Just restore the original common.sh
cp common.sh.backup common.sh

# Tests work unchanged
# Zero risk!
```

## Timeline

| Action | Time |
|--------|------|
| Copy template | 1 min |
| Update module name | 1 min |
| Run tests | 5-10 min |
| Verify all pass | 5 min |
| **Total per suite** | **15-20 min** |

**For all 7 suites: ~2 hours**

## After Migration

You now have:
- ✓ Cleaner, smaller common.sh files
- ✓ Access to 30+ assertion helpers
- ✓ Automatic temp file management
- ✓ Automatic resource cleanup
- ✓ Single source of truth for testing code
- ✓ All existing tests working unchanged

## Next Steps

1. Read [README.md](README.md) for full documentation
2. Check [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for available functions
3. Look at [../templates/test-example.sh](../templates/test-example.sh) for working examples

## Questions?

See [START_HERE.md](START_HERE.md) for a quick overview.

---

**Framework Version**: 1.0.0  
**Migration Risk**: Low (100% backward compatible)  
**Time to Migrate**: 15-20 min per test suite
