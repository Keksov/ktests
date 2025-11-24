#!/bin/bash
# Unit tests: Advanced array assertion checks

source "$(cd "$(dirname "$0")/.." && pwd)/kk-test.sh"

kk_test_init "AdvancedArrayOperations" "$(dirname "$0")"

# Test kk_assert_array_contains with value that exists
kk_test_start "kk_assert_array_contains with existing value"
declare -a test_arr=("apple" "banana" "cherry" "date")
if kk_assert_array_contains test_arr "banana" "Contains test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains fails with non-existing value
kk_test_start "kk_assert_array_contains fails with non-existing value"
if ! kk_assert_array_contains test_arr "grape" "Non-existing test"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_array_contains with empty array
kk_test_start "kk_assert_array_contains with empty array"
declare -a empty_arr=()
if ! kk_assert_array_contains empty_arr "anything" "Empty array test"; then
    kk_test_pass "Assertion correctly failed"
else
    kk_test_fail "Assertion should have failed"
fi

# Test kk_assert_array_contains with numbers
kk_test_start "kk_assert_array_contains with numeric values"
declare -a num_arr=(1 2 3 4 5)
if kk_assert_array_contains num_arr 3 "Numeric contains test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with special characters
kk_test_start "kk_assert_array_contains with special characters"
declare -a special_arr=("test\$value" "hello@world" "path/to/file")
if kk_assert_array_contains special_arr "hello@world" "Special chars test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with duplicate values
kk_test_start "kk_assert_array_contains with duplicate values"
declare -a dup_arr=("item1" "item2" "item1" "item3")
if kk_assert_array_contains dup_arr "item1" "Duplicate test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with case sensitivity
kk_test_start "kk_assert_array_contains case sensitivity"
declare -a case_arr=("Hello" "World" "Test")
if ! kk_assert_array_contains case_arr "hello" "Case sensitive test"; then
    kk_test_pass "Assertion correctly failed (case sensitive)"
else
    kk_test_fail "Assertion should have failed (case sensitive)"
fi

# Test kk_assert_array_contains with whitespace values
kk_test_start "kk_assert_array_contains with whitespace values"
declare -a space_arr=(" value1 " "  value2  " "value3")
if kk_assert_array_contains space_arr " value1 " "Whitespace test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with mixed data types
kk_test_start "kk_assert_array_contains with mixed data types"
declare -a mixed_arr=("string" 123 "true" "")
if kk_assert_array_contains mixed_arr 123 "Mixed types test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with empty string search
kk_test_start "kk_assert_array_contains with empty string search"
declare -a empty_str_arr=("" "value1" "value2")
if kk_assert_array_contains empty_str_arr "" "Empty string search"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with very long values
kk_test_start "kk_assert_array_contains with long values"
long_value=$(printf "long_value_%s" {1..50})
declare -a long_arr=("short" "$long_value" "another")
if kk_assert_array_contains long_arr "$long_value" "Long value test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with multi-line values
kk_test_start "kk_assert_array_contains with multi-line values"
declare -a multiline_arr=("single" $'multi\nline' "value")
if kk_assert_array_contains multiline_arr $'multi\nline' "Multiline test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with glob patterns
kk_test_start "kk_assert_array_contains with glob patterns"
declare -a glob_arr=("file1.txt" "file2.log" "data.csv")
if kk_assert_array_contains glob_arr "file*.txt" "Glob pattern test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test with indexed array vs associative array
kk_test_start "kk_assert_array_contains with indexed array"
declare -a indexed_arr=("a" "b" "c")
if kk_assert_array_contains indexed_arr "b" "Indexed array test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with single element array
kk_test_start "kk_assert_array_contains with single element"
declare -a single_arr=("only_element")
if kk_assert_array_contains single_arr "only_element" "Single element test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test kk_assert_array_contains with unicode characters
kk_test_start "kk_assert_array_contains with unicode characters"
declare -a unicode_arr=("café" "naïve" "résumé")
if kk_assert_array_contains unicode_arr "café" "Unicode test"; then
    kk_test_pass "Assertion passed"
else
    kk_test_fail "Assertion failed"
fi

# Test that array reference is by name, not by value
kk_test_start "kk_assert_array_contains array reference test"
declare -a test_arr1=("value1" "value2")
declare -a test_arr2=("different" "values")
if ! kk_assert_array_contains test_arr1 "different" "Array reference test"; then
    kk_test_pass "Array reference works correctly"
else
    kk_test_fail "Array reference test failed"
fi