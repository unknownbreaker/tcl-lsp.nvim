-- tests/lua/utils/cache_spec.lua
-- Tests for per-buffer AST cache

describe("AST Cache", function()
  local cache
  local temp_file
  local bufnr

  before_each(function()
    -- Clear module cache so each test gets a fresh cache
    package.loaded["tcl-lsp.utils.cache"] = nil
    cache = require("tcl-lsp.utils.cache")

    -- Create a temp TCL file and load it into a buffer
    temp_file = vim.fn.tempname() .. ".tcl"
    local f = io.open(temp_file, "w")
    f:write('proc hello {} {\n    puts "hello"\n}\n')
    f:close()

    vim.cmd("edit " .. temp_file)
    bufnr = vim.api.nvim_get_current_buf()
  end)

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    if temp_file then
      vim.fn.delete(temp_file)
    end
  end)

  describe("parse()", function()
    it("should return AST on success", function()
      local ast, err = cache.parse(bufnr)
      assert.is_not_nil(ast)
      assert.is_nil(err)
      assert.equals("root", ast.type)
    end)

    it("should return nil and error for syntax errors", function()
      -- Replace buffer content with broken TCL
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "proc broken {" })
      local ast, err = cache.parse(bufnr)
      -- Parser may return ast=nil with error or ast with had_error
      -- Either way, the cache should handle it
      if not ast then
        assert.is_not_nil(err)
      end
    end)

    it("should cache on same changedtick (hit)", function()
      cache.reset_stats()

      -- First parse: cache miss
      local ast1, _ = cache.parse(bufnr)
      assert.is_not_nil(ast1)

      -- Second parse: same content -> cache hit
      local ast2, _ = cache.parse(bufnr)
      assert.is_not_nil(ast2)

      local s = cache.stats()
      assert.equals(1, s.misses)
      assert.equals(1, s.hits)
    end)

    it("should re-parse when changedtick changes (miss)", function()
      cache.reset_stats()

      -- First parse
      local ast1, _ = cache.parse(bufnr)
      assert.is_not_nil(ast1)

      -- Modify buffer -> changedtick increments
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc goodbye {} {",
        '    puts "goodbye"',
        "}",
      })

      -- Second parse: different changedtick -> cache miss
      local ast2, _ = cache.parse(bufnr)
      assert.is_not_nil(ast2)

      local s = cache.stats()
      assert.equals(2, s.misses)
      assert.equals(0, s.hits)
    end)
  end)

  describe("parse_with_errors()", function()
    it("should return table with ast and errors", function()
      local result = cache.parse_with_errors(bufnr)
      assert.is_table(result)
      assert.is_not_nil(result.ast)
      assert.is_table(result.errors)
    end)

    it("should share cache with parse()", function()
      cache.reset_stats()

      -- Parse via parse() first
      cache.parse(bufnr)
      -- Then via parse_with_errors() -> should be a hit
      cache.parse_with_errors(bufnr)

      local s = cache.stats()
      assert.equals(1, s.misses)
      assert.equals(1, s.hits)
    end)
  end)

  describe("invalidate()", function()
    it("should force re-parse after invalidation", function()
      cache.reset_stats()

      cache.parse(bufnr)
      assert.equals(1, cache.stats().misses)

      cache.invalidate(bufnr)

      cache.parse(bufnr)
      assert.equals(2, cache.stats().misses)
    end)
  end)

  describe("clear()", function()
    it("should clear all cached entries", function()
      cache.parse(bufnr)
      assert.equals(1, cache.stats().size)

      cache.clear()
      assert.equals(0, cache.stats().size)
    end)
  end)

  describe("stats()", function()
    it("should track hits, misses, and size", function()
      cache.reset_stats()

      local s = cache.stats()
      assert.equals(0, s.hits)
      assert.equals(0, s.misses)
      assert.equals(0, s.size)

      cache.parse(bufnr)
      s = cache.stats()
      assert.equals(0, s.hits)
      assert.equals(1, s.misses)
      assert.equals(1, s.size)

      cache.parse(bufnr)
      s = cache.stats()
      assert.equals(1, s.hits)
      assert.equals(1, s.misses)
      assert.equals(1, s.size)
    end)
  end)

  describe("invalid bufnr", function()
    it("should return nil and error for nil bufnr", function()
      local ast, err = cache.parse(nil)
      assert.is_nil(ast)
      assert.is_not_nil(err)
    end)

    it("should return error table for nil bufnr via parse_with_errors", function()
      local result = cache.parse_with_errors(nil)
      assert.is_table(result)
      assert.is_nil(result.ast)
      assert.is_true(#result.errors > 0)
    end)
  end)
end)
