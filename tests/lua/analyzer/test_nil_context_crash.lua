-- tests/lua/analyzer/test_nil_context_crash.lua
-- CRITICAL BUG REPRODUCTION: Nil context causes crash in find_in_index()
--
-- This is a minimal reproduction of a crash that occurs when:
-- 1. Parser fails to parse a file (returns nil AST)
-- 2. scope.get_context() returns nil
-- 3. definitions.find_in_index() is called with nil context
-- 4. CRASH: attempt to index nil value
--
-- Run with: nvim --headless --noplugin -u tests/minimal_init.lua -c "luafile tests/lua/analyzer/test_nil_context_crash.lua" -c "qa!"

print("========================================")
print("CRITICAL BUG TEST: Nil Context Crash")
print("========================================")
print()

-- Load the definitions module
local ok, definitions = pcall(require, "tcl-lsp.analyzer.definitions")
if not ok then
  print("ERROR: Could not load definitions module")
  print(definitions)
  os.exit(1)
end

print("Test 1: Call find_in_index() with nil context")
print("Expected: Should return nil gracefully")
io.write("Actual: ")

local success, result = pcall(function()
  return definitions.find_in_index("test_proc", nil)
end)

if success then
  print("✓ Did not crash (returned: " .. tostring(result) .. ")")
else
  print("✗ CRASHED with error:")
  print("  " .. tostring(result))
  print()
  print("BUG CONFIRMED: definitions.find_in_index() crashes on nil context!")
  print("Location: lua/tcl-lsp/analyzer/definitions.lua, line 49")
  print("Fix: Add nil check at function entry")
  os.exit(1)
end

print()

print("Test 2: Call find_in_index() with empty context")
print("Expected: Should return nil gracefully")
io.write("Actual: ")

success, result = pcall(function()
  return definitions.find_in_index("test_proc", {})
end)

if success then
  print("✓ Did not crash (returned: " .. tostring(result) .. ")")
else
  print("✗ CRASHED with error:")
  print("  " .. tostring(result))
  os.exit(1)
end

print()

print("Test 3: Call find_in_index() with malformed context")
print("Expected: Should handle gracefully")
io.write("Actual: ")

success, result = pcall(function()
  return definitions.find_in_index("test_proc", { invalid = "context" })
end)

if success then
  print("✓ Did not crash (returned: " .. tostring(result) .. ")")
else
  print("✗ CRASHED with error:")
  print("  " .. tostring(result))
  os.exit(1)
end

print()

print("Test 4: Call build_candidates() with nil context")
print("Expected: Should crash or handle gracefully")
io.write("Actual: ")

success, result = pcall(function()
  return definitions.build_candidates("test_proc", nil)
end)

if success then
  print("✓ Did not crash (returned table with " .. #result .. " items)")
else
  print("✗ CRASHED with error:")
  print("  " .. tostring(result))
  print()
  print("BUG CONFIRMED: build_candidates() crashes on nil context!")
  print("Location: lua/tcl-lsp/analyzer/definitions.lua, line 33")
  os.exit(1)
end

print()
print("========================================")
print("All tests passed!")
print("========================================")
print()
print("Note: If these tests pass, the bug may have been fixed.")
print("However, the bug exists in the original code and should")
print("be verified by code inspection.")
