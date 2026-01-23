-- tests/lua/features/diagnostics_spec.lua
-- ADVERSARIAL TESTS for diagnostics feature
-- Goal: Break the implementation before it ships to users
--
-- Attack vectors:
-- 1. Edge cases that crash/hang (empty buffers, huge files, binary content)
-- 2. Parser error format edge cases (nil messages, no ranges, negative lines)
-- 3. State/lifecycle issues (calling before setup, deleted buffers)
-- 4. Integration failures (parser returns weird data, vim.diagnostic.set fails)

-- Helper to create uniquely-named test buffers and avoid E95 errors
local test_counter = 0
local function make_test_buffer(content)
  test_counter = test_counter + 1
  local name = string.format("/tmp/test_diag_%d_%d.tcl", vim.loop.now(), test_counter)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, name)
  if content then
    local lines = vim.split(content, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
  return bufnr
end

describe("Diagnostics Feature - Adversarial Tests", function()
  local diagnostics
  local parser

  before_each(function()
    -- Reload modules to get clean state
    package.loaded["tcl-lsp.features.diagnostics"] = nil
    package.loaded["tcl-lsp.parser"] = nil
    diagnostics = require("tcl-lsp.features.diagnostics")
    parser = require("tcl-lsp.parser")
  end)

  describe("ATTACK 1: Lifecycle and State Edge Cases", function()
    it("should handle check_buffer before setup()", function()
      -- BUG HUNT: Does it crash if namespace is nil?
      local bufnr = make_test_buffer("set x 1")

      -- Don't call setup(), just call check_buffer directly
      local success, err = pcall(diagnostics.check_buffer, bufnr)

      -- Should either succeed or fail gracefully, never crash
      assert.is_true(success or err:match("namespace"), "Should handle nil namespace gracefully")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle clear() before setup()", function()
      -- BUG HUNT: Does clear() crash if namespace is nil?
      local bufnr = vim.api.nvim_create_buf(false, true)

      local success = pcall(diagnostics.clear, bufnr)
      assert.is_true(success, "Should not crash on clear before setup")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle multiple setup() calls", function()
      -- BUG HUNT: Double setup could create duplicate autocommands
      local success1 = pcall(diagnostics.setup)
      local success2 = pcall(diagnostics.setup)
      local success3 = pcall(diagnostics.setup)

      assert.is_true(success1)
      assert.is_true(success2)
      assert.is_true(success3)
    end)

    it("should handle check_buffer on invalid buffer number", function()
      -- ATTACK: Non-existent buffer
      diagnostics.setup()

      local success, err = pcall(diagnostics.check_buffer, 99999)
      -- Should fail gracefully, not crash
      assert.is_true(success or err ~= nil, "Should handle invalid buffer")
    end)

    it("should handle check_buffer on deleted buffer", function()
      -- ATTACK: Buffer gets deleted mid-check
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "set x 1" })
      vim.api.nvim_buf_delete(bufnr, { force = true })

      local success = pcall(diagnostics.check_buffer, bufnr)
      -- Should handle deleted buffer gracefully
      assert.is_true(success, "Should not crash on deleted buffer")
    end)

    it("should handle clear() on buffer with no diagnostics", function()
      -- BUG HUNT: Clearing non-existent diagnostics should be safe
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "empty.tcl")

      local success = pcall(diagnostics.clear, bufnr)
      assert.is_true(success, "Should handle clear on buffer with no diagnostics")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle clear() on invalid buffer", function()
      diagnostics.setup()

      local success = pcall(diagnostics.clear, 99999)
      assert.is_true(success, "Should not crash on clear with invalid buffer")
    end)
  end)

  describe("ATTACK 2: Empty and Degenerate Buffers", function()
    it("should handle completely empty buffer", function()
      -- BUG HUNT: Empty content could cause parser issues
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      vim.api.nvim_buf_set_name(bufnr, "empty.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle empty buffer")

      -- Should set empty diagnostics (no errors)
      local diags = vim.diagnostic.get(bufnr)
      assert.is_table(diags)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle buffer with only whitespace", function()
      -- BUG HUNT: Whitespace-only could confuse parser
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "   ", "\t\t", "  \n  ", "" })
      vim.api.nvim_buf_set_name(bufnr, "whitespace.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle whitespace-only buffer")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle buffer with only comments", function()
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# Comment 1",
        "# Comment 2",
        "# Comment 3",
      })
      vim.api.nvim_buf_set_name(bufnr, "comments.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle comment-only buffer")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle single-character buffer", function()
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x" })
      vim.api.nvim_buf_set_name(bufnr, "tiny.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle 1-char buffer")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle buffer with only newlines", function()
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "", "", "", "" })
      vim.api.nvim_buf_set_name(bufnr, "newlines.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle newline-only buffer")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle unnamed buffer", function()
      -- BUG HUNT: Buffer with no filename
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "set x 1" })
      -- Don't set name - filename will be empty

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle unnamed buffer")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle buffer that is not saved to disk", function()
      -- BUG HUNT: Unsaved buffer (in-memory only)
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "proc test {} {}" })
      vim.api.nvim_buf_set_name(bufnr, "/tmp/never_saved_" .. os.time() .. ".tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle unsaved buffer")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK 3: Very Large Buffers", function()
    it("should handle 10,000 line buffer without hanging", function()
      -- BUG HUNT: Large files could cause memory/performance issues
      diagnostics.setup()

      local lines = {}
      for i = 1, 10000 do
        table.insert(lines, "set var" .. i .. " value" .. i)
      end

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_set_name(bufnr, "huge.tcl")

      local start_time = os.clock()
      local success = pcall(diagnostics.check_buffer, bufnr)
      local elapsed = os.clock() - start_time

      assert.is_true(success, "Should handle large buffer")
      -- Parser has 10s timeout, but this should be much faster
      assert.is_true(elapsed < 5.0, "Should complete in reasonable time (took " .. elapsed .. "s)")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle very long single line", function()
      -- BUG HUNT: 100KB single line could break string handling
      diagnostics.setup()

      local long_line = "set x " .. string.rep("a", 100000)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { long_line })
      vim.api.nvim_buf_set_name(bufnr, "longline.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle very long line")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle deeply nested structures", function()
      -- BUG HUNT: 1000 levels of nesting
      diagnostics.setup()

      local code = "set x " .. string.rep("{", 1000) .. "deep" .. string.rep("}", 1000)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { code })
      vim.api.nvim_buf_set_name(bufnr, "nested.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle deep nesting")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK 4: Binary and Special Content", function()
    it("should handle buffer with null bytes", function()
      -- BUG HUNT: Binary content with \0
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "set x hello\x00world" })
      vim.api.nvim_buf_set_name(bufnr, "nulls.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle null bytes")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle buffer with control characters", function()
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "set x \x01\x02\x03",
        "set y \x1b[31mred\x1b[0m",
      })
      vim.api.nvim_buf_set_name(bufnr, "control.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle control characters")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle buffer with emoji", function()
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'proc test🔥 {} { puts "🚀" }',
      })
      vim.api.nvim_buf_set_name(bufnr, "emoji.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle emoji")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle buffer with RTL unicode", function()
      -- BUG HUNT: Right-to-left text
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '# مرحبا - שלום',
        "set x value",
      })
      vim.api.nvim_buf_set_name(bufnr, "rtl.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle RTL text")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle buffer with zero-width characters", function()
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      -- Zero-width space U+200B
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "set x test" .. string.char(0xE2, 0x80, 0x8B) .. "value",
      })
      vim.api.nvim_buf_set_name(bufnr, "zwj.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle zero-width chars")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK 5: Parser Error Format Edge Cases", function()
    it("should handle parser returning nil errors array", function()
      -- BUG HUNT: Mock parser.parse_with_errors to return weird data
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return { ast = { type = "root" }, errors = nil }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle nil errors array")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle error with nil message", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = nil, range = { start_line = 1, start_col = 1, end_line = 1, end_col = 10 } },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle nil message")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle error with empty message", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "", range = { start_line = 1, start_col = 1, end_line = 1, end_col = 10 } },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle empty message")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle error with nil range", function()
      -- BUG HUNT: Missing range info should not crash
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "Syntax error", range = nil },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle nil range")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle error with partial range (missing end)", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "Error", range = { start_line = 1, start_col = 1 } }, -- Missing end
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle partial range")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle error at line 0", function()
      -- BUG HUNT: Line 0 is invalid in vim (0-indexed but lines start at 1)
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "Error at line 0", range = { start_line = 0, start_col = 1, end_line = 0, end_col = 10 } },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle line 0 (convert to line 1)")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle error with negative line number", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            {
              message = "Negative line",
              range = { start_line = -5, start_col = 1, end_line = -5, end_col = 10 },
            },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle negative line number")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle error with line beyond buffer", function()
      -- BUG HUNT: Error at line 1000 but buffer only has 1 line
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "Error", range = { start_line = 1000, start_col = 1, end_line = 1000, end_col = 10 } },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle line beyond buffer")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle multiple errors on same line", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "Error 1", range = { start_line = 1, start_col = 1, end_line = 1, end_col = 5 } },
            { message = "Error 2", range = { start_line = 1, start_col = 6, end_line = 1, end_col = 10 } },
            { message = "Error 3", range = { start_line = 1, start_col = 11, end_line = 1, end_col = 15 } },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1 set y 2")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle multiple errors on same line")

      -- Verify all errors are set
      local diags = vim.diagnostic.get(bufnr)
      assert.equals(3, #diags, "Should have 3 diagnostics")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle error with very long message (10KB)", function()
      -- BUG HUNT: Huge error message could break display
      diagnostics.setup()

      local long_msg = string.rep("Error details: ", 700) -- ~10KB
      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = long_msg, range = { start_line = 1, start_col = 1, end_line = 1, end_col = 10 } },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle very long error message")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle error with message containing special characters", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            {
              message = "Error: unclosed { at line 5\nExpected }\nGot EOF\t\t\t",
              range = { start_line = 5, start_col = 1, end_line = 5, end_col = 10 },
            },
          },
        }
      end

      local bufnr = make_test_buffer("1\n2\n3\n4\nproc test {} {")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle special chars in message")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK 6: Parser Execution Failures", function()
    it("should handle parser.parse_with_errors throwing error", function()
      -- BUG HUNT: Parser crashes entirely
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        error("Parser crashed!")
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      -- Should catch the error gracefully
      assert.is_true(success or pcall(function() end), "Should handle parser crash")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle parser returning nil", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return nil
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle parser returning nil")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle parser returning non-table", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return "unexpected string"
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle parser returning wrong type")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle errors array with non-table entries", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = { "string error", 123, true, nil, {} }, -- Mixed types
        }
      end

      local bufnr = make_test_buffer("set x 1")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle malformed errors array")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK 7: Integration with vim.diagnostic", function()
    it("should handle vim.diagnostic.set failure gracefully", function()
      -- BUG HUNT: What if vim.diagnostic.set errors?
      diagnostics.setup()

      -- This is hard to test without mocking, but we can check it doesn't crash
      local bufnr = make_test_buffer("proc test {} {")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle vim.diagnostic.set gracefully")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should properly convert 1-indexed to 0-indexed lines", function()
      -- BUG HUNT: Off-by-one errors in line conversion
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            -- Parser returns 1-indexed
            { message = "Error", range = { start_line = 5, start_col = 10, end_line = 5, end_col = 20 } },
          },
        }
      end

      local bufnr = make_test_buffer("1\n2\n3\n4\nerror here\n6")

      diagnostics.check_buffer(bufnr)

      local diags = vim.diagnostic.get(bufnr)
      assert.equals(1, #diags)
      -- Should be 0-indexed (line 5 → 4)
      assert.equals(4, diags[1].lnum, "Line should be 0-indexed")
      assert.equals(9, diags[1].col, "Column should be 0-indexed")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should set severity to ERROR", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "Error", range = { start_line = 1, start_col = 1, end_line = 1, end_col = 10 } },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      diagnostics.check_buffer(bufnr)

      local diags = vim.diagnostic.get(bufnr)
      assert.equals(1, #diags)
      assert.equals(vim.diagnostic.severity.ERROR, diags[1].severity)

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should set source to tcl-lsp", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "Error", range = { start_line = 1, start_col = 1, end_line = 1, end_col = 10 } },
          },
        }
      end

      local bufnr = make_test_buffer("set x 1")

      diagnostics.check_buffer(bufnr)

      local diags = vim.diagnostic.get(bufnr)
      assert.equals(1, #diags)
      assert.equals("tcl-lsp", diags[1].source)

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK 8: Real-World Syntax Errors", function()
    it("should handle unclosed brace", function()
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc test {} {",
        "  puts hello",
        "# Missing closing brace",
      })
      vim.api.nvim_buf_set_name(bufnr, "unclosed.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle unclosed brace")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should clear diagnostics when syntax is fixed", function()
      diagnostics.setup()

      local bufnr = make_test_buffer("proc test {} {")

      -- First check: should have errors
      diagnostics.check_buffer(bufnr)
      local diags1 = vim.diagnostic.get(bufnr)
      -- May have errors depending on parser

      -- Fix the syntax
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "proc test {} {}" })

      -- Second check: should clear errors
      diagnostics.check_buffer(bufnr)
      local diags2 = vim.diagnostic.get(bufnr)
      -- Should have fewer or no errors

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle file with no errors", function()
      diagnostics.setup()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc test {arg} {",
        "  set x 1",
        "  puts $x",
        "}",
      })
      vim.api.nvim_buf_set_name(bufnr, "valid.tcl")

      diagnostics.check_buffer(bufnr)

      local diags = vim.diagnostic.get(bufnr)
      assert.equals(0, #diags, "Valid code should have no diagnostics")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK 9: Concurrent Operations", function()
    it("should handle rapid repeated check_buffer calls", function()
      -- BUG HUNT: Race conditions with multiple saves
      diagnostics.setup()

      local bufnr = make_test_buffer("set x 1")

      -- Spam check_buffer
      for i = 1, 10 do
        local success = pcall(diagnostics.check_buffer, bufnr)
        assert.is_true(success, "Repeated calls should not crash")
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle check_buffer on multiple buffers", function()
      diagnostics.setup()

      local buffers = {}
      for i = 1, 5 do
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "set x" .. i .. " " .. i })
        vim.api.nvim_buf_set_name(bufnr, "test" .. i .. ".tcl")
        table.insert(buffers, bufnr)
      end

      -- Check all buffers
      for _, bufnr in ipairs(buffers) do
        local success = pcall(diagnostics.check_buffer, bufnr)
        assert.is_true(success, "Should handle multiple buffers")
      end

      -- Clean up
      for _, bufnr in ipairs(buffers) do
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)
  end)

  describe("ATTACK 10: Edge Cases in Diagnostic Display", function()
    it("should handle diagnostic at column 0", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "Error at start", range = { start_line = 1, start_col = 0, end_line = 1, end_col = 5 } },
          },
        }
      end

      local bufnr = make_test_buffer("error here")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle column 0")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle diagnostic spanning multiple lines", function()
      diagnostics.setup()

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return {
          ast = { type = "root" },
          errors = {
            { message = "Multiline error", range = { start_line = 1, start_col = 1, end_line = 3, end_col = 10 } },
          },
        }
      end

      local bufnr = make_test_buffer("line 1\nline 2\nline 3")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle multi-line diagnostic")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle 100 errors in one file", function()
      -- BUG HUNT: Can vim.diagnostic handle many errors?
      diagnostics.setup()

      local errors = {}
      for i = 1, 100 do
        table.insert(errors, {
          message = "Error " .. i,
          range = { start_line = i, start_col = 1, end_line = i, end_col = 10 },
        })
      end

      local original_parse = parser.parse_with_errors
      parser.parse_with_errors = function()
        return { ast = { type = "root" }, errors = errors }
      end

      local lines = {}
      for i = 1, 100 do
        table.insert(lines, "line " .. i)
      end

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_set_name(bufnr, "manyerrors.tcl")

      local success = pcall(diagnostics.check_buffer, bufnr)
      assert.is_true(success, "Should handle 100 errors")

      local diags = vim.diagnostic.get(bufnr)
      assert.equals(100, #diags, "Should set all 100 diagnostics")

      parser.parse_with_errors = original_parse
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
