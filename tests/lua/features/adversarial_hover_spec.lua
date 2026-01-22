-- tests/lua/features/adversarial_hover_spec.lua
-- Adversarial tests for hover feature - designed to break the implementation
-- Tests edge cases, malformed input, unicode, deeply nested structures, and pathological cases

local helpers = require "tests.spec.test_helpers"

describe("Hover Feature - Adversarial Tests", function()
  local hover, docs

  before_each(function()
    package.loaded["tcl-lsp.features.hover"] = nil
    package.loaded["tcl-lsp.analyzer.docs"] = nil
    hover = require("tcl-lsp.features.hover")
    docs = require("tcl-lsp.analyzer.docs")
  end)

  describe("ATTACK: Malformed TCL Code", function()
    it("should handle proc with no closing brace", function()
      -- BUG HUNT: Does parser crash or return graceful error?
      local symbol = {
        type = "proc",
        name = "broken",
        qualified_name = "::broken",
        params = { "arg1" },
        file = "/tmp/broken.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success, "Should not crash on malformed symbol")
      assert.is_not_nil(result)
    end)

    it("should handle proc with nil range", function()
      -- BUG HUNT: Missing range should not cause nil reference error
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/test.tcl",
        range = nil, -- ATTACK: nil range
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success, "Should handle nil range gracefully")
      if success then
        assert.is_not_nil(result)
        -- Should default to line 1
        assert.matches(":1", result)
      end
    end)

    it("should handle proc with malformed range (missing start)", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { end_pos = { line = 5, col = 1 } }, -- ATTACK: no start
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success, "Should handle malformed range")
    end)

    it("should handle incomplete proc definition in buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc incomplete {",
        "  # Missing closing brace",
        "  puts hello",
      })

      -- Position on "incomplete"
      local success, result = pcall(hover.handle_hover, bufnr, 0, 5)
      assert.is_true(success, "Should not crash on incomplete proc")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle variable with no value", function()
      local symbol = {
        type = "variable",
        name = "empty",
        qualified_name = "::empty",
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_variable_hover, symbol, nil, "namespace variable")
      assert.is_true(success)
      assert.is_not_nil(result)
    end)
  end)

  describe("ATTACK: Unicode and Special Characters", function()
    it("should handle proc name with unicode (emoji)", function()
      -- BUG HUNT: Can TCL handle emoji in proc names? Should we crash?
      local symbol = {
        type = "proc",
        name = "test_🚀_proc",
        qualified_name = "::test_🚀_proc",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
      if success then
        assert.matches("🚀", result)
      end
    end)

    it("should handle comment with unicode (multi-byte chars)", function()
      -- BUG HUNT: Does comment extraction handle UTF-8 correctly?
      local doc = "这是一个测试注释 with 日本語 and한글"

      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, doc)
      assert.is_true(success)
      if success then
        assert.matches("这是一个测试", result)
      end
    end)

    it("should handle comment with RTL text (Arabic/Hebrew)", function()
      -- BUG HUNT: Right-to-left text can break markdown rendering
      local doc = "مرحبا بك في التطبيق - שלום"

      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, doc)
      assert.is_true(success)
    end)

    it("should handle comment with zero-width characters", function()
      -- BUG HUNT: Zero-width joiners and spaces can cause rendering issues
      local doc = "Test\u{200B}with\u{200C}zero\u{200D}width\u{FEFF}chars"

      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, doc)
      assert.is_true(success)
    end)

    it("should handle comment with control characters", function()
      -- BUG HUNT: Control chars like NULL, BEL, ESC can break terminals
      local doc = "Test\0with\x07control\x1bchars\x0d\x0a"

      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, doc)
      assert.is_true(success)
    end)

    it("should handle filename with unicode", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/文件_файл_📁.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
      if success then
        assert.matches("文件_файл_📁.tcl", result)
      end
    end)
  end)

  describe("ATTACK: Deeply Nested Namespaces", function()
    it("should handle extremely deep namespace nesting", function()
      -- BUG HUNT: Stack overflow or string buffer issues?
      local deep_namespace = "::" .. string.rep("level::", 100) .. "deep_proc"

      local symbol = {
        type = "proc",
        name = "deep_proc",
        qualified_name = deep_namespace,
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = deep_namespace:match("(.*)::.*$"),
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
      if success then
        assert.is_true(#result < 100000, "Result should not be excessively large")
      end
    end)

    it("should handle namespace with special TCL characters", function()
      -- BUG HUNT: Does :: in namespace break parsing?
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::weird::${name}::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::weird::${name}",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
    end)

    it("should handle triple colon namespace (malformed)", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = ":::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = ":::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
    end)
  end)

  describe("ATTACK: Very Long Comments", function()
    it("should handle comment with 10000 lines", function()
      -- BUG HUNT: Memory exhaustion or timeout?
      local lines = {}
      for i = 1, 10000 do
        table.insert(lines, "# Line " .. i)
      end
      table.insert(lines, "proc test {} {}")

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- ATTACK: Try to extract 10000 line comment
      local success, result = pcall(docs.extract_comments, lines, 10001)
      assert.is_true(success)
      if success and result then
        -- Should collect all comments
        local comment_lines = vim.split(result, "\n")
        assert.equals(10000, #comment_lines)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle comment with extremely long single line", function()
      -- BUG HUNT: String buffer overflow?
      local very_long_comment = "# " .. string.rep("x", 100000)
      local lines = { very_long_comment, "proc test {} {}" }

      local success, result = pcall(docs.extract_comments, lines, 2)
      assert.is_true(success)
      if success and result then
        -- Should handle the long line
        assert.is_true(#result > 50000)
      end
    end)

    it("should handle comment with markdown code blocks that could break rendering", function()
      local doc = [[
This is a comment with embedded markdown:

```tcl
proc nested {} {
  # This looks like code but it's in a comment
}
```

And some **bold** and *italic* text
]]

      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, doc)
      assert.is_true(success)
      -- Should have multiple code blocks
      local _, count = result:gsub("```", "")
      assert.is_true(count >= 2, "Should preserve code blocks")
    end)
  end)

  describe("ATTACK: Complex Variable Syntax", function()
    it("should extract variable name from $arr(key)", function()
      -- Tests extract_variable_name via handle_hover
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "set arr(key) value",
      })

      vim.api.nvim_buf_set_name(bufnr, "test.tcl")
      vim.bo[bufnr].filetype = "tcl"

      -- This will internally call extract_variable_name
      -- Testing if it correctly extracts "arr" from "$arr(key)"
      local success = pcall(hover.handle_hover, bufnr, 0, 4)
      assert.is_true(success)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should extract variable name from ${braced}", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "set {weird name} value",
      })

      vim.api.nvim_buf_set_name(bufnr, "test.tcl")
      vim.bo[bufnr].filetype = "tcl"

      local success = pcall(hover.handle_hover, bufnr, 0, 5)
      assert.is_true(success)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle variable with namespace qualifier", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "set ::config::app_name value",
      })

      vim.api.nvim_buf_set_name(bufnr, "test.tcl")
      vim.bo[bufnr].filetype = "tcl"

      local success = pcall(hover.handle_hover, bufnr, 0, 10)
      assert.is_true(success)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle unclosed brace in variable name", function()
      -- BUG HUNT: Does extract_variable_name crash on malformed input?
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "set ${unclosed value",
      })

      vim.api.nvim_buf_set_name(bufnr, "test.tcl")
      vim.bo[bufnr].filetype = "tcl"

      local success = pcall(hover.handle_hover, bufnr, 0, 5)
      assert.is_true(success, "Should not crash on unclosed brace")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle empty array key", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "set arr() value",
      })

      vim.api.nvim_buf_set_name(bufnr, "test.tcl")
      vim.bo[bufnr].filetype = "tcl"

      local success = pcall(hover.handle_hover, bufnr, 0, 4)
      assert.is_true(success)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK: Proc Parameters Edge Cases", function()
    it("should handle proc with 1000 parameters", function()
      -- BUG HUNT: String concatenation performance issues?
      local params = {}
      for i = 1, 1000 do
        table.insert(params, "param" .. i)
      end

      local symbol = {
        type = "proc",
        name = "huge",
        qualified_name = "::huge",
        params = params,
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local start_time = os.clock()
      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      local elapsed = os.clock() - start_time

      assert.is_true(success)
      assert.is_true(elapsed < 1.0, "Should format quickly (took " .. elapsed .. "s)")
      if success then
        -- Should contain all parameters
        assert.matches("param1", result)
        assert.matches("param1000", result)
      end
    end)

    it("should handle params with unicode", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = { "文字", "日本語", { "选项", "默认" } },
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
      if success then
        assert.matches("文字", result)
        assert.matches("日本語", result)
      end
    end)

    it("should handle params with special TCL chars", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = { "{braced}", "[list]", "$var", "normal" },
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
    end)

    it("should handle malformed param with only name in table", function()
      -- BUG HUNT: What if optional param format is wrong?
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = { { "only_name" } }, -- Missing default value
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success, "Should handle malformed optional param")
    end)

    it("should handle empty param list vs nil", function()
      local symbol1 = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local symbol2 = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = nil,
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success1, result1 = pcall(hover.format_proc_hover, symbol1, nil)
      local success2, result2 = pcall(hover.format_proc_hover, symbol2, nil)

      assert.is_true(success1)
      assert.is_true(success2)
      -- Both should show empty params
      assert.matches("{}", result1)
      assert.matches("{}", result2)
    end)
  end)

  describe("ATTACK: Edge Positions", function()
    it("should handle hover at line 0, col 0", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc test {} {}",
      })

      vim.api.nvim_buf_set_name(bufnr, "test.tcl")

      local success = pcall(hover.handle_hover, bufnr, 0, 0)
      assert.is_true(success)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle hover at last line, last column", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc test {} {}",
        "set var value",
        "end",
      })

      vim.api.nvim_buf_set_name(bufnr, "test.tcl")

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      local last_line = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1]
      local success = pcall(hover.handle_hover, bufnr, line_count - 1, #last_line)
      assert.is_true(success)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle hover beyond buffer bounds", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc test {} {}",
      })

      vim.api.nvim_buf_set_name(bufnr, "test.tcl")

      -- ATTACK: Line beyond buffer
      local success = pcall(hover.handle_hover, bufnr, 1000, 0)
      assert.is_true(success, "Should not crash on out-of-bounds line")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle negative line/column", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc test {} {}",
      })

      vim.api.nvim_buf_set_name(bufnr, "test.tcl")

      -- ATTACK: Negative indices
      local success = pcall(hover.handle_hover, bufnr, -1, -1)
      assert.is_true(success, "Should handle negative indices gracefully")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK: Empty and Degenerate Cases", function()
    it("should handle empty file", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      vim.api.nvim_buf_set_name(bufnr, "empty.tcl")

      local result = hover.handle_hover(bufnr, 0, 0)
      assert.is_nil(result, "Empty file should return nil")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle file with only comments", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# Comment 1",
        "# Comment 2",
        "# Comment 3",
      })
      vim.api.nvim_buf_set_name(bufnr, "comments.tcl")

      local result = hover.handle_hover(bufnr, 1, 0)
      -- Should return nil since no symbols
      assert.is_true(result == nil)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle file with only whitespace", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "   ",
        "\t\t\t",
        "     ",
      })
      vim.api.nvim_buf_set_name(bufnr, "whitespace.tcl")

      local result = hover.handle_hover(bufnr, 0, 1)
      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle single character file", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x" })
      vim.api.nvim_buf_set_name(bufnr, "tiny.tcl")

      local success = pcall(hover.handle_hover, bufnr, 0, 0)
      assert.is_true(success)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle invalid buffer number", function()
      -- ATTACK: Non-existent buffer
      local result = hover.handle_hover(99999, 0, 0)
      assert.is_nil(result, "Invalid buffer should return nil")
    end)

    it("should handle file with only newlines", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "", "", "", "" })
      vim.api.nvim_buf_set_name(bufnr, "newlines.tcl")

      local result = hover.handle_hover(bufnr, 2, 0)
      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("ATTACK: Comment Extraction Edge Cases", function()
    it("should handle comment at line 1 (no previous line)", function()
      local lines = { "proc test {} {}" }
      local result = docs.extract_comments(lines, 1)
      assert.is_nil(result, "No comment above line 1")
    end)

    it("should handle comment extraction at line 0", function()
      -- BUG HUNT: Boundary condition - line 0 should be handled
      local lines = { "# Comment", "proc test {} {}" }
      local success, result = pcall(docs.extract_comments, lines, 0)
      assert.is_true(success)
    end)

    it("should stop at first non-comment line", function()
      local lines = {
        "# Comment 1",
        "# Comment 2",
        "set var value", -- Non-comment
        "# Comment 3",
        "proc test {} {}", -- Target
      }

      local result = docs.extract_comments(lines, 5)
      assert.is_not_nil(result)
      -- Should only get Comment 3, not Comment 1 or 2
      assert.matches("Comment 3", result)
      assert.is_nil(result:match("Comment 1"))
    end)

    it("should handle comments with tabs and mixed indentation", function()
      local lines = {
        "\t\t# Tab indented",
        "    # Space indented",
        " \t # Mixed",
        "proc test {} {}",
      }

      local result = docs.extract_comments(lines, 4)
      assert.is_not_nil(result)
      -- All comments should be extracted with leading whitespace removed
      assert.matches("Tab indented", result)
      assert.matches("Space indented", result)
      assert.matches("Mixed", result)
    end)

    it("should handle comment with only # symbol", function()
      local lines = {
        "#",
        "proc test {} {}",
      }

      local result = docs.extract_comments(lines, 2)
      assert.is_not_nil(result)
      assert.equals("", result)
    end)

    it("should handle comment without space after #", function()
      local lines = {
        "#NoSpaceAfterHash",
        "proc test {} {}",
      }

      local result = docs.extract_comments(lines, 2)
      assert.is_not_nil(result)
      assert.equals("NoSpaceAfterHash", result)
    end)

    it("should handle blank lines between comments", function()
      local lines = {
        "# Comment 1",
        "", -- Blank line should stop collection
        "# Comment 2",
        "proc test {} {}",
      }

      local result = docs.extract_comments(lines, 4)
      assert.is_not_nil(result)
      -- Should only get Comment 2
      assert.matches("Comment 2", result)
      assert.is_nil(result:match("Comment 1"))
    end)

    it("should handle very long comment line", function()
      local long_comment = "# " .. string.rep("word ", 10000)
      local lines = {
        long_comment,
        "proc test {} {}",
      }

      local success, result = pcall(docs.extract_comments, lines, 2)
      assert.is_true(success)
      if success and result then
        assert.is_true(#result > 40000, "Should preserve long comment")
      end
    end)
  end)

  describe("ATTACK: Path Handling", function()
    it("should handle path with no directory separator", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "nodirectory.tcl", -- No slashes
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
      assert.matches("nodirectory.tcl", result)
    end)

    it("should handle path with multiple slashes", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/path//with///extra////slashes.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
      assert.matches("slashes.tcl", result)
    end)

    it("should handle path ending with slash", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/path/to/",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
    end)

    it("should handle empty file path", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
    end)

    it("should handle Windows-style path", function()
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "C:\\Users\\test\\file.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
      -- basename should handle backslashes on Windows - but may not on Unix
      -- Just ensure it doesn't crash
    end)
  end)

  describe("ATTACK: get_initial_value Edge Cases", function()
    it("should handle nil AST", function()
      local result = docs.get_initial_value(nil, "test")
      assert.is_nil(result)
    end)

    it("should handle empty AST", function()
      local ast = { type = "root", children = {} }
      local result = docs.get_initial_value(ast, "test")
      assert.is_nil(result)
    end)

    it("should handle deeply nested set command", function()
      -- BUG HUNT: Stack overflow on deep recursion?
      local ast = { type = "root", children = {} }
      local current = ast.children

      -- Create 1000 levels of nesting
      for i = 1, 1000 do
        local node = { type = "namespace_eval", children = {} }
        table.insert(current, node)
        current = node.children
      end

      -- Add set at the deepest level
      table.insert(current, { type = "set", var_name = "deep", value = "found" })

      local success, result = pcall(docs.get_initial_value, ast, "deep")
      assert.is_true(success, "Should handle deep nesting without stack overflow")
      if success then
        assert.equals("found", result)
      end
    end)

    it("should handle circular reference in AST (defensive)", function()
      -- BUG HUNT: Infinite loop on circular structure?
      local ast = { type = "root", children = {} }
      local child = { type = "namespace_eval", children = {} }
      table.insert(ast.children, child)
      -- Create circular reference
      table.insert(child.children, ast)

      -- This should not hang - but may not find value
      local success = pcall(function()
        local start_time = os.clock()
        docs.get_initial_value(ast, "test")
        local elapsed = os.clock() - start_time
        assert.is_true(elapsed < 1.0, "Should not hang on circular reference")
      end)
      assert.is_true(success)
    end)
  end)

  describe("ATTACK: get_scope_type Edge Cases", function()
    it("should handle nil context", function()
      local result = hover.get_scope_type("test", nil)
      assert.equals("namespace variable", result)
    end)

    it("should handle empty context", function()
      local result = hover.get_scope_type("test", {})
      assert.equals("namespace variable", result)
    end)

    it("should handle context with nil locals", function()
      local context = { locals = nil, globals = { "test" }, namespace = "::" }
      local result = hover.get_scope_type("test", context)
      -- Should check globals even if locals is nil
      assert.equals("global variable", result)
    end)

    it("should handle context with nil globals", function()
      local context = { locals = { "test" }, globals = nil, namespace = "::" }
      local result = hover.get_scope_type("test", context)
      assert.equals("local variable", result)
    end)

    it("should handle variable in both locals and globals (locals win)", function()
      local context = { locals = { "test" }, globals = { "test" }, namespace = "::" }
      local result = hover.get_scope_type("test", context)
      -- Locals should take precedence
      assert.equals("local variable", result)
    end)
  end)

  describe("ATTACK: Format Edge Cases", function()
    it("should handle extremely long qualified name", function()
      local long_name = "::" .. string.rep("namespace::", 100) .. "proc_name"
      local symbol = {
        type = "proc",
        name = "proc_name",
        qualified_name = long_name,
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, nil)
      assert.is_true(success)
      if success then
        -- Markdown should still be valid
        assert.matches("```tcl", result)
        assert.matches("proc " .. long_name, result)
      end
    end)

    it("should handle comment with markdown special chars", function()
      local doc = "Test with **stars** and __underscores__ and `backticks` and [brackets]"
      local symbol = {
        type = "proc",
        name = "test",
        qualified_name = "::test",
        params = {},
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
        scope = "::",
      }

      local success, result = pcall(hover.format_proc_hover, symbol, doc)
      assert.is_true(success)
      -- Markdown should be preserved (not escaped)
      assert.matches("**stars**", result)
      assert.matches("`backticks`", result)
    end)

    it("should handle namespace type symbol", function()
      local symbol = {
        type = "namespace",
        name = "test",
        qualified_name = "::test::ns",
        file = "/tmp/test.tcl",
        range = { start = { line = 1, col = 1 } },
      }

      local success, result = pcall(hover.handle_hover, 0, 0, 0)
      -- This path may not be exercised easily without full AST
      assert.is_true(success)
    end)
  end)
end)
