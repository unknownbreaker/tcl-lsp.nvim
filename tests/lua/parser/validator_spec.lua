-- tests/lua/parser/validator_spec.lua
-- Validator Module Tests - TDD Phase (RED)
-- Tests for AST schema validation

describe("AST Validator Module", function()
  local validator
  local schema

  before_each(function()
    package.loaded["tcl-lsp.parser.validator"] = nil
    package.loaded["tcl-lsp.parser.schema"] = nil
    validator = require "tcl-lsp.parser.validator"
    schema = require "tcl-lsp.parser.schema"
  end)

  describe("validate_node", function()
    it("should validate a valid proc node", function()
      local node = {
        type = "proc",
        name = "test_proc",
        params = {},
        body = { children = {} },
        range = {
          start = { line = 1, column = 1 },
          end_pos = { line = 5, column = 1 },
        },
        depth = 0,
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_table(result)
      assert.is_true(result.valid, "Valid proc node should pass validation")
      assert.is_table(result.errors)
      assert.equals(0, #result.errors)
    end)

    it("should detect missing required type field", function()
      local node = {
        name = "test_proc",
        params = {},
        body = { children = {} },
        range = {
          start = { line = 1, column = 1 },
          end_pos = { line = 5, column = 1 },
        },
        depth = 0,
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_false(result.valid)
      assert.is_true(#result.errors > 0)
      assert.matches("type", result.errors[1].message:lower())
    end)

    it("should detect unknown node type", function()
      local node = {
        type = "unknown_node_type",
        name = "test",
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_false(result.valid)
      assert.matches("unknown", result.errors[1].message:lower())
    end)

    it("should detect missing required fields", function()
      local node = {
        type = "proc",
        -- missing: name, params, body, range, depth
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_false(result.valid)
      assert.is_true(#result.errors >= 1)
    end)

    it("should detect type mismatch for string field", function()
      local node = {
        type = "proc",
        name = 123, -- should be string
        params = {},
        body = { children = {} },
        range = {
          start = { line = 1, column = 1 },
          end_pos = { line = 5, column = 1 },
        },
        depth = 0,
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_false(result.valid)
      assert.matches("name", result.errors[1].message:lower())
    end)

    it("should detect type mismatch for array field", function()
      local node = {
        type = "proc",
        name = "test",
        params = "not an array", -- should be array
        body = { children = {} },
        range = {
          start = { line = 1, column = 1 },
          end_pos = { line = 5, column = 1 },
        },
        depth = 0,
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_false(result.valid)
      assert.matches("params", result.errors[1].message:lower())
    end)

    it("should validate nested range structure", function()
      local node = {
        type = "set",
        var_name = "x",
        value = "10",
        range = {
          start = { line = "not a number", column = 1 }, -- should be number
          end_pos = { line = 1, column = 1 },
        },
        depth = 0,
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_false(result.valid)
      assert.is_true(#result.errors > 0)
    end)

    it("should allow optional fields to be missing", function()
      local node = {
        type = "variable",
        name = "x",
        -- value is optional
        range = {
          start = { line = 1, column = 1 },
          end_pos = { line = 1, column = 10 },
        },
        depth = 0,
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_true(result.valid)
    end)

    it("should include path in error messages", function()
      local node = {
        type = "proc",
        name = 123, -- invalid type
        params = {},
        body = { children = {} },
        range = {
          start = { line = 1, column = 1 },
          end_pos = { line = 5, column = 1 },
        },
        depth = 0,
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_false(result.valid)
      assert.is_not_nil(result.errors[1].path)
      assert.matches("root.children%[1%]", result.errors[1].path)
    end)
  end)

  describe("validate_ast", function()
    it("should validate empty root node", function()
      local ast = {
        type = "root",
        children = {},
      }

      local result = validator.validate_ast(ast)
      assert.is_table(result)
      assert.is_true(result.valid)
      assert.is_table(result.errors)
      assert.equals(0, #result.errors)
    end)

    it("should validate root with valid children", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "set",
            var_name = "x",
            value = "10",
            range = {
              start = { line = 1, column = 1 },
              end_pos = { line = 1, column = 10 },
            },
            depth = 0,
          },
        },
      }

      local result = validator.validate_ast(ast)
      assert.is_true(result.valid)
    end)

    it("should detect errors in child nodes", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "set",
            var_name = 123, -- invalid: should be string
            value = "10",
            range = {
              start = { line = 1, column = 1 },
              end_pos = { line = 1, column = 10 },
            },
            depth = 0,
          },
        },
      }

      local result = validator.validate_ast(ast)
      assert.is_false(result.valid)
      assert.is_true(#result.errors > 0)
    end)

    it("should validate deeply nested structures", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "test",
            params = {},
            body = {
              children = {
                {
                  type = "if",
                  condition = "$x > 0",
                  then_body = {
                    children = {
                      {
                        type = "puts",
                        args = { "hello" },
                        range = {
                          start = { line = 3, column = 5 },
                          end_pos = { line = 3, column = 20 },
                        },
                        depth = 2,
                      },
                    },
                  },
                  range = {
                    start = { line = 2, column = 1 },
                    end_pos = { line = 4, column = 1 },
                  },
                  depth = 1,
                },
              },
            },
            range = {
              start = { line = 1, column = 1 },
              end_pos = { line = 5, column = 1 },
            },
            depth = 0,
          },
        },
      }

      local result = validator.validate_ast(ast)
      assert.is_true(result.valid)
    end)

    it("should collect all errors in strict mode", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "set",
            var_name = 123, -- error 1
            value = "10",
            range = {
              start = { line = 1, column = 1 },
              end_pos = { line = 1, column = 10 },
            },
            depth = 0,
          },
          {
            type = "proc",
            name = 456, -- error 2
            params = {},
            body = { children = {} },
            range = {
              start = { line = 2, column = 1 },
              end_pos = { line = 3, column = 1 },
            },
            depth = 0,
          },
        },
      }

      local result = validator.validate_ast(ast, { strict = true })
      assert.is_false(result.valid)
      assert.is_true(#result.errors >= 2, "Should collect all errors in strict mode")
    end)

    it("should stop at first error in fast mode", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "set",
            var_name = 123, -- error 1
            value = "10",
            range = {
              start = { line = 1, column = 1 },
              end_pos = { line = 1, column = 10 },
            },
            depth = 0,
          },
          {
            type = "proc",
            name = 456, -- error 2 (should not be checked)
            params = {},
            body = { children = {} },
            range = {
              start = { line = 2, column = 1 },
              end_pos = { line = 3, column = 1 },
            },
            depth = 0,
          },
        },
      }

      local result = validator.validate_ast(ast, { strict = false })
      assert.is_false(result.valid)
      assert.equals(1, #result.errors, "Should stop at first error in fast mode")
    end)
  end)

  describe("validate_file (integration)", function()
    local temp_dir

    before_each(function()
      temp_dir = vim.fn.tempname()
      vim.fn.mkdir(temp_dir, "p")
    end)

    after_each(function()
      if temp_dir then
        vim.fn.delete(temp_dir, "rf")
      end
    end)

    it("should validate a simple TCL file", function()
      local file_path = temp_dir .. "/test.tcl"
      local file = io.open(file_path, "w")
      file:write('set x "hello"\n')
      file:close()

      local result = validator.validate_file(file_path)
      assert.is_table(result)
      -- Result may be valid or invalid depending on parser output
      assert.is_not_nil(result.valid)
      assert.is_table(result.errors)
    end)

    it("should return error for non-existent file", function()
      local result = validator.validate_file "/nonexistent/file.tcl"
      assert.is_false(result.valid)
      assert.is_true(#result.errors > 0)
      assert.matches("file", result.errors[1].message:lower())
    end)
  end)

  describe("error formatting", function()
    it("should format errors with path, message, and node type", function()
      local node = {
        type = "proc",
        name = 123,
        params = {},
        body = { children = {} },
        range = {
          start = { line = 1, column = 1 },
          end_pos = { line = 5, column = 1 },
        },
        depth = 0,
      }

      local result = validator.validate_node(node, "root.children[1]")
      assert.is_false(result.valid)

      local error = result.errors[1]
      assert.is_table(error)
      assert.is_string(error.message)
      assert.is_string(error.path)
      assert.equals("proc", error.node_type)
    end)
  end)
end)
