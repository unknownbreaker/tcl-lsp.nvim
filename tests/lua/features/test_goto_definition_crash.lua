-- tests/lua/features/test_goto_definition_crash.lua
-- CRITICAL BUG REPRODUCTION: Go-to-definition crashes on malformed TCL file
--
-- Scenario:
-- 1. User opens a TCL file with unclosed braces
-- 2. Parser fails and returns nil AST
-- 3. User presses 'gd' to go to definition
-- 4. CRASH: nil pointer dereference
--
-- Run with: nvim --headless --noplugin -u tests/minimal_init.lua -c "luafile tests/lua/features/test_goto_definition_crash.lua" -c "qa!"

print("========================================")
print("BUG REPRODUCTION: Go-to-Definition Crash")
print("========================================")
print()

-- Create a temp file with malformed TCL code
local temp_file = vim.fn.tempname() .. ".tcl"
local f = io.open(temp_file, "w")
f:write([[
proc test {} {
  puts "hello"
  # Missing closing brace!
]])
f:close()

print("Created malformed TCL file: " .. temp_file)
print("Content:")
print("  proc test {} {")
print("    puts \"hello\"")
print("    # Missing closing brace!")
print()

-- Load the file in a buffer
vim.cmd("edit " .. temp_file)
local bufnr = vim.api.nvim_get_current_buf()

print("Buffer loaded: " .. bufnr)
print()

-- Try to go to definition on line 1, column 6 (on word "test")
print("Test: Trigger go-to-definition on word 'test'")
print("Expected: Should return nil gracefully (syntax error)")
io.write("Actual: ")

local definition = require("tcl-lsp.features.definition")

-- This should NOT crash
local success, result = pcall(function()
  return definition.handle_definition(bufnr, 0, 6)  -- Line 1, col 6 (0-indexed)
end)

if success then
  print("✓ Did not crash (returned: " .. tostring(result) .. ")")
  print()
  print("RESULT: Bug may be fixed or not triggered in this scenario")
else
  print("✗ CRASHED with error:")
  print("  " .. tostring(result))
  print()
  print("BUG CONFIRMED: Go-to-definition crashes on malformed TCL!")
  print("Root cause: nil context passed to find_in_index()")

  -- Clean up
  vim.fn.delete(temp_file)
  os.exit(1)
end

-- Clean up
vim.fn.delete(temp_file)

print("========================================")
print("Test Complete")
print("========================================")
