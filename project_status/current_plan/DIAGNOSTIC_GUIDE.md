# Quick Diagnostic Guide

## 🔍 Immediate Investigation Steps

### Step 1: Test TCL Parser Directly (2 min)
```bash
# Test if TCL parser works standalone
echo 'set x 42' | tclsh tcl/core/ast/builder.tcl

# Expected output: Valid JSON with AST structure
# If this fails: TCL parser is broken (but tests say it works?)
# If this works: Problem is in Lua bridge
```

### Step 2: Check Lua Parser File (5 min)
```bash
# Find the Lua parser file
find . -name "ast.lua" -path "*/parser/*"

# Check if it exists and has content
cat lua/tcl-lsp/parser/ast.lua | head -50
```

### Step 3: Add Debug Logging (10 min)
Add this to `lua/tcl-lsp/parser/ast.lua`:

```lua
-- At the top of the parse() function
local function parse(code, opts)
    print("=== PARSE DEBUG ===")
    print("Input code:", code)
    print("Input length:", #code)
    
    -- Find where TCL parser is called
    local tcl_result = call_tcl_parser(code)  -- Whatever the actual function is
    
    print("TCL result type:", type(tcl_result))
    print("TCL result:", vim.inspect(tcl_result))
    
    if not tcl_result then
        print("ERROR: TCL returned nil!")
        return nil, "TCL parser returned nil"
    end
    
    -- Continue with normal parsing...
end
```

### Step 4: Run One Failing Test (5 min)
```bash
# Run just one test to see debug output
nvim --headless --noplugin -u tests/minimal_init.lua \
    -c "lua require('plenary.busted').run('tests/lua/parser/command_substitution_spec.lua')" \
    -c "qa!" 2>&1 | less

# Look for:
# - "PARSE DEBUG" messages
# - "TCL result" output
# - Error messages
```

---

## 🎯 Likely Root Causes (in order)

### 1. TCL Parser Path Not Found (60% probability)
**Symptom:** Lua can't find tcl/core/ast/builder.tcl  
**Check:**
```lua
-- In lua/tcl-lsp/parser/ast.lua
local parser_path = find_tcl_parser()
print("Parser path:", parser_path)  -- Is this nil?
```

**Fix:**
```lua
-- Make sure path resolution works
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
local parser_path = script_path .. "../../../tcl/core/ast/builder.tcl"
```

### 2. TCL Execution Fails (25% probability)
**Symptom:** `tclsh` command not found or errors  
**Check:**
```bash
which tclsh
tclsh --version
```

**Fix:**
```lua
-- Add error checking
local handle = io.popen("tclsh " .. parser_path .. " 2>&1")
local result = handle:read("*a")
local success = handle:close()

if not success then
    print("ERROR: tclsh execution failed")
    print("Output:", result)
end
```

### 3. JSON Parsing Fails (10% probability)
**Symptom:** TCL returns valid JSON but Lua can't parse it  
**Check:**
```lua
local json_str = get_from_tcl()
print("JSON string:", json_str)

local ok, ast = pcall(vim.json.decode, json_str)
if not ok then
    print("JSON parse error:", ast)
end
```

**Fix:**
```lua
-- Add better error handling
local ok, ast = pcall(vim.json.decode, json_str)
if not ok then
    return nil, "JSON parse error: " .. tostring(ast)
end
```

### 4. Wrong Function Being Called (5% probability)
**Symptom:** Tests call wrong parser function  
**Check:**
```lua
-- In test file
local parser = require "tcl-lsp.parser.ast"
print("Parser module:", vim.inspect(parser))
print("Parse function:", type(parser.parse))
```

---

## 🔧 Quick Fixes to Try

### Fix 1: Hardcode a Test Case
```lua
-- In lua/tcl-lsp/parser/ast.lua
local function parse(code, opts)
    -- TEMPORARY: Return hardcoded AST for testing
    if code == 'set x 42' then
        return {
            type = "root",
            children = {
                {
                    type = "set",
                    var_name = "x",
                    value = "42",
                    range = {start = {line = 1, character = 1}, ["end"] = {line = 1, character = 10}},
                    depth = 0
                }
            }
        }
    end
    
    -- Continue with normal parsing...
end
```

**If this makes tests pass:** Bridge is broken, TCL not being called  
**If tests still fail:** Test expectations or structure wrong

### Fix 2: Bypass TCL, Use Pure Lua
```lua
-- Quick Lua parser for testing
local function simple_parse(code)
    if code:match("^set%s+(%w+)%s+(.+)$") then
        local var, val = code:match("^set%s+(%w+)%s+(.+)$")
        return {
            type = "root",
            children = {{type = "set", var_name = var, value = val}}
        }
    end
    return {type = "root", children = {}}
end
```

### Fix 3: Test JSON Serialization
```bash
# Create test file
cat > /tmp/test.tcl << 'EOF'
set x 42
EOF

# Run TCL parser directly
tclsh tcl/core/ast/builder.tcl < /tmp/test.tcl

# Output should be valid JSON
```

---

## 📊 Decision Tree

```
Start: Test failing with nil return
↓
Q: Does `tclsh tcl/core/ast/builder.tcl` work from command line?
├─ NO → Fix TCL parser installation/path
└─ YES ↓
   Q: Does Lua find the TCL parser file?
   ├─ NO → Fix path resolution in Lua
   └─ YES ↓
      Q: Does TCL return valid JSON when called from Lua?
      ├─ NO → Fix TCL execution/JSON serialization
      └─ YES ↓
         Q: Does Lua successfully parse the JSON?
         ├─ NO → Fix JSON parsing in Lua
         └─ YES ↓
            Q: Is AST structure correct?
            ├─ NO → Fix AST structure/test expectations
            └─ YES → It works! 🎉
```

---

## 📝 Investigation Checklist

Copy this to track your progress:

```
[ ] Step 1: Confirmed TCL parser works standalone
[ ] Step 2: Found Lua parser file location
[ ] Step 3: Added debug logging to parse() function
[ ] Step 4: Ran one test and captured output
[ ] Step 5: Identified which root cause applies
[ ] Step 6: Applied appropriate fix
[ ] Step 7: Verified fix with multiple tests
[ ] Step 8: Removed debug logging
[ ] Step 9: Ran full test suite
[ ] Step 10: Documented findings
```

---

## 🚀 Expected Timeline

- **Investigation:** 15-30 minutes
- **Fix implementation:** 1-2 hours
- **Testing & verification:** 30 minutes
- **Total:** 2-3 hours

---

## 💡 Key Files to Check

1. **`lua/tcl-lsp/parser/ast.lua`** - Main parser interface
2. **`lua/tcl-lsp/parser/init.lua`** - Parser initialization  
3. **`tcl/core/ast/builder.tcl`** - TCL parser entry point
4. **`tests/lua/parser/ast_spec.lua`** - Test file
5. **`tests/minimal_init.lua`** - Test setup

---

## ✅ Success Indicators

You'll know it's fixed when:
- Debug logs show valid JSON from TCL
- Debug logs show parsed AST in Lua
- Tests print actual values instead of nil
- More tests start passing (23 → 30+)

---

**Start here:** Run Step 1 (test TCL parser) right now! ⏱️
