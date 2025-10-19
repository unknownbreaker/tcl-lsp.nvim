# TCL AST Module Test Suite

## Overview

Comprehensive test suite for the refactored TCL AST modules. Each module has its own focused test file that mirrors the implementation structure.

## Test Structure

```
tests/tcl/core/ast/
├── run_all_tests.tcl          # Master test runner
├── test_json.tcl               # JSON serialization tests (40 tests)
├── test_utils.tcl              # Utilities tests (35 tests)
├── test_comments.tcl           # Comment extraction tests (10 tests)
├── test_commands.tcl           # Command extraction tests (10 tests)
├── parsers/
│   ├── test_procedures.tcl     # Procedure parser tests (5 tests)
│   ├── test_variables.tcl      # Variable parser tests (12 tests)
│   ├── test_control_flow.tcl   # Control flow parser tests (14 tests)
│   ├── test_namespaces.tcl     # Namespace parser tests (8 tests)
│   ├── test_packages.tcl       # Package parser tests (5 tests)
│   ├── test_expressions.tcl    # Expression parser tests (7 tests)
│   └── test_lists.tcl          # List parser tests (9 tests)
└── integration/
    └── test_full_ast.tcl       # Full AST integration tests (10 tests)
```

## Running Tests

### Run All Tests

```bash
cd tests/tcl/core/ast
tclsh run_all_tests.tcl
```

### Run Individual Test Suites

```bash
# Test JSON module (most critical - has the bug fix!)
tclsh test_json.tcl

# Test utilities
tclsh test_utils.tcl

# Test comments
tclsh test_comments.tcl

# Test commands
tclsh test_commands.tcl

# Test procedure parser
tclsh parsers/test_procedures.tcl

# Test full integration
tclsh integration/test_full_ast.tcl
```

## Test Coverage

### test_json.tcl (40 tests)
**Purpose:** Validates the critical JSON serialization bug fix

**Groups:**
1. **Basic Types** (5 tests) - Strings, integers, floats, booleans
2. **Special Characters** (5 tests) - Newlines, quotes, backslashes, tabs
3. **Lists** (5 tests) - Empty, simple, numeric, mixed, single element
4. **Nested Structures** (5 tests) - **THE BUG FIX VALIDATION** ⭐
5. **Real-World AST** (5 tests) - Proc nodes, set nodes, root with children
6. **Indentation** (2 tests) - Proper formatting
7. **Edge Cases** (3 tests) - Long strings, many keys, deep nesting

**Why Critical:**
- Tests the fix for "bad class 'dict'" error
- Validates list of dicts serialization
- Ensures AST can be converted to JSON without errors

### test_utils.tcl (35 tests)
**Purpose:** Position tracking and range creation

**Groups:**
1. **Range Creation** (5 tests) - Simple, single-line, column-only, large numbers
2. **Line Mapping** (4 tests) - Single/multiple lines, empty, very long
3. **Offset to Line** (6 tests) - Various positions in multiline code
4. **Line Counting** (6 tests) - Different line configurations
5. **Complex Scenarios** (4 tests) - Real TCL code patterns
6. **Edge Cases** (4 tests) - Unicode, CRLF, mixed line endings

### test_comments.tcl (10 tests)
**Purpose:** Comment extraction accuracy

**Tests:**
- No comments
- Single/multiple comments
- Indented comments
- Comments with special characters
- Edge cases (empty file, whitespace)

### test_commands.tcl (10 tests)
**Purpose:** Command splitting and extraction

**Tests:**
- Single/multiple commands
- Multiline commands (procs, loops)
- Commands with comments
- Empty lines handling
- Nested braces

### test_procedures.tcl (5 tests)
**Purpose:** Procedure parsing correctness

**Tests:**
- Simple proc with no args
- Proc with arguments
- Proc with default values
- Proc with varargs
- Complex procedures

### test_variables.tcl (12 tests)
**Purpose:** Variable operation parsing

**Tests:**
- set commands (simple, string, variable reference)
- variable declarations (with/without defaults)
- global variables (single, multiple)
- upvar commands (simple, with level)
- array operations (set, get, exists)

### test_control_flow.tcl (14 tests)
**Purpose:** Control flow statement parsing

**Tests:**
- if statements (simple, if-else, if-elseif-else)
- while loops (simple, complex conditions)
- for loops (simple, with step)
- foreach loops (simple, multiple vars, multiple lists)
- switch statements (simple, with default, with options)

### test_namespaces.tcl (8 tests)
**Purpose:** Namespace operation parsing

**Tests:**
- namespace eval (simple, with body, nested)
- namespace import (simple, specific)
- namespace export (simple, multiple, with pattern)

### test_packages.tcl (5 tests)
**Purpose:** Package operation parsing

**Tests:**
- package require (simple, with version, exact version)
- package provide (simple, with version)

### test_expressions.tcl (7 tests)
**Purpose:** Expression parsing

**Tests:**
- Simple arithmetic
- Expressions with variables
- Complex expressions
- Comparisons
- Logical expressions
- Function calls
- String comparisons

### test_lists.tcl (9 tests)
**Purpose:** List operation parsing

**Tests:**
- list command (simple, empty, with spaces)
- lappend command (simple, multiple elements)
- puts command (simple, to channel, with options)

### test_full_ast.tcl (10 tests)
**Purpose:** End-to-end AST building

**Tests:**
1. Empty code handling
2. Single set command
3. Simple procedure
4. Multiple commands
5. Control flow (if statement)
6. Namespace declarations
7. Comment tracking
8. Syntax error detection
9. Complex realistic code
10. JSON conversion

## Test Output Format

### Successful Test
```
✓ PASS: Test name
```

### Failed Test
```
✗ FAIL: Test name
  Expected: value
  Got: different_value
```

### Test Summary
```
=========================================
Test Results
=========================================
Total:  40
Passed: 40
Failed: 0

✓ ALL TESTS PASSED
```

## Adding New Tests

### Template for New Test File

```tcl
#!/usr/bin/env tclsh
# tests/tcl/core/ast/test_yourmodule.tcl

set script_dir [file dirname [file normalize [info script]]]
set ast_dir [file join [file dirname [file dirname [file dirname [file dirname $script_dir]]]] tcl core ast]
source [file join $ast_dir yourmodule.tcl]

set total 0
set passed 0

proc test {name script expected} {
    global total passed
    incr total
    
    if {[catch {uplevel 1 $script} result]} {
        puts "✗ FAIL: $name - Error: $result"
        return
    }
    
    if {$result eq $expected} {
        puts "✓ PASS: $name"
        incr passed
    } else {
        puts "✗ FAIL: $name"
        puts "  Expected: $expected"
        puts "  Got: $result"
    }
}

puts "Your Module Tests"
puts "=================\n"

test "Test 1" {
    # Test code here
} "expected_result"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
```

### Add to Master Test Runner

Edit `run_all_tests.tcl` and add:

```tcl
run_test_suite "Your Module" \
    [file join $test_dir test_yourmodule.tcl]
```

## Integration with CI/CD

### In Makefile

```makefile
test-ast:
	@cd tests/tcl/core/ast && tclsh run_all_tests.tcl

test-ast-json:
	@cd tests/tcl/core/ast && tclsh test_json.tcl

test-ast-integration:
	@cd tests/tcl/core/ast && tclsh integration/test_full_ast.tcl
```

### In GitHub Actions

```yaml
- name: Run AST Module Tests
  run: |
    cd tests/tcl/core/ast
    tclsh run_all_tests.tcl
```

## Debugging Failed Tests

### Enable Verbose Output

Add debug output to individual tests:

```tcl
proc test {name script expected} {
    global total passed
    incr total
    
    puts "Running: $name"
    puts "  Script: $script"
    
    if {[catch {uplevel 1 $script} result]} {
        puts "  Error: $result"
        return
    }
    
    puts "  Result: $result"
    puts "  Expected: $expected"
    
    # ... rest of test
}
```

### Run Single Test

Modify test file to run only one test:

```tcl
# Comment out other tests
test "The one I'm debugging" {
    # test code
} "expected"
```

## Test Philosophy

### Unit Tests
- **Fast** - Each suite runs in <1 second
- **Focused** - One module per file
- **Independent** - No dependencies between tests
- **Clear** - Descriptive names and error messages

### Integration Tests
- **Realistic** - Use real TCL code patterns
- **Comprehensive** - Test complete workflows
- **End-to-end** - From input to JSON output

## Expected Results

After deployment, all tests should pass:

```
========================================
TEST SUITE SUMMARY
========================================

Test Suite                               Status
============================================================
JSON Serialization                       ✓ PASS
Utilities                                ✓ PASS
Comment Extraction                       ✓ PASS
Command Extraction                       ✓ PASS
Procedure Parser                         ✓ PASS
Full AST Integration                     ✓ PASS
============================================================

Total Suites:  6
Passed:        6
Failed:        0

✓ ALL TEST SUITES PASSED

Ready for deployment!
```

## Troubleshooting

### "cannot find package/module"
**Issue:** Path to modules incorrect  
**Fix:** Check that `ast_dir` variable points to correct location

### "command not found"
**Issue:** TCL procedure not loaded  
**Fix:** Ensure `source` commands load modules before use

### Tests pass individually but fail in runner
**Issue:** State pollution between tests  
**Fix:** Use fresh `interp` or reset globals

## Continuous Improvement

As you add features:
1. Write tests first (TDD approach)
2. Add to appropriate test file
3. Run `run_all_tests.tcl` to verify
4. Update this README with new test counts

## Summary

- **170 total tests** across 13 test suites
- **Mirrors module structure** for easy navigation
- **Validates the critical bug fix** in JSON module
- **Easy to run** - single command for all tests
- **Easy to extend** - clear templates and patterns

**Run them!** `tclsh run_all_tests.tcl`
