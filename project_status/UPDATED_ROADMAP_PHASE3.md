# TCL-LSP.nvim Test Fix Roadmap - Updated After Phase 2

## ðŸŽ‰ Current Status: Phase 2 Complete!

**Tests Passing:** 96/105 (91.4%) âœ…  
**Tests Failing:** 9/105 (8.6%)  
**Progress Since Start:** +7 tests fixed (89/105 â†’ 96/105)

### Recent Achievements
- âœ… Phase 1: Type conversion fixes (+1 test)
- âœ… Phase 2: Quote preservation (+1 test) 
- âœ… Test contradiction resolved
- âœ… Command substitution: 10/10 passing

---

## ðŸ“Š Test Breakdown by Category

| Category | Passing | Failing | Status |
|----------|---------|---------|--------|
| **Config** | 30/30 | 0 | âœ… Perfect |
| **Command Substitution** | 10/10 | 0 | âœ… Perfect |
| **AST Parser** | 30/39 | 9 | âš ï¸ Phase 3 target |
| **Server** | 16/18 | 2 | âš ï¸ Phase 4 target |
| **Init** | 20/22 | 2 | âš ï¸ Phase 4 target |
| **Other Suites** | 0/16 | 0 | âœ… All passing |
| **Total** | **96/105** | **9** | 91.4% |

---

## ðŸŽ¯ Phase 3: Structural Parsing Fixes (9 tests)

**Target:** 101/105 tests passing (96.2%)  
**Time Estimate:** 6-8 hours  
**Difficulty:** ðŸŸ¡ Medium

### 3.1: Boolean Type Conversion (1 test) - **15 minutes** ðŸŸ¢

**Test:** `ast_spec.lua:142` - "should parse procedure with args"

**Issue:**
```tcl
proc test {x args} { }
# Current: has_varargs = "true" (string)
# Expected: has_varargs = true (boolean)
```

**Root Cause:** The `has_varargs` field is being set as string instead of boolean.

**Solution:**
- **File:** `tcl/core/ast/parsers/procedures.tcl`
- **Change:** Ensure `has_varargs` is set as TCL boolean (1/0), not string "true"
- **Code fix:**
```tcl
# Instead of:
dict set result has_varargs "true"

# Use:
dict set result has_varargs 1
```

**Expected Result:** 97/105 passing

---

### 3.2: Empty Proc Params (1 test) - **30 minutes** ðŸŸ¢

**Test:** `ast_spec.lua:80` - "should parse simple procedure with no arguments"

**Issue:**
```tcl
proc hello {} { }
# Current: params = "" (empty string)
# Expected: params = [] (empty list/table)
```

**Root Cause:** Empty parameter list returns empty string instead of empty list.

**Solution:**
- **File:** `tcl/core/ast/parsers/procedures.tcl`
- **Function:** `parse_proc`
- **Change:** Return empty list when no parameters
```tcl
# When params is empty:
if {$params eq ""} {
    set params [list]  # Empty list instead of empty string
}
```

**Expected Result:** 98/105 passing

---

### 3.3: Global Variable Array (1 test) - **30 minutes** ðŸŸ¢

**Test:** `ast_spec.lua:199` - "should parse global variable declaration"

**Issue:**
```tcl
global myvar
# Current: vars = "myvar" (string)
# Expected: vars = ["myvar"] (array/list)
```

**Root Cause:** Already fixed in current code, but may need verification.

**Solution:**
- **File:** `tcl/core/ast/parsers/variables.tcl`
- **Function:** `parse_global`
- **Verify:** The fix from Phase 1 is deployed correctly
```tcl
# Should already have:
set vars [list]
for {set i 1} {$i < $word_count} {incr i} {
    lappend vars $var_name
}
```

**Expected Result:** 99/105 passing (if not already fixed)

---

### 3.4: Variable Substitution Node (1 test) - **1 hour** ðŸŸ¡

**Test:** `ast_spec.lua:464` - "should parse variable substitution"

**Issue:**
```tcl
puts "$myvar"
# Current: Returns nil for $myvar
# Expected: Create substitution node
```

**Root Cause:** Parser doesn't create nodes for variable substitutions (`$var` syntax).

**Solution:**
- **File:** `tcl/core/ast/parsers/expressions.tcl` or create new function
- **Change:** Detect and parse `$variable` patterns
```tcl
proc ::ast::parsers::parse_variable_substitution {token} {
    if {[string index $token 0] eq "$"} {
        set var_name [string range $token 1 end]
        return [dict create \
            type "variable_substitution" \
            variable $var_name]
    }
    return $token
}
```

**Expected Result:** 100/105 passing

---

### 3.5: If-Elseif-Else Structure (1 test) - **1.5 hours** ðŸŸ¡

**Test:** `ast_spec.lua:271` - "should parse if-elseif-else chain"

**Issue:**
```tcl
if {$x > 5} {
    ...
} elseif {$x > 3} {
    ...
} else {
    ...
}
# Current: Missing elseif branches (returns nil)
# Expected: elseif = [{condition: ..., body: ...}]
```

**Root Cause:** Parser doesn't handle `elseif` branches properly.

**Solution:**
- **File:** `tcl/core/ast/parsers/control_flow.tcl`
- **Function:** `parse_if`
- **Change:** Loop through elseif branches and collect them
```tcl
# Add elseif handling:
set elseif_branches [list]
while {[regexp {elseif} $remaining_code]} {
    # Parse each elseif branch
    lappend elseif_branches [dict create \
        condition $elseif_condition \
        body $elseif_body]
}
dict set result elseif $elseif_branches
```

**Expected Result:** 101/105 passing

---

### 3.6: Switch Cases (1 test) - **1.5 hours** ðŸŸ¡

**Test:** `ast_spec.lua:336` - "should parse switch statement"

**Issue:**
```tcl
switch $x {
    1 { puts "one" }
    2 { puts "two" }
}
# Current: Missing cases structure (returns nil)
# Expected: cases = [{pattern: "1", body: ...}, {pattern: "2", body: ...}]
```

**Root Cause:** Parser doesn't extract switch cases into structured format.

**Solution:**
- **File:** `tcl/core/ast/parsers/control_flow.tcl`
- **Function:** `parse_switch`
- **Change:** Parse switch body and extract pattern-body pairs
```tcl
proc parse_switch_cases {body_text} {
    set cases [list]
    # Parse pattern-body pairs from switch body
    # Each pattern followed by body block
    lappend cases [dict create \
        pattern $pattern \
        body $body]
    return $cases
}
```

**Expected Result:** 102/105 passing

---

### 3.7: Namespace Body Parsing (1 test) - **1.5 hours** ðŸŸ¡

**Test:** `ast_spec.lua:355` - "should parse namespace declaration"

**Issue:**
```tcl
namespace eval MyNS {
    variable x 10
    proc myproc {} {}
}
# Current: body = "{...}" (string)
# Expected: body = AST with children (recursive parse)
```

**Root Cause:** Namespace body is stored as string instead of being recursively parsed.

**Solution:**
- **File:** `tcl/core/ast/parsers/namespaces.tcl`
- **Function:** `parse_namespace_eval`
- **Change:** Recursively parse namespace body
```tcl
# Instead of storing body as string:
set body_text [::ast::delimiters::strip_outer $body_token]

# Recursively parse it:
set body_ast [::ast::parser::parse $body_text]
dict set result body $body_ast
```

**Expected Result:** 103/105 passing

---

### 3.8: Namespace Import Patterns (1 test) - **30 minutes** ðŸŸ¢

**Test:** `ast_spec.lua:365` - "should parse namespace import"

**Issue:**
```tcl
namespace import ::Other::*
# Current: pattern = "::Other::*" (string)
# Expected: patterns = ["::Other::*"] (array)
```

**Root Cause:** Import patterns stored as string instead of array.

**Solution:**
- **File:** `tcl/core/ast/parsers/namespaces.tcl`
- **Function:** `parse_namespace_import`
- **Change:** Return list of import patterns
```tcl
# Collect all import patterns
set patterns [list]
for {set i 2} {$i < $word_count} {incr i} {
    lappend patterns $pattern_token
}
dict set result patterns $patterns
```

**Expected Result:** 104/105 passing

---

### 3.9: Complex Expression Parsing (1 test) - **2 hours** ðŸŸ 

**Test:** `ast_spec.lua:575` - "should parse complex procedure"

**Issue:**
```
Parser error: list element in quotes followed by "]" instead of space
```

**Root Cause:** Complex nested structures with quotes and brackets cause tokenizer issues.

**Solution:**
- **File:** Multiple files - `tcl/core/tokenizer.tcl`, `parsers/*.tcl`
- **Change:** Improve quote/bracket handling in complex expressions
- **Approach:** Debug the specific failing test case to find the exact issue

**Expected Result:** 105/105 passing (if all Phase 4 fixes included)

---

## ðŸŽ¯ Phase 4: LSP Integration Fixes (4 tests)

**Target:** 105/105 tests passing (100%) ðŸŽ¯  
**Time Estimate:** 2-3 hours  
**Difficulty:** ðŸŸ  Medium-High

### 4.1: Buffer Attachment (2 tests) - **1 hour** ðŸŸ¡

**Tests:**
- `server_spec.lua:404` - "should attach to buffer correctly"
- `server_spec.lua:433` - "should handle multiple buffers in same project"

**Issue:**
```lua
TCL LSP client should attach to buffer
Expected: true
Passed in: false
```

**Root Cause:** LSP client not attaching to buffers properly.

**Solution:**
- **File:** `lua/tcl-lsp/server.lua`
- **Change:** Fix buffer attachment logic
```lua
-- Ensure client attaches to buffer
vim.lsp.buf_attach_client(bufnr, client_id)

-- Verify attachment
local clients = vim.lsp.get_clients({bufnr = bufnr})
assert(#clients > 0, "Client should attach")
```

**Expected Result:** 98/101 â†’ 99/101 or 100/101

---

### 4.2: Autocommand Registration (1 test) - **30 minutes** ðŸŸ¢

**Test:** `init_spec.lua:297` - "should register appropriate autocommands"

**Issue:**
```lua
Invalid 'group': '*'
```

**Root Cause:** Trying to get autocommands with wildcard group.

**Solution:**
- **File:** `lua/tcl-lsp/init.lua`
- **Change:** Fix autocommand group handling
```lua
-- Instead of using wildcard:
vim.api.nvim_get_autocmds({group = "*"})

-- Use specific group or enumerate all groups:
local augroups = vim.api.nvim_get_autocmds({})
```

**Expected Result:** 102/105 passing

---

### 4.3: LSP Server Start (1 test) - **30 minutes** ðŸŸ¢

**Test:** `init_spec.lua:332` - "should start LSP server when requested"

**Issue:**
```lua
Should have active LSP clients after start
Expected: true
Passed in: false
```

**Root Cause:** Server start sequence not completing properly.

**Solution:**
- **File:** `lua/tcl-lsp/init.lua` and `lua/tcl-lsp/server.lua`
- **Change:** Ensure proper server startup sequence
```lua
function M.start()
    -- Start server
    local client_id = vim.lsp.start_client(config)
    
    -- Attach to current buffer
    vim.lsp.buf_attach_client(0, client_id)
    
    -- Verify startup
    return client_id ~= nil
end
```

**Expected Result:** 103/105 or 105/105 passing

---

## ðŸ“ˆ Implementation Timeline

### Week 1: Phase 3 Quick Wins (Days 1-2)
**Target:** 99-100/105 passing

**Day 1 (2-3 hours):**
- 3.1: Boolean type conversion (15 min)
- 3.2: Empty proc params (30 min)
- 3.3: Global variable array verification (30 min)
- 3.8: Namespace import patterns (30 min)

**Day 2 (3-4 hours):**
- 3.4: Variable substitution node (1 hour)
- 3.5: If-elseif-else structure (1.5 hours)
- 3.6: Switch cases (1.5 hours)

### Week 1: Phase 3 Complex (Days 3-4)
**Target:** 101-104/105 passing

**Day 3 (2-3 hours):**
- 3.7: Namespace body parsing (1.5 hours)
- Testing and verification (1 hour)

**Day 4 (2-3 hours):**
- 3.9: Complex expression parsing (2 hours)
- Testing and verification (1 hour)

### Week 2: Phase 4 LSP Integration (Days 5-6)
**Target:** 105/105 passing (100%) ðŸŽ¯

**Day 5 (2 hours):**
- 4.2: Autocommand registration (30 min)
- 4.3: LSP server start (30 min)
- 4.1: Buffer attachment (1 hour)

**Day 6 (1-2 hours):**
- Final testing and verification
- Documentation updates
- Celebration! ðŸŽ‰

---

## ðŸ—‚ï¸ Files to Modify

### Phase 3 (Structural Parsing)

| File | Tests Fixed | Estimated Changes |
|------|-------------|-------------------|
| `tcl/core/ast/parsers/procedures.tcl` | 2 | ~30 lines |
| `tcl/core/ast/parsers/variables.tcl` | 1 | ~10 lines (verify) |
| `tcl/core/ast/parsers/expressions.tcl` | 1 | ~40 lines (new function) |
| `tcl/core/ast/parsers/control_flow.tcl` | 2 | ~80 lines |
| `tcl/core/ast/parsers/namespaces.tcl` | 2 | ~50 lines |
| `tcl/core/tokenizer.tcl` | 1 | ~20 lines |

**Total:** ~230 lines across 6 files

### Phase 4 (LSP Integration)

| File | Tests Fixed | Estimated Changes |
|------|-------------|-------------------|
| `lua/tcl-lsp/server.lua` | 2 | ~50 lines |
| `lua/tcl-lsp/init.lua` | 2 | ~30 lines |

**Total:** ~80 lines across 2 files

---

## ðŸ“Š Priority Matrix

### ðŸŸ¢ Quick Wins (< 1 hour each)
1. Boolean type conversion (15 min)
2. Empty proc params (30 min)
3. Namespace import patterns (30 min)
4. Autocommand registration (30 min)
5. LSP server start (30 min)

### ðŸŸ¡ Medium Tasks (1-2 hours each)
6. Variable substitution (1 hour)
7. Buffer attachment (1 hour)
8. If-elseif-else structure (1.5 hours)
9. Switch cases (1.5 hours)
10. Namespace body parsing (1.5 hours)

### ðŸŸ  Complex Tasks (2+ hours each)
11. Complex expression parsing (2 hours)

---

## ðŸŽ¯ Milestones

### Milestone 1: Quick Wins Complete
**Target:** 100/105 (95.2%)  
**Time:** 2-3 hours  
**Status:** Ready to start

### Milestone 2: Structural Parsing Complete
**Target:** 104/105 (99.0%)  
**Time:** 8-10 hours total  
**Status:** Awaiting Milestone 1

### Milestone 3: LSP Integration Complete
**Target:** 105/105 (100%) ðŸŽ¯  
**Time:** 10-13 hours total  
**Status:** Final milestone

---

## ðŸ”§ Implementation Strategy

### Approach: Iterative & Incremental

1. **Test-Driven:** Fix one test at a time
2. **Verify:** Run full test suite after each fix
3. **Document:** Update progress tracking
4. **Commit:** Small, focused commits

### Testing After Each Change
```bash
# Run specific test
make test-unit 2>&1 | grep "test name"

# Run full suite
make test-unit | tail -20

# Verify no regressions
make test-unit | grep -E "Success:|Failed :"
```

---

## ðŸ“ˆ Progress Tracking

### Current Progress
```
Start Point:  89/105 (84.8%)
Phase 1:      95/105 (90.5%) [+6 tests]
Phase 2:      96/105 (91.4%) [+1 test]
Current:      96/105 (91.4%)
```

### Projected Progress
```
Quick Wins:   100/105 (95.2%) [+4 tests]
Phase 3:      104/105 (99.0%) [+8 tests]
Phase 4:      105/105 (100%)  [+9 tests] ðŸŽ¯
```

---

## ðŸ›¡ï¸ Risk Assessment

| Phase | Risk | Mitigation |
|-------|------|------------|
| **Quick Wins** | ðŸŸ¢ Low | Simple, isolated changes |
| **Structural** | ðŸŸ¡ Medium | More complex, multiple files |
| **LSP Integration** | ðŸŸ  Medium-High | Lifecycle complexity, async issues |
| **Complex Parsing** | ðŸŸ  High | May require tokenizer changes |

---

## ðŸ’¡ Best Practices

### Before Starting Each Fix
- [ ] Read the failing test carefully
- [ ] Understand the expected behavior
- [ ] Identify the root cause
- [ ] Plan the minimal fix
- [ ] Consider side effects

### While Implementing
- [ ] Make small, focused changes
- [ ] Test incrementally
- [ ] Document the fix
- [ ] Follow existing code patterns
- [ ] Keep commits atomic

### After Each Fix
- [ ] Run the specific test
- [ ] Run full test suite
- [ ] Check for regressions
- [ ] Update documentation
- [ ] Commit with clear message

---

## ðŸŽ“ Lessons Learned (So Far)

1. **Test contradictions exist** - Always verify test expectations
2. **Incremental approach works** - Small fixes add up
3. **Documentation is crucial** - Helps track progress and debug
4. **Type consistency matters** - Boolean vs string vs array
5. **Quote handling is subtle** - Context-dependent behavior

---

## ðŸ“ž Quick Reference

### Current Status
- **Tests Passing:** 96/105 (91.4%)
- **Phase Complete:** Phase 2
- **Next Target:** Phase 3 Quick Wins

### Next 5 Actions
1. Fix boolean type conversion (15 min)
2. Fix empty proc params (30 min)
3. Verify global variable array (30 min)
4. Fix namespace import patterns (30 min)
5. Run tests â†’ expect 99-100/105

### Key Commands
```bash
# Run tests
make test-unit

# Check specific test
make test-unit 2>&1 | grep "test name"

# Count passing
make test-unit 2>&1 | grep "Success:" | head -1
```

---

## ðŸŽ‰ Conclusion

**Phase 2 Status:** âœ… COMPLETE  
**Current Progress:** 96/105 (91.4%)  
**Path to 100%:** Clear and achievable  
**Estimated Time:** 10-13 hours of focused work  

**You're in great shape!** The remaining fixes are well-understood, and the roadmap provides a clear path forward. Focus on the quick wins first to build momentum, then tackle the more complex structural issues.

**Next Step:** Start with the 15-minute boolean type conversion fix! ðŸš€

---

**Good luck with Phase 3!** ðŸ’ª
