-- tests/lua/features/formatting_spec.lua
-- Tests for formatting feature

describe("Formatting Feature", function()
  local formatting

  before_each(function()
    package.loaded["tcl-lsp.features.formatting"] = nil
    formatting = require("tcl-lsp.features.formatting")
  end)

  describe("setup", function()
    it("should register without error", function()
      local success = pcall(formatting.setup)
      assert.is_true(success)
    end)
  end)

  describe("format_code", function()
    it("should return empty string for empty input", function()
      local result = formatting.format_code("")
      assert.equals("", result)
    end)

    it("should return nil input unchanged", function()
      local result = formatting.format_code(nil)
      assert.is_nil(result)
    end)

    it("should remove trailing whitespace", function()
      local code = "proc foo {} {   \n    puts hello   \n}  "
      local result = formatting.format_code(code)
      assert.is_not_nil(result)
      -- No trailing whitespace on any line
      assert.is_nil(result:match("[ \t]+\n"))
      assert.is_nil(result:match("[ \t]+$"))
    end)

    it("should preserve blank lines", function()
      local code = "proc foo {} {\n\n    puts hello\n}"
      local result = formatting.format_code(code)
      assert.is_not_nil(result)
      -- Should still have a blank line
      assert.is_not_nil(result:match("\n\n"))
    end)

    it("should handle code without trailing newline", function()
      local code = "puts hello"
      local result = formatting.format_code(code)
      assert.equals("puts hello", result)
    end)

    it("should handle code with trailing newline", function()
      local code = "puts hello\n"
      local result = formatting.format_code(code)
      assert.equals("puts hello\n", result)
    end)
  end)

  describe("detect_indent", function()
    it("should detect 4-space indent", function()
      local code = "proc foo {} {\n    puts hello\n}"
      local style, size = formatting.detect_indent(code)
      assert.equals("spaces", style)
      assert.equals(4, size)
    end)

    it("should detect 2-space indent", function()
      local code = "proc foo {} {\n  puts hello\n}"
      local style, size = formatting.detect_indent(code)
      assert.equals("spaces", style)
      assert.equals(2, size)
    end)

    it("should detect tab indent", function()
      local code = "proc foo {} {\n\tputs hello\n}"
      local style, size = formatting.detect_indent(code)
      assert.equals("tabs", style)
      assert.equals(1, size)
    end)

    it("should default to 4 spaces for no indentation", function()
      local code = "puts hello"
      local style, size = formatting.detect_indent(code)
      assert.equals("spaces", style)
      assert.equals(4, size)
    end)

    it("should detect 2-space from multiple lines", function()
      local code = "proc foo {} {\n  line1\n  line2\n    nested\n}"
      local style, size = formatting.detect_indent(code)
      assert.equals("spaces", style)
      assert.equals(2, size)
    end)
  end)
end)
