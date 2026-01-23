-- tests/lua/parser/adversarial_spec.lua
-- ADVERSARIAL TESTS - Breaking the Lua-TCL parser bridge
-- Note: Parser has a 10-second timeout to prevent hangs on malicious input

describe("Parser Adversarial Tests", function()
  local parser = require("tcl-lsp.parser")

  -- Helper to check result is valid (either AST or error, not hang)
  local function assert_completes(ast, err)
    -- Test passes if we got any result (AST or error) without hanging
    assert.is_true(ast ~= nil or err ~= nil, "Parser should return AST or error, not hang")
  end

  describe("ATTACK 1: Empty and nil inputs", function()
    it("should handle nil code", function()
      local ast, err = parser.parse(nil)
      -- Should return empty AST, not crash
      assert.is_not_nil(ast)
      assert.equals("root", ast.type)
    end)

    it("should handle empty string", function()
      local ast, err = parser.parse("")
      assert.is_not_nil(ast)
      assert.equals("root", ast.type)
    end)

    it("should handle only whitespace", function()
      local ast, err = parser.parse("   \t\n   ")
      assert.is_not_nil(ast)
      assert.equals("root", ast.type)
    end)

    it("should handle only comments", function()
      local ast, err = parser.parse("# just a comment\n# another comment")
      assert.is_not_nil(ast)
    end)
  end)

  describe("ATTACK 2: Malformed TCL syntax", function()
    it("should handle unclosed braces", function()
      local ast, err = parser.parse("proc test {} { puts hello")
      -- Should return error, not crash
      assert.is_nil(ast)
      assert.is_not_nil(err)
    end)

    it("should handle unclosed quotes", function()
      local ast, err = parser.parse('set x "unclosed')
      assert.is_nil(ast)
      assert.is_not_nil(err)
    end)

    it("should handle unclosed brackets", function()
      local ast, err = parser.parse("set x [expr 1 + 2")
      assert.is_nil(ast)
      assert.is_not_nil(err)
    end)

    it("should handle completely invalid syntax", function()
      local ast, err = parser.parse("}{][}{")
      assert.is_nil(ast)
      assert.is_not_nil(err)
    end)
  end)

  describe("ATTACK 3: Control characters and unicode", function()
    it("should handle null bytes", function()
      local code = "set x hello\x00world"
      local ast, err = parser.parse(code)
      -- Should not crash
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle control characters", function()
      local code = "set x \x01\x02\x03"
      local ast, err = parser.parse(code)
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle emoji in code", function()
      local code = 'proc test {} { puts "🔥🔥🔥" }'
      local ast, err = parser.parse(code)
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle right-to-left unicode", function()
      -- U+202E Right-to-Left Override (using raw bytes for LuaJIT compatibility)
      local code = 'set x "' .. string.char(0xE2, 0x80, 0xAE) .. 'evil"'
      local ast, err = parser.parse(code)
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle zero-width characters", function()
      -- U+200B Zero Width Space (using raw bytes for LuaJIT compatibility)
      local code = 'set x "test' .. string.char(0xE2, 0x80, 0x8B) .. 'value"'
      local ast, err = parser.parse(code)
      assert.is_true(ast ~= nil or err ~= nil)
    end)
  end)

  describe("ATTACK 4: Large inputs (resource exhaustion)", function()
    -- Note: Parser has 10-second timeout to prevent hangs

    it("should handle 100KB of code or timeout gracefully", function()
      local code = string.rep("set x 1\n", 10000) -- ~100KB
      local ast, err = parser.parse(code)
      -- Should complete or timeout, never hang
      assert_completes(ast, err)
    end)

    it("should handle deeply nested structures or timeout", function()
      -- 100 levels of braces - may cause parser issues
      local code = "set x " .. string.rep("{", 100) .. "deep" .. string.rep("}", 100)
      local ast, err = parser.parse(code)
      assert_completes(ast, err)
    end)

    it("should handle very long single line or timeout", function()
      local code = "set x " .. string.rep("a", 100000)
      local ast, err = parser.parse(code)
      assert_completes(ast, err)
    end)

    it("should handle many procs or timeout", function()
      local procs = {}
      for i = 1, 1000 do
        table.insert(procs, string.format("proc test%d {} { puts %d }", i, i))
      end
      local code = table.concat(procs, "\n")
      local ast, err = parser.parse(code)
      assert_completes(ast, err)
    end)
  end)

  describe("ATTACK 5: Edge case filenames", function()
    it("should handle nil filepath", function()
      local ast, err = parser.parse("set x 1", nil)
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle empty filepath", function()
      local ast, err = parser.parse("set x 1", "")
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle filepath with unicode", function()
      local ast, err = parser.parse("set x 1", "/tmp/file🔥.tcl")
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle filepath with spaces", function()
      local ast, err = parser.parse("set x 1", "/tmp/my file.tcl")
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle very long filepath", function()
      local long_path = "/tmp/" .. string.rep("a", 10000) .. ".tcl"
      local ast, err = parser.parse("set x 1", long_path)
      assert.is_true(ast ~= nil or err ~= nil)
    end)
  end)

  describe("ATTACK 6: AST structure edge cases", function()
    it("should handle code with only comments", function()
      local code = "# comment 1\n# comment 2\n# comment 3"
      local ast, err = parser.parse(code)
      assert.is_not_nil(ast)
      assert.equals("root", ast.type)
      -- Should have empty children or only comments
    end)

    it("should handle mixed valid and invalid commands", function()
      local code = "set x 1\nINVALID_CMD\nset y 2"
      local ast, err = parser.parse(code)
      -- Should parse what it can
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle TCL with embedded null commands", function()
      local code = "set x 1\n\n\n\nset y 2"
      local ast, err = parser.parse(code)
      assert.is_not_nil(ast)
    end)
  end)

  describe("ATTACK 7: Special TCL constructs", function()
    it("should handle unescaped dollar signs", function()
      local code = "set x $undefined"
      local ast, err = parser.parse(code)
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle command substitution", function()
      local code = "set x [expr 1 + [expr 2 + 3]]"
      local ast, err = parser.parse(code)
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle backslash continuation", function()
      local code = "set x hello\\\nworld"
      local ast, err = parser.parse(code)
      assert.is_true(ast ~= nil or err ~= nil)
    end)

    it("should handle semicolon command separator", function()
      local code = "set x 1; set y 2; set z 3"
      local ast, err = parser.parse(code)
      assert.is_true(ast ~= nil or err ~= nil)
    end)
  end)

  describe("ATTACK 8: Race conditions and state", function()
    it("should handle concurrent parse calls", function()
      local code1 = "proc test1 {} { puts 1 }"
      local code2 = "proc test2 {} { puts 2 }"

      -- Parse both at the same time
      local ast1, err1 = parser.parse(code1, "file1.tcl")
      local ast2, err2 = parser.parse(code2, "file2.tcl")

      -- Both should succeed
      assert.is_not_nil(ast1)
      assert.is_not_nil(ast2)

      -- Should have filepath (uses temp file, so just check it exists)
      assert.is_not_nil(ast1.filepath)
      assert.is_not_nil(ast2.filepath)
    end)

    it("should handle parse after error", function()
      -- First parse with error
      local ast1, err1 = parser.parse("invalid {{{")
      assert.is_nil(ast1)

      -- Second parse should work
      local ast2, err2 = parser.parse("set x 1")
      assert.is_not_nil(ast2)
      assert.equals("root", ast2.type)
    end)

    it("should handle repeated parsing of same code", function()
      local code = "proc test {} { puts hello }"

      for i = 1, 10 do
        local ast, err = parser.parse(code, string.format("file%d.tcl", i))
        assert.is_not_nil(ast)
        -- Parser uses temp file, so just verify we get a valid AST each time
        assert.equals("root", ast.type)
      end
    end)
  end)

  describe("ATTACK 9: JSON parsing edge cases", function()
    it("should handle AST with special characters in strings", function()
      local code = 'set x "line1\\nline2\\ttab\\r\\n"'
      local ast, err = parser.parse(code)
      assert.is_not_nil(ast)
      -- AST should be valid JSON-serializable
    end)

    it("should handle AST with nested quotes", function()
      local code = 'set x "say \\"hello\\""'
      local ast, err = parser.parse(code)
      assert.is_not_nil(ast)
    end)

    it("should handle AST with backslashes", function()
      local code = 'set path "C:\\\\Users\\\\test"'
      local ast, err = parser.parse(code)
      assert.is_not_nil(ast)
    end)
  end)

  describe("ATTACK 10: Error message quality", function()
    it("should provide helpful error for unclosed brace", function()
      local ast, err = parser.parse("proc test {} { puts hello")
      assert.is_nil(ast)
      assert.is_not_nil(err)
      assert.is_string(err)
      assert.is_true(#err > 0, "Error message should not be empty")
    end)

    it("should provide helpful error for syntax error", function()
      local ast, err = parser.parse("}{][")
      assert.is_nil(ast)
      assert.is_not_nil(err)
      assert.is_string(err)
    end)

    it("should not expose internal paths in errors", function()
      local ast, err = parser.parse("invalid syntax")
      if err then
        -- Error should not contain absolute paths to plugin internals
        assert.is_false(err:match("/Users/") ~= nil, "Error contains absolute path")
        assert.is_false(err:match("/home/") ~= nil, "Error contains absolute path")
      end
    end)
  end)
end)
