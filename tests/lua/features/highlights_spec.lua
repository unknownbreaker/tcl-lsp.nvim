-- tests/lua/features/highlights_spec.lua
describe("Highlights Feature", function()
  local highlights

  before_each(function()
    package.loaded["tcl-lsp.features.highlights"] = nil
    highlights = require("tcl-lsp.features.highlights")
  end)

  it("should provide semantic token capabilities", function()
    local caps = highlights.get_capabilities()
    assert.is_table(caps.semanticTokensProvider)
    assert.is_table(caps.semanticTokensProvider.legend)
    assert.is_table(caps.semanticTokensProvider.legend.tokenTypes)
    assert.is_table(caps.semanticTokensProvider.legend.tokenModifiers)
    assert.is_true(caps.semanticTokensProvider.full)
  end)

  it("should handle semantic tokens request for buffer", function()
    -- Create test buffer with TCL code
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "proc test {} {", "  return 1", "}" })
    vim.api.nvim_set_option_value("filetype", "tcl", { buf = bufnr })

    local result = highlights.handle_semantic_tokens(bufnr)
    assert.is_table(result)
    assert.is_table(result.data)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  describe("get_capabilities", function()
    it("should return full semantic tokens support", function()
      local caps = highlights.get_capabilities()
      assert.is_true(caps.semanticTokensProvider.full)
      assert.is_false(caps.semanticTokensProvider.delta)
    end)

    it("should include all standard token types", function()
      local caps = highlights.get_capabilities()
      local legend = caps.semanticTokensProvider.legend

      -- Check for key TCL-relevant token types
      assert.is_true(vim.tbl_contains(legend.tokenTypes, "function"))
      assert.is_true(vim.tbl_contains(legend.tokenTypes, "variable"))
      assert.is_true(vim.tbl_contains(legend.tokenTypes, "parameter"))
      assert.is_true(vim.tbl_contains(legend.tokenTypes, "keyword"))
    end)

    it("should include modifier types", function()
      local caps = highlights.get_capabilities()
      local legend = caps.semanticTokensProvider.legend

      assert.is_true(vim.tbl_contains(legend.tokenModifiers, "definition"))
      assert.is_true(vim.tbl_contains(legend.tokenModifiers, "declaration"))
      assert.is_true(vim.tbl_contains(legend.tokenModifiers, "modification"))
      assert.is_true(vim.tbl_contains(legend.tokenModifiers, "defaultLibrary"))
    end)
  end)

  describe("handle_semantic_tokens", function()
    it("should return empty data for empty buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local result = highlights.handle_semantic_tokens(bufnr)
      assert.is_table(result)
      assert.is_table(result.data)
      assert.equals(0, #result.data)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should extract tokens from proc definitions", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc greet {name} {",
        "  puts $name",
        "}",
      })
      vim.api.nvim_set_option_value("filetype", "tcl", { buf = bufnr })

      local result = highlights.handle_semantic_tokens(bufnr)
      assert.is_table(result)
      assert.is_table(result.data)
      -- Should have tokens: proc keyword, greet function, name parameter, puts keyword
      assert.is_true(#result.data > 0, "Should have encoded token data")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle buffer with parse errors gracefully", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      -- Invalid TCL: unclosed brace
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "proc broken {" })
      vim.api.nvim_set_option_value("filetype", "tcl", { buf = bufnr })

      -- Should not throw, just return empty or partial data
      local success, result = pcall(highlights.handle_semantic_tokens, bufnr)
      assert.is_true(success, "Should not throw on parse errors")
      assert.is_table(result)
      assert.is_table(result.data)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should use filepath from buffer name", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/test/path/file.tcl")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "set x 1" })
      vim.api.nvim_set_option_value("filetype", "tcl", { buf = bufnr })

      local result = highlights.handle_semantic_tokens(bufnr)
      assert.is_table(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("setup", function()
    it("should be callable without errors", function()
      local success = pcall(highlights.setup)
      assert.is_true(success, "setup() should not throw")
    end)
  end)

  describe("RVT support", function()
    it("should handle RVT files with mixed content", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "<html>",
        "<? proc test {} {} ?>",
        "</html>",
      })
      vim.api.nvim_set_option_value("filetype", "rvt", { buf = bufnr })

      local result = highlights.handle_semantic_tokens(bufnr)
      assert.is_table(result.data)
      assert.is_true(#result.data > 0) -- Should have tokens

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
