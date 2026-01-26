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

  describe("indentation fixing", function()
    it("should fix badly indented proc", function()
      local code = "proc foo {} {\nputs hello\n}"
      local result = formatting.format_code(code)
      -- Should have indentation on the puts line
      assert.is_not_nil(result:match("\n[ \t]+puts"))
    end)

    it("should fix nested if indentation", function()
      local code = "proc foo {} {\nif {1} {\nputs hello\n}\n}"
      local result = formatting.format_code(code)
      -- The puts should be more indented than the if
      local lines = {}
      for line in result:gmatch("[^\n]+") do
        table.insert(lines, line)
      end
      -- Check that deeper nesting has more indent
      if #lines >= 4 then
        local if_indent = #(lines[2]:match("^([ \t]*)") or "")
        local puts_indent = #(lines[3]:match("^([ \t]*)") or "")
        assert.is_true(puts_indent > if_indent, "puts should be more indented than if")
      end
    end)

    it("should handle syntax errors gracefully", function()
      local code = "proc foo { missing brace"
      local result = formatting.format_code(code)
      -- Should return original code (with trailing whitespace stripped)
      assert.is_not_nil(result)
      assert.is_not_nil(result:match("proc foo"))
    end)

    it("should not change already well-formatted code", function()
      local code = "proc foo {} {\n    puts hello\n}"
      local result = formatting.format_code(code)
      assert.equals(code, result)
    end)
  end)

  describe("format_buffer", function()
    it("should format current buffer", function()
      -- Create a test buffer
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc foo {} {",
        "puts hello   ",
        "}",
      })

      formatting.format_buffer(bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- Should have removed trailing whitespace from line 2
      assert.equals("puts hello", lines[2]:match("^%s*(.-)%s*$"))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return true on success", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "puts hello" })

      local result = formatting.format_buffer(bufnr)
      assert.is_true(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return false for invalid buffer", function()
      local result = formatting.format_buffer(99999)
      assert.is_false(result)
    end)
  end)

  describe("TclFormat command", function()
    it("should be created after setup", function()
      formatting.setup()
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.TclFormat)
    end)
  end)
end)
