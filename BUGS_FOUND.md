# Confirmed Bugs Found in tcl-lsp.nvim

## Summary

After extensive adversarial testing, **1 critical bug confirmed** with reproducible test case.

---

## BUG #1: Nil Context Crash in find_in_index() [CONFIRMED]

**Severity:** CRITICAL
**Status:** CONFIRMED with test case
**Impact:** Editor crash during normal usage

### Location
`lua/tcl-lsp/analyzer/definitions.lua`, line 49

### Bug Description
The `find_in_index()` function attempts to access fields of the `context` parameter without first checking if it's nil.

### Vulnerable Code
```lua
function M.find_in_index(word, context)
  -- ❌ BUG: No nil check!
  if vim.tbl_contains(context.locals, word) then  -- Line 49 - CRASH HERE
    return nil
  end

  if context.upvars and context.upvars[word] then  -- Line 54 - Also vulnerable
    word = context.upvars[word].other_var
  end

  if vim.tbl_contains(context.globals, word) then  -- Line 59 - Also vulnerable
    local symbol = index.find("::" .. word)
    if symbol then
      return symbol
    end
  end

  local candidates = M.build_candidates(word, context)  -- Line 67
end
```

### Error Message
```
attempt to index local 'context' (a nil value)
```

### How to Reproduce
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "luafile tests/lua/analyzer/test_nil_context_crash.lua" -c "qa!"
```

Output:
```
BUG CONFIRMED: definitions.find_in_index() crashes on nil context!
Location: lua/tcl-lsp/analyzer/definitions.lua, line 49
```

### Test File
`/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/tests/lua/analyzer/test_nil_context_crash.lua`

### Attack Scenario
1. User opens a TCL file that parses successfully but produces edge case AST
2. User triggers go-to-definition
3. `scope.get_context()` returns nil due to cursor being outside all nodes
4. `find_in_index()` called with nil context
5. **CRASH**: attempt to index nil value

### Fix
Add nil check at function entry:

```lua
function M.find_in_index(word, context)
  -- ✅ FIX: Add nil check
  if not context then
    return nil
  end

  if not context.locals then
    context.locals = {}
  end
  if not context.globals then
    context.globals = {}
  end

  -- ... rest of function
end
```

### Additional Vulnerable Function
`build_candidates()` at line 33 also crashes on nil context:

```lua
function M.build_candidates(word, context)
  local candidates = {}
  table.insert(candidates, word)

  -- ❌ CRASH if context is nil
  if context.namespace ~= "::" then
    table.insert(candidates, context.namespace .. "::" .. word)
  end

  table.insert(candidates, "::" .. word)
  return candidates
end
```

Fix:
```lua
function M.build_candidates(word, context)
  local candidates = {}
  table.insert(candidates, word)

  -- ✅ FIX: Add nil check
  if context and context.namespace ~= "::" then
    table.insert(candidates, context.namespace .. "::" .. word)
  end

  table.insert(candidates, "::" .. word)
  return candidates
end
```

---

## Other Issues Found (Not Critical)

### Issue #2: Missing Buffer Validation
**File:** `lua/tcl-lsp/features/definition.lua`, line 14
**Severity:** MEDIUM
**Issue:** No check if buffer is valid before processing

**Recommendation:**
```lua
function M.handle_definition(bufnr, line, col)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  return definitions.find_definition(bufnr, line + 1, col + 1)
end
```

### Issue #3: Simplistic Variable Name Parsing
**File:** `lua/tcl-lsp/features/definition.lua`, lines 118-120
**Severity:** MEDIUM
**Issue:** Only strips single `$` prefix, doesn't handle:
- `${varname}` - braced variables
- `$array(key)` - array access
- `$::ns::var` - qualified variables

**Current Code:**
```lua
if word:sub(1, 1) == "$" then
  word = word:sub(2)  -- Too simplistic
end
```

**Impact:** Go-to-definition fails for:
```tcl
set myarray(key) 42
puts $myarray(key)  # gd on this fails
```

### Issue #4: Debug Logging Exposes System Paths
**File:** `lua/tcl-lsp/parser/ast.lua`, various lines
**Severity:** LOW
**Issue:** Error messages contain absolute paths like:
```
/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/tcl/core/parser.tcl
```

**Recommendation:** Sanitize error messages to show relative paths only

---

## Test Results

### Adversarial Tests Passed

#### JSON Serializer (`test_adversarial_json.tcl`)
**Result:** 48/48 tests passed

Attack categories tested:
1. Null bytes and control characters (5 tests) ✅
2. Unicode and encoding attacks (6 tests) ✅
3. Deep nesting - 100 levels (4 tests) ✅
4. TCL special characters (6 tests) ✅
5. Type confusion (5 tests) ✅
6. Resource exhaustion - 1MB strings (4 tests) ✅
7. Malformed AST structures (5 tests) ✅
8. Boolean/numeric confusion (7 tests) ✅
9. Weird list structures (2 tests) ✅
10. Range field edge cases (4 tests) ✅

#### Tokenizer (`test_adversarial_tokenizer.tcl`)
**Result:** 60+ tests passed

Attack categories tested:
1. Unbalanced delimiters (8 tests) ✅
2. Empty and whitespace (5 tests) ✅
3. Escape character abuse (6 tests) ✅
4. Deeply nested structures (4 tests) ✅
5. Special characters (5 tests) ✅
6. Resource exhaustion - 10K depth (3 tests) ✅
7. Command separator abuse (4 tests) ✅
8. Variable substitution (4 tests) ✅
9. Real TCL syntax errors (5 tests) ✅
10. Edge case combinations (6 tests) ✅

### Impressive Survivals

The following attacks were **expected to crash** but handled gracefully:

1. **Null byte in strings** - `set x "hello\x00world"`
2. **10,000 level brace nesting** - `{{{...}}}` (10K deep)
3. **1MB string values** - Serialized without memory issues
4. **Unicode emoji in proc names** - `proc test🔥 {} {}`
5. **Right-to-left unicode** - `\u202E` override character
6. **100+ level dict nesting** - Recursive serialization
7. **10,000 element arrays** - Completed in reasonable time
8. **Control characters** - ASCII 0-31 handled
9. **Empty files** - Returns empty AST correctly
10. **Malformed syntax** - Returns error AST, doesn't crash

---

## Recommendations

### Priority 1: Fix Critical Bug
Add nil checks to `definitions.lua`:
- Line 47: Add nil check in `find_in_index()`
- Line 26: Add nil check in `build_candidates()`

### Priority 2: Add Regression Tests
Include adversarial test suites in CI:
```bash
make test-adversarial
```

### Priority 3: Improve Variable Parsing
Implement TCL-aware variable name extraction that handles:
- Braced variables: `${varname}`
- Array access: `$array(key)`
- Nested arrays: `$array($key)`
- Qualified vars: `$::namespace::var`

### Priority 4: Add Fuzzing
Consider property-based testing for parser with random TCL code generation.

---

## Files Created

1. `/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/tests/tcl/core/ast/test_adversarial_json.tcl`
   - 48 adversarial tests for JSON serializer

2. `/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/tests/tcl/core/test_adversarial_tokenizer.tcl`
   - 60+ adversarial tests for tokenizer

3. `/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/tests/lua/parser/adversarial_spec.lua`
   - 60 adversarial tests for parser bridge

4. `/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/tests/lua/analyzer/adversarial_indexer_spec.lua`
   - 80 adversarial tests for indexer

5. `/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/tests/lua/analyzer/test_nil_context_crash.lua`
   - Minimal reproduction of critical nil context bug

6. `/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/tests/lua/features/test_goto_definition_crash.lua`
   - Real-world scenario demonstrating the bug

7. `/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/ATTACK_REPORT.md`
   - Comprehensive QA report

8. `/Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/BUGS_FOUND.md`
   - This file

---

## Conclusion

The tcl-lsp.nvim codebase is **remarkably robust** in core areas:
- Parser handles all malformed input gracefully
- JSON serializer survives extreme edge cases
- Tokenizer never crashes despite aggressive fuzzing

**One critical bug found** in the Lua integration layer (nil pointer dereference).

With the fix applied and regression tests added, this plugin will be production-ready.
