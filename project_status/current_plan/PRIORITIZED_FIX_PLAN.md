# Prioritized Fix Plan - Based on Actual Test Failures

## 🚨 Critical Discovery

**The Issue:** TCL tests are 100% passing (12/12), but Lua integration tests show only **23/39 passing**. This indicates the problem is in the **Lua-TCL bridge**, not the TCL parser itself.

```
TCL Tests: 12/12 passing ✅
Lua Tests: 23/39 passing ❌ (16 failures)
```

---

## 📊 Failure Analysis

### Root Cause Categories

| Category | Failures | Root Cause | Priority |
|----------|----------|------------|----------|
| **Nil Returns** | ~10 tests | Lua parser not calling TCL correctly | 🔴 **CRITICAL** |
| **Type Mismatches** | ~4 tests | Number vs string conversion | 🟡 HIGH |
| **Structure Issues** | ~2 tests | AST structure mismatch | 🟢 MEDIUM |

### Specific Failures Observed

```
Command Substitution Tests: 7/10 passing (3 failures)
- Expected: 'set', Got: nil
- Expected: '42' (string), Got: 42 (number)
- Expected: 'x', Got: nil

AST Parser Tests: 23/39 passing (16 failures)
- Multiple "Expected: 'set', Got: nil"
- Multiple "Expected: 'if', Got: nil"
- Package version: Expected '8.6', Got 8.5999... (float)
- Complex procedure: Expected 'proc', Got: nil
```

---

## 🎯 Priority 1: CRITICAL - Fix Lua-TCL Bridge (10-12 tests)

**Time Estimate:** 2-3 hours  
**Impact:** Fixes majority of nil returns  
**Difficulty:** 🟡 Medium

### Problem
The Lua parser is calling the TCL parser but getting nil/empty results instead of proper AST nodes.

### Investigation Steps
1. **Check `lua/tcl-lsp/parser/ast.lua`** - Verify TCL parser invocation
2. **Check error handling** - Errors may be swallowed
3. **Check JSON parsing** - TCL returns JSON, Lua must parse it
4. **Check type conversion** - TCL → JSON → Lua conversion

### Likely Issues

#### Issue 1A: Parser Not Found or Not Executing
```lua
-- In lua/tcl-lsp/parser/ast.lua
local function parse(code)
    -- Check if TCL parser exists
    local parser_path = find_parser()
    if not parser_path then
        return nil, "TCL parser not found"
    end
    
    -- Execute parser
    local result = execute_parser(parser_path, code)
    if not result then
        return nil, "Parser execution failed"
    end
end
```

#### Issue 1B: JSON Serialization Mismatch
```lua
-- TCL returns JSON string
-- Lua must parse it correctly
local json_str = execute_tcl_parser(code)
local ast = vim.json.decode(json_str)  -- May fail silently
```

#### Issue 1C: Error Swallowing
```lua
-- Current (bad):
local ok, result = pcall(parse_tcl, code)
return result  -- Returns nil on error

-- Fixed (good):
local ok, result = pcall(parse_tcl, code)
if not ok then
    return nil, result  -- Return error message
end
```

### Tests That Will Be Fixed
- ✅ Simple set with string value
- ✅ Simple set with numeric value  
- ✅ Simple variable set
- ✅ If statement parsing
- ✅ If-else statement
- ✅ Procedure with no args
- ✅ Procedure with args
- ✅ Nested procedures
- ✅ Upvar declaration
- ✅ Switch statement (if not already fixed)

**Expected Result:** 23/39 → ~33-35/39 passing

---

## 🎯 Priority 2: HIGH - Fix Type Conversions (4 tests)

**Time Estimate:** 1-2 hours  
**Impact:** Fixes type mismatch errors  
**Difficulty:** 🟢 Easy

### Problem
TCL returns numbers as Lua numbers, but tests expect strings. Also float precision issues with version numbers.

### Issue 2A: Number vs String
```tcl
# TCL parser returns:
dict set result value 42  # This becomes Lua number

# Test expects:
assert.equals("42", set_node.value)  # String!
```

**Solution Options:**
1. **Option A (Preferred):** Keep values as strings in TCL parser
2. **Option B:** Convert in Lua layer
3. **Option C:** Update test expectations

**Recommended:** Option A - Modify TCL parser to always quote literal values

```tcl
# In tcl/core/ast/parsers/variables.tcl
proc parse_set {cmd_text start_line end_line depth} {
    # ...
    set value [::tokenizer::get_token $cmd_text 2]
    
    # Keep value as string literal
    dict set result value $value  # Not [strip_outer $value]
}
```

### Issue 2B: Float Precision (Package Version)
```lua
-- Expected: "8.6"
-- Got: 8.5999999999999996447
```

**Solution:** Keep version as string, don't parse as number

```tcl
# In tcl/core/ast/parsers/packages.tcl
proc parse_package {cmd_text start_line end_line depth} {
    # ...
    set version [::tokenizer::get_token $cmd_text 3]
    
    # DON'T strip quotes - keep as literal string
    dict set result version $version
}
```

### Tests That Will Be Fixed
- ✅ Simple set with numeric value (42 vs "42")
- ✅ Package version (8.6 vs 8.5999...)
- ✅ Upvar level (1 vs "1")
- ✅ Any other number literals

**Expected Result:** 33/39 → 37/39 passing

---

## 🎯 Priority 3: MEDIUM - Fix Structure Issues (2 tests)

**Time Estimate:** 1 hour  
**Impact:** Final 2 tests  
**Difficulty:** 🟡 Medium

### Issue 3A: If-Elseif-Else Chain
```tcl
if {$x > 5} {
    ...
} elseif {$x > 3} {
    ...
} else {
    ...
}
# Current: elseif field missing or nil
# Expected: elseif = [{condition: ..., body: ...}]
```

**Check:** This might already be fixed in control_flow.tcl. Verify the Lua test expectations match TCL output.

### Issue 3B: Complex Procedure
```lua
-- Test: ast_spec.lua:580
-- Expected: 'proc'
-- Got: nil
```

This is likely a **Priority 1 issue** (bridge problem), not a structure issue.

### Tests That Will Be Fixed
- ✅ If-elseif-else chain
- ✅ Complex procedure with multiple constructs

**Expected Result:** 37/39 → 39/39 passing ✅

---

## 🎯 Priority 4: BONUS - Fix Command Substitution Edge Cases

**Time Estimate:** 30 minutes  
**Impact:** Polish, not critical  
**Difficulty:** 🟢 Easy

### Issue 4: Brackets in Quoted Strings
```tcl
set x "[test]"
# Current: Returns nil
# Expected: Parse correctly
```

This is likely **already fixed** in the TCL parser but failing due to Priority 1 bridge issue.

---

## 📋 Implementation Plan

### Phase 1: Debug the Bridge (Day 1 - 3 hours)
**Goal:** Understand why Lua gets nil from TCL

#### Steps:
1. Add extensive logging to `lua/tcl-lsp/parser/ast.lua`
2. Verify TCL parser is being called
3. Check if TCL returns valid JSON
4. Verify Lua JSON parsing
5. Fix any bridge issues found

**Testing:**
```bash
# Run one failing test with debug output
make test-unit 2>&1 | grep -A 10 "simple set with string"
```

**Expected Result:** Identify exact failure point in bridge

---

### Phase 2: Fix Type Conversions (Day 1-2 - 2 hours)
**Goal:** Make types consistent

#### Steps:
1. Update `variables.tcl` to preserve string literals
2. Update `packages.tcl` to keep version as string
3. Update any other parsers with number fields
4. Run tests to verify

**Testing:**
```bash
# Run specific failing tests
make test-unit 2>&1 | grep "numeric value"
make test-unit 2>&1 | grep "package require"
```

**Expected Result:** Type mismatch errors resolved

---

### Phase 3: Verify Structure (Day 2 - 1 hour)
**Goal:** Ensure AST structure matches expectations

#### Steps:
1. Check if-elseif-else parsing
2. Verify test expectations match TCL output
3. Update either code or tests as needed

**Testing:**
```bash
# Run full test suite
make test-unit
```

**Expected Result:** 39/39 tests passing ✅

---

## 🔍 Diagnostic Commands

### Check Lua-TCL Bridge
```lua
-- In lua/tcl-lsp/parser/ast.lua, add logging:
local function parse(code)
    print("=== PARSE CALLED ===")
    print("Code:", code)
    
    local result = call_tcl_parser(code)
    print("TCL Result:", vim.inspect(result))
    
    local ast = process_result(result)
    print("Final AST:", vim.inspect(ast))
    
    return ast
end
```

### Test TCL Parser Directly
```bash
# Verify TCL parser works standalone
echo 'set x 42' | tclsh tcl/core/ast/builder.tcl

# Should output valid JSON with AST
```

### Test Lua JSON Parsing
```lua
-- In Neovim:
:lua print(vim.json.encode({type="set", value=42}))
:lua print(vim.inspect(vim.json.decode('{"type":"set","value":42}')))
```

---

## 📊 Expected Progress

| Phase | Time | Tests Passing | Status |
|-------|------|---------------|--------|
| **Start** | - | 23/39 (59%) | Current |
| **Phase 1** | 3 hrs | 33-35/39 (87%) | Bridge fixed |
| **Phase 2** | 2 hrs | 37/39 (95%) | Types fixed |
| **Phase 3** | 1 hr | 39/39 (100%) ✅ | COMPLETE |
| **Total** | **6 hrs** | **100%** | 🎯 |

---

## ⚠️ Critical Notes

### 1. Don't Chase Individual Test Failures
The roadmap showed 96/105 passing, but current output shows 23/39. **This is a systemic bridge issue**, not individual test problems. Fix the bridge first!

### 2. TCL Parser Is Working
All 12/12 TCL test suites pass. The problem is **Lua can't access the TCL parser output**.

### 3. Focus on the Integration Layer
```
TCL Parser (✅ Works) → JSON Serialization (?) → Lua Parser (❌ Gets nil)
                         ^^^^^^^^^^^^^^^^^^^
                         THIS IS THE PROBLEM
```

### 4. Test Locally First
Before deploying any fixes, test the integration:
```bash
# Test TCL → JSON
echo 'set x 42' | tclsh tcl/core/ast/builder.tcl

# Test Lua → TCL → Lua
nvim --headless -c "lua require('tcl-lsp.parser.ast').parse('set x 42')" -c "qa"
```

---

## 🎯 Success Criteria

### Phase 1 Complete When:
- [ ] Lua can successfully call TCL parser
- [ ] Valid JSON is returned from TCL
- [ ] Lua can parse the JSON
- [ ] AST nodes are not nil
- [ ] 30+ tests passing

### Phase 2 Complete When:
- [ ] No type mismatch errors
- [ ] Numbers handled correctly
- [ ] Package versions are strings
- [ ] 37+ tests passing

### Phase 3 Complete When:
- [ ] All structure tests pass
- [ ] 39/39 tests passing ✅
- [ ] No regressions in TCL tests

---

## 🚀 Quick Start

### Immediate Actions (Next 30 min):
1. **Add debug logging** to `lua/tcl-lsp/parser/ast.lua`
2. **Run one failing test** and capture full output
3. **Identify** exact point of failure
4. **Document** findings

### Next Steps (Based on findings):
- If TCL not executing → Fix path/installation
- If JSON invalid → Fix TCL serialization
- If JSON parse fails → Fix Lua JSON handling
- If types wrong → Fix type conversion

---

## 📝 Files to Investigate

### Priority 1 (Bridge):
1. `lua/tcl-lsp/parser/ast.lua` - Main parser interface
2. `lua/tcl-lsp/parser/init.lua` - Parser initialization
3. `tcl/core/ast/builder.tcl` - TCL entry point
4. `tcl/core/ast/json.tcl` - JSON serialization

### Priority 2 (Types):
1. `tcl/core/ast/parsers/variables.tcl` - Variable parsing
2. `tcl/core/ast/parsers/packages.tcl` - Package parsing
3. `tcl/core/tokenizer.tcl` - Token handling

### Priority 3 (Structure):
1. `tcl/core/ast/parsers/control_flow.tcl` - If/elseif/else
2. `tests/lua/parser/ast_spec.lua` - Test expectations

---

## 💡 Key Insight

> **The TCL parser works perfectly. The problem is the Lua-TCL integration layer.**

This is actually **good news** because:
1. ✅ We don't need to rewrite the parser
2. ✅ The fix is localized to integration code
3. ✅ Should be faster to fix than parser bugs
4. ✅ Less risk of breaking working code

**Focus Area:** Get Lua to successfully call TCL and receive valid AST data.

---

**Next Step:** Start with Phase 1 - Debug the bridge! 🔍
