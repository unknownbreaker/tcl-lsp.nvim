-- tests/lua/analyzer/definitions_spec.lua
-- Tests for Definition Resolver - finds definitions given cursor position

describe("Definition Resolver", function()
  local definitions
  local index

  before_each(function()
    package.loaded["tcl-lsp.analyzer.definitions"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil
    definitions = require("tcl-lsp.analyzer.definitions")
    index = require("tcl-lsp.analyzer.index")
    index.clear()
  end)

  -- Helper for test assertions
  local function assert_includes(item, list)
    for _, v in ipairs(list) do
      if v == item then
        return true
      end
    end
    error("Expected list to include: " .. tostring(item) .. "\nList: " .. vim.inspect(list))
  end

  describe("build_candidates", function()
    it("should generate qualified name candidates", function()
      local context = {
        namespace = "::math",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      }

      local candidates = definitions.build_candidates("add", context)

      assert_includes("add", candidates)
      assert_includes("::math::add", candidates)
      assert_includes("::add", candidates)
    end)

    it("should handle global namespace", function()
      local context = {
        namespace = "::",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      }

      local candidates = definitions.build_candidates("helper", context)

      assert_includes("helper", candidates)
      assert_includes("::helper", candidates)
      -- Should not double up ::
      for _, c in ipairs(candidates) do
        assert.is_nil(c:match("^::::"), "Should not have :::: prefix")
      end
    end)

    it("should handle nested namespaces", function()
      local context = {
        namespace = "::outer::inner",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      }

      local candidates = definitions.build_candidates("func", context)

      assert_includes("func", candidates)
      assert_includes("::outer::inner::func", candidates)
      assert_includes("::func", candidates)
    end)
  end)

  describe("find_in_index", function()
    it("should find proc in index", function()
      index.add_symbol({
        type = "proc",
        name = "helper",
        qualified_name = "::utils::helper",
        file = "/project/utils.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
        scope = "::utils",
      })

      local result = definitions.find_in_index("helper", {
        namespace = "::utils",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      })

      assert.is_not_nil(result)
      assert.equals("/project/utils.tcl", result.file)
      assert.equals(5, result.range.start.line)
    end)

    it("should return nil for local variable", function()
      local result = definitions.find_in_index("x", {
        namespace = "::",
        proc = "test",
        locals = { "x", "y" },
        globals = {},
        upvars = {},
      })

      -- Local variables don't have index entries
      assert.is_nil(result)
    end)

    it("should find global variable in index", function()
      index.add_symbol({
        type = "variable",
        name = "config",
        qualified_name = "::config",
        file = "/project/config.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 1, col = 20 } },
        scope = "::",
      })

      local result = definitions.find_in_index("config", {
        namespace = "::app",
        proc = "init",
        locals = { "x" },
        globals = { "config" },
        upvars = {},
      })

      assert.is_not_nil(result)
      assert.equals("::config", result.qualified_name)
    end)

    it("should follow upvar binding", function()
      index.add_symbol({
        type = "variable",
        name = "original",
        qualified_name = "::original",
        file = "/project/vars.tcl",
        range = { start = { line = 3, col = 1 }, end_pos = { line = 3, col = 15 } },
        scope = "::",
      })

      local result = definitions.find_in_index("local_ref", {
        namespace = "::",
        proc = "test",
        locals = {},
        globals = {},
        upvars = {
          local_ref = { level = 1, other_var = "original" },
        },
      })

      assert.is_not_nil(result)
      assert.equals("::original", result.qualified_name)
    end)

    it("should find proc in current namespace first", function()
      -- Add proc in global namespace
      index.add_symbol({
        type = "proc",
        name = "add",
        qualified_name = "::add",
        file = "/project/global.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
        scope = "::",
      })

      -- Add proc in math namespace
      index.add_symbol({
        type = "proc",
        name = "add",
        qualified_name = "::math::add",
        file = "/project/math.tcl",
        range = { start = { line = 10, col = 1 }, end_pos = { line = 15, col = 1 } },
        scope = "::math",
      })

      local result = definitions.find_in_index("add", {
        namespace = "::math",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      })

      assert.is_not_nil(result)
      -- Should find the one in current namespace
      assert.equals("::math::add", result.qualified_name)
    end)

    it("should fall back to global namespace", function()
      index.add_symbol({
        type = "proc",
        name = "global_proc",
        qualified_name = "::global_proc",
        file = "/project/lib.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
        scope = "::",
      })

      local result = definitions.find_in_index("global_proc", {
        namespace = "::app",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      })

      assert.is_not_nil(result)
      assert.equals("::global_proc", result.qualified_name)
    end)

    it("should return nil when symbol not found", function()
      local result = definitions.find_in_index("nonexistent", {
        namespace = "::",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      })

      assert.is_nil(result)
    end)
  end)

  describe("find_in_ast", function()
    it("should find proc in current file AST", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "helper",
            params = {},
            range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
          },
        },
      }

      local result = definitions.find_in_ast(ast, "helper", {
        namespace = "::",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      }, "/test.tcl")

      assert.is_not_nil(result)
      assert.equals("file:///test.tcl", result.uri)
      -- LSP uses 0-indexed lines
      assert.equals(4, result.range.start.line)
    end)

    it("should find namespaced proc in AST", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "utils",
            body = {
              children = {
                {
                  type = "proc",
                  name = "format",
                  params = {},
                  range = { start = { line = 3, col = 3 }, end_pos = { line = 8, col = 1 } },
                },
              },
            },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
          },
        },
      }

      local result = definitions.find_in_ast(ast, "format", {
        namespace = "::utils",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      }, "/utils.tcl")

      assert.is_not_nil(result)
      assert.equals("file:///utils.tcl", result.uri)
    end)

    it("should return nil when not found in AST", function()
      local ast = {
        type = "root",
        children = {},
      }

      local result = definitions.find_in_ast(ast, "unknown", {
        namespace = "::",
        proc = nil,
        locals = {},
        globals = {},
        upvars = {},
      }, "/empty.tcl")

      assert.is_nil(result)
    end)
  end)
end)
