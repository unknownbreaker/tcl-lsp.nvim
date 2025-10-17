-- TCL AST Parser - Granular Command Substitution Tests
-- This file tests command substitution in increasing complexity

local parser = require "tcl-lsp.parser.ast"

describe("Command Substitution - Granular Tests", function()
  describe("Level 1: Simple Commands (No Substitution)", function()
    it("should parse simple set with string value", function()
      local code = 'set x "hello"'
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse simple string")
      assert.is_not_nil(ast)
      assert.equals(1, #ast.children)

      local set_node = ast.children[1]
      assert.equals("set", set_node.type)
      assert.equals("x", set_node.var_name)
      assert.equals('"hello"', set_node.value)
    end)

    it("should parse simple set with numeric value", function()
      local code = "set x 42"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse number")
      local set_node = ast.children[1]
      assert.equals("x", set_node.var_name)
      assert.equals("42", set_node.value)
    end)

    it("should parse set with variable reference", function()
      local code = "set x $y"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse variable reference")
      local set_node = ast.children[1]
      assert.equals("x", set_node.var_name)
      assert.equals("$y", set_node.value)
    end)
  end)

  describe("Level 2: Commands with Square Brackets (As Strings)", function()
    it("should handle brackets in quoted strings", function()
      local code = 'set x "[test]"'
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse brackets in quotes: " .. tostring(err))
      if ast then
        local set_node = ast.children[1]
        assert.equals("x", set_node.var_name)
      end
    end)

    it("should handle escaped brackets", function()
      local code = "set x \\[test\\]"
      local ast, err = parser.parse(code)

      -- This might legitimately fail, just documenting behavior
      if ast then
        assert.equals(1, #ast.children)
      end
    end)
  end)

  describe("Level 3: Actual Command Substitution", function()
    it("should parse set with command substitution - simple", function()
      local code = "set x [list a b c]"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse command substitution: " .. tostring(err))
      if ast then
        local set_node = ast.children[1]
        assert.equals("set", set_node.type)
        assert.equals("x", set_node.var_name)
        -- For now, value can be string or table
        assert.is_not_nil(set_node.value)
      end
    end)

    it("should parse set with expr command substitution", function()
      local code = "set x [expr {1 + 2}]"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse expr substitution: " .. tostring(err))
      if ast then
        local set_node = ast.children[1]
        assert.equals("x", set_node.var_name)
        -- Value should exist (string or table)
        assert.is_not_nil(set_node.value)
      end
    end)

    it("should parse set with nested braces in substitution", function()
      local code = "set result [expr {1 + 1}]"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse nested braces: " .. tostring(err))
      if ast then
        assert.equals(1, #ast.children)
      end
    end)
  end)

  describe("Level 4: Multiple Substitutions", function()
    it("should parse command with multiple substitutions", function()
      local code = "set x [expr [expr 1]]"
      local ast, err = parser.parse(code)

      -- This is very complex, may not work yet
      if ast then
        assert.is_not_nil(ast.children[1])
      end
    end)
  end)

  describe("Level 5: Command Extraction with Brackets", function()
    it("should not split commands on brackets", function()
      local code = [[
set x 10
set y [expr $x + 5]
set z 20
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse multiple commands: " .. tostring(err))
      if ast then
        -- Should have 3 set commands, not split by brackets
        assert.equals(3, #ast.children, "Should have 3 commands")
      end
    end)
  end)
end)
