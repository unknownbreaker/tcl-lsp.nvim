-- tests/lua/analyzer/visitor_spec.lua
-- Tests for shared AST visitor walk

describe("Visitor", function()
  local visitor

  before_each(function()
    package.loaded["tcl-lsp.analyzer.visitor"] = nil
    visitor = require("tcl-lsp.analyzer.visitor")
  end)

  describe("walk", function()
    it("should visit children", function()
      local visited = {}
      local ast = {
        type = "root",
        children = {
          { type = "set", var_name = "x", value = "1", range = {}, depth = 1 },
          { type = "set", var_name = "y", value = "2", range = {}, depth = 1 },
        },
      }

      visitor.walk(ast, {
        set = function(node)
          table.insert(visited, node.var_name)
        end,
      }, "test.tcl")

      assert.same({ "x", "y" }, visited)
    end)

    it("should visit body.children (procs)", function()
      local visited = {}
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "test",
            params = {},
            body = {
              children = {
                { type = "set", var_name = "inner", value = "1", range = {}, depth = 2 },
              },
            },
            range = {},
            depth = 1,
          },
        },
      }

      visitor.walk(ast, {
        set = function(node)
          table.insert(visited, node.var_name)
        end,
      }, "test.tcl")

      assert.same({ "inner" }, visited)
    end)

    it("should visit then_body children (if statements)", function()
      local visited = {}
      local ast = {
        type = "root",
        children = {
          {
            type = "if",
            condition = "1",
            then_body = {
              children = {
                { type = "set", var_name = "in_then", value = "1", range = {}, depth = 2 },
              },
            },
            range = {},
            depth = 1,
          },
        },
      }

      visitor.walk(ast, {
        set = function(node)
          table.insert(visited, node.var_name)
        end,
      }, "test.tcl")

      assert.same({ "in_then" }, visited)
    end)

    it("should visit else_body children (if-else)", function()
      local visited = {}
      local ast = {
        type = "root",
        children = {
          {
            type = "if",
            condition = "1",
            then_body = { children = {} },
            else_body = {
              children = {
                { type = "set", var_name = "in_else", value = "1", range = {}, depth = 2 },
              },
            },
            range = {},
            depth = 1,
          },
        },
      }

      visitor.walk(ast, {
        set = function(node)
          table.insert(visited, node.var_name)
        end,
      }, "test.tcl")

      assert.same({ "in_else" }, visited)
    end)

    it("should visit elseif branch bodies", function()
      local visited = {}
      local ast = {
        type = "root",
        children = {
          {
            type = "if",
            condition = "1",
            then_body = { children = {} },
            ["elseif"] = {
              {
                condition = "2",
                body = {
                  children = {
                    { type = "set", var_name = "in_elseif", value = "1", range = {}, depth = 2 },
                  },
                },
              },
            },
            range = {},
            depth = 1,
          },
        },
      }

      visitor.walk(ast, {
        set = function(node)
          table.insert(visited, node.var_name)
        end,
      }, "test.tcl")

      assert.same({ "in_elseif" }, visited)
    end)

    it("should visit switch case bodies", function()
      local visited = {}
      local ast = {
        type = "root",
        children = {
          {
            type = "switch",
            expression = "$x",
            cases = {
              {
                pattern = "a",
                body = {
                  children = {
                    { type = "set", var_name = "in_case", value = "1", range = {}, depth = 2 },
                  },
                },
              },
            },
            range = {},
            depth = 1,
          },
        },
      }

      visitor.walk(ast, {
        set = function(node)
          table.insert(visited, node.var_name)
        end,
      }, "test.tcl")

      assert.same({ "in_case" }, visited)
    end)

    it("should track namespace through namespace_eval", function()
      local namespaces = {}
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "foo",
            body = {
              children = {
                { type = "set", var_name = "x", value = "1", range = {}, depth = 2 },
              },
            },
            range = {},
            depth = 1,
          },
        },
      }

      visitor.walk(ast, {
        set = function(_, ctx)
          table.insert(namespaces, ctx.namespace)
        end,
      }, "test.tcl")

      assert.same({ "::foo" }, namespaces)
    end)
  end)
end)
