-- tests/lua/analyzer/extractor_spec.lua
-- Tests for Symbol Extractor - extracts symbols from parsed AST

describe("Symbol Extractor", function()
  local extractor

  before_each(function()
    package.loaded["tcl-lsp.analyzer.extractor"] = nil
    extractor = require("tcl-lsp.analyzer.extractor")
  end)

  describe("extract_symbols", function()
    it("should extract proc definitions", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "greet",
            params = { { name = "name" } },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
          },
        },
      }

      local symbols = extractor.extract_symbols(ast, "/test.tcl")

      assert.equals(1, #symbols)
      assert.equals("proc", symbols[1].type)
      assert.equals("greet", symbols[1].name)
      assert.equals("::greet", symbols[1].qualified_name)
      assert.equals("/test.tcl", symbols[1].file)
    end)

    it("should extract procs within namespaces", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "math",
            body = {
              children = {
                {
                  type = "proc",
                  name = "add",
                  params = {},
                  range = { start = { line = 2, col = 1 }, end_pos = { line = 4, col = 1 } },
                },
              },
            },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
          },
        },
      }

      local symbols = extractor.extract_symbols(ast, "/math.tcl")

      assert.equals(2, #symbols) -- namespace + proc
      local proc = vim.tbl_filter(function(s)
        return s.type == "proc"
      end, symbols)[1]
      assert.equals("::math::add", proc.qualified_name)
      assert.equals("::math", proc.scope)
    end)

    it("should extract variable definitions from set", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "set",
            var_name = "config",
            value = "default",
            range = { start = { line = 1, col = 1 }, end_pos = { line = 1, col = 20 } },
          },
        },
      }

      local symbols = extractor.extract_symbols(ast, "/init.tcl")

      assert.equals(1, #symbols)
      assert.equals("variable", symbols[1].type)
      assert.equals("config", symbols[1].name)
      assert.equals("::config", symbols[1].qualified_name)
    end)

    it("should extract variable declarations", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "variable",
            name = "counter",
            range = { start = { line = 1, col = 1 }, end_pos = { line = 1, col = 16 } },
          },
        },
      }

      local symbols = extractor.extract_symbols(ast, "/vars.tcl")

      assert.equals(1, #symbols)
      assert.equals("variable", symbols[1].type)
      assert.equals("counter", symbols[1].name)
      assert.equals("::counter", symbols[1].qualified_name)
    end)

    it("should handle empty AST", function()
      local ast = {
        type = "root",
        children = {},
      }

      local symbols = extractor.extract_symbols(ast, "/empty.tcl")

      assert.equals(0, #symbols)
    end)

    it("should handle nil AST gracefully", function()
      local symbols = extractor.extract_symbols(nil, "/nil.tcl")

      assert.equals(0, #symbols)
    end)

    it("should extract nested namespace procs", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "outer",
            body = {
              children = {
                {
                  type = "namespace_eval",
                  name = "inner",
                  body = {
                    children = {
                      {
                        type = "proc",
                        name = "deep",
                        params = {},
                        range = { start = { line = 3, col = 1 }, end_pos = { line = 5, col = 1 } },
                      },
                    },
                  },
                  range = { start = { line = 2, col = 1 }, end_pos = { line = 6, col = 1 } },
                },
              },
            },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 7, col = 1 } },
          },
        },
      }

      local symbols = extractor.extract_symbols(ast, "/nested.tcl")

      assert.equals(3, #symbols) -- outer namespace + inner namespace + proc
      local proc = vim.tbl_filter(function(s)
        return s.type == "proc"
      end, symbols)[1]
      assert.equals("::outer::inner::deep", proc.qualified_name)
      assert.equals("::outer::inner", proc.scope)
    end)

    it("should include params for procs", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "calculate",
            params = { { name = "x" }, { name = "y" }, { name = "z" } },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
          },
        },
      }

      local symbols = extractor.extract_symbols(ast, "/calc.tcl")

      assert.equals(1, #symbols)
      assert.equals(3, #symbols[1].params)
      assert.equals("x", symbols[1].params[1].name)
      assert.equals("y", symbols[1].params[2].name)
      assert.equals("z", symbols[1].params[3].name)
    end)

    it("should not crash on deeply nested AST (depth guard)", function()
      -- Build an AST nested 100 levels deep (exceeds MAX_DEPTH=50)
      local node = { type = "root", children = {} }
      local current = node
      for i = 1, 100 do
        local child = {
          type = "namespace_eval",
          name = "ns" .. i,
          body = { children = {} },
          range = { start = { line = i, col = 1 }, end_pos = { line = i, col = 10 } },
        }
        table.insert(current.children or current.body.children, child)
        current = child
      end

      -- Should not error or hang — depth guard stops recursion
      local symbols = extractor.extract_symbols(node, "/deep.tcl")
      assert.is_table(symbols)
      -- Should have some but not all 100 namespaces (stops at depth 50)
      assert.is_true(#symbols < 100)
      assert.is_true(#symbols > 0)
    end)
  end)
end)
