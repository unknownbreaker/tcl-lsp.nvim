-- tests/lua/parser/scope_spec.lua
-- Tests for Scope Context Builder - extracts scope context from cursor position

describe("Scope Context", function()
  local scope

  before_each(function()
    package.loaded["tcl-lsp.parser.scope"] = nil
    scope = require("tcl-lsp.parser.scope")
  end)

  describe("get_context", function()
    it("should return global namespace at top level", function()
      local ast = {
        type = "root",
        children = {},
        range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
      }

      local ctx = scope.get_context(ast, 5, 1)

      assert.equals("::", ctx.namespace)
      assert.is_nil(ctx.proc)
      assert.same({}, ctx.locals)
    end)

    it("should detect namespace context", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "math",
            range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
            body = { children = {} },
          },
        },
      }

      local ctx = scope.get_context(ast, 5, 1)

      assert.equals("::math", ctx.namespace)
    end)

    it("should detect proc context with params as locals", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "greet",
            params = { { name = "name" }, { name = "greeting", default = "hello" } },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
            body = { children = {} },
          },
        },
      }

      local ctx = scope.get_context(ast, 3, 1)

      assert.equals("greet", ctx.proc)
      assert.same({ "name", "greeting" }, ctx.locals)
    end)

    it("should detect nested namespace context", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "outer",
            range = { start = { line = 1, col = 1 }, end_pos = { line = 20, col = 1 } },
            body = {
              children = {
                {
                  type = "namespace_eval",
                  name = "inner",
                  range = { start = { line = 5, col = 1 }, end_pos = { line = 15, col = 1 } },
                  body = { children = {} },
                },
              },
            },
          },
        },
      }

      local ctx = scope.get_context(ast, 10, 1)

      assert.equals("::outer::inner", ctx.namespace)
    end)

    it("should detect proc inside namespace", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "utils",
            range = { start = { line = 1, col = 1 }, end_pos = { line = 20, col = 1 } },
            body = {
              children = {
                {
                  type = "proc",
                  name = "helper",
                  params = { { name = "arg1" } },
                  range = { start = { line = 5, col = 1 }, end_pos = { line = 15, col = 1 } },
                  body = { children = {} },
                },
              },
            },
          },
        },
      }

      local ctx = scope.get_context(ast, 10, 1)

      assert.equals("::utils", ctx.namespace)
      assert.equals("helper", ctx.proc)
      assert.same({ "arg1" }, ctx.locals)
    end)

    it("should include set variables as locals inside proc", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "calculate",
            params = { { name = "x" } },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
            body = {
              children = {
                {
                  type = "set",
                  var_name = "result",
                  range = { start = { line = 3, col = 1 }, end_pos = { line = 3, col = 15 } },
                },
              },
            },
          },
        },
      }

      local ctx = scope.get_context(ast, 5, 1)

      assert.equals("calculate", ctx.proc)
      assert.is_true(vim.tbl_contains(ctx.locals, "x"))
      assert.is_true(vim.tbl_contains(ctx.locals, "result"))
    end)

    it("should track global declarations", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "test",
            params = {},
            range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
            body = {
              children = {
                {
                  type = "global",
                  vars = { "config", "settings" },
                  range = { start = { line = 2, col = 1 }, end_pos = { line = 2, col = 25 } },
                },
              },
            },
          },
        },
      }

      local ctx = scope.get_context(ast, 5, 1)

      assert.same({ "config", "settings" }, ctx.globals)
    end)

    it("should track upvar declarations", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "modify",
            params = { { name = "varname" } },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
            body = {
              children = {
                {
                  type = "upvar",
                  level = 1,
                  other_var = "varname",
                  local_var = "local_ref",
                  range = { start = { line = 2, col = 1 }, end_pos = { line = 2, col = 30 } },
                },
              },
            },
          },
        },
      }

      local ctx = scope.get_context(ast, 5, 1)

      assert.is_not_nil(ctx.upvars["local_ref"])
      assert.equals(1, ctx.upvars["local_ref"].level)
      assert.equals("varname", ctx.upvars["local_ref"].other_var)
    end)

    it("should handle nil AST gracefully", function()
      local ctx = scope.get_context(nil, 5, 1)

      assert.equals("::", ctx.namespace)
      assert.is_nil(ctx.proc)
      assert.same({}, ctx.locals)
    end)

    it("should handle position outside all ranges", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "first",
            params = {},
            range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
            body = { children = {} },
          },
        },
      }

      -- Position after the proc
      local ctx = scope.get_context(ast, 100, 1)

      assert.equals("::", ctx.namespace)
      assert.is_nil(ctx.proc)
    end)
  end)
end)
