-- tests/lua/analyzer/docs_spec.lua
-- Tests for documentation extraction utilities

describe("Docs Analyzer", function()
  local docs

  before_each(function()
    package.loaded["tcl-lsp.analyzer.docs"] = nil
    docs = require("tcl-lsp.analyzer.docs")
  end)

  describe("extract_comments", function()
    it("should return nil when no comments above target line", function()
      local lines = {
        "set x 1",
        "proc foo {} {",
        "    puts hello",
        "}",
      }

      local result = docs.extract_comments(lines, 2) -- line 2 is "proc foo"

      assert.is_nil(result)
    end)

    it("should extract single-line comment", function()
      local lines = {
        "# This is a description",
        "proc foo {} {",
        "    puts hello",
        "}",
      }

      local result = docs.extract_comments(lines, 2)

      assert.is_not_nil(result)
      assert.equals("This is a description", result)
    end)

    it("should extract multi-line contiguous comment block", function()
      local lines = {
        "# This function does something",
        "# very important and useful.",
        "# It returns a value.",
        "proc foo {} {",
        "    return 42",
        "}",
      }

      local result = docs.extract_comments(lines, 4)

      assert.is_not_nil(result)
      assert.equals(
        "This function does something\nvery important and useful.\nIt returns a value.",
        result
      )
    end)

    it("should stop at blank line", function()
      local lines = {
        "# Unrelated comment",
        "",
        "# Actual doc comment",
        "proc foo {} {",
        "    return 42",
        "}",
      }

      local result = docs.extract_comments(lines, 4)

      assert.is_not_nil(result)
      assert.equals("Actual doc comment", result)
    end)

    it("should stop at non-comment line", function()
      local lines = {
        "set x 1",
        "# This is the doc",
        "proc foo {} {",
        "    return 42",
        "}",
      }

      local result = docs.extract_comments(lines, 3)

      assert.is_not_nil(result)
      assert.equals("This is the doc", result)
    end)

    it("should preserve blank lines within comment block", function()
      local lines = {
        "# First paragraph",
        "#",
        "# Second paragraph",
        "proc foo {} {",
        "    return 42",
        "}",
      }

      local result = docs.extract_comments(lines, 4)

      assert.is_not_nil(result)
      assert.equals("First paragraph\n\nSecond paragraph", result)
    end)

    it("should handle comments with no space after hash", function()
      local lines = {
        "#No space after hash",
        "proc foo {} {",
        "    return 42",
        "}",
      }

      local result = docs.extract_comments(lines, 2)

      assert.is_not_nil(result)
      assert.equals("No space after hash", result)
    end)

    it("should handle indented comments", function()
      local lines = {
        "    # Indented comment",
        "    proc foo {} {",
        "        return 42",
        "    }",
      }

      local result = docs.extract_comments(lines, 2)

      assert.is_not_nil(result)
      assert.equals("Indented comment", result)
    end)

    it("should return nil for line 1 (no lines above)", function()
      local lines = {
        "proc foo {} {",
        "    return 42",
        "}",
      }

      local result = docs.extract_comments(lines, 1)

      assert.is_nil(result)
    end)
  end)

  describe("get_initial_value", function()
    it("should extract value from simple set command", function()
      local ast = {
        type = "script",
        children = {
          {
            type = "set",
            var_name = "timeout",
            value = "30",
            range = { start = { line = 1, col = 1 }, end_pos = { line = 1, col = 14 } },
          },
        },
      }

      local result = docs.get_initial_value(ast, "timeout")

      assert.is_not_nil(result)
      assert.equals("30", result)
    end)

    it("should return nil when variable not found", function()
      local ast = {
        type = "script",
        children = {
          {
            type = "set",
            var_name = "other_var",
            value = "hello",
            range = { start = { line = 1, col = 1 }, end_pos = { line = 1, col = 18 } },
          },
        },
      }

      local result = docs.get_initial_value(ast, "timeout")

      assert.is_nil(result)
    end)

    it("should find variable in nested structure", function()
      local ast = {
        type = "script",
        children = {
          {
            type = "namespace_eval",
            name = "config",
            body = {
              children = {
                {
                  type = "set",
                  var_name = "debug",
                  value = "true",
                  range = { start = { line = 2, col = 5 }, end_pos = { line = 2, col = 18 } },
                },
              },
            },
          },
        },
      }

      local result = docs.get_initial_value(ast, "debug")

      assert.is_not_nil(result)
      assert.equals("true", result)
    end)

    it("should handle variable with string value", function()
      local ast = {
        type = "script",
        children = {
          {
            type = "set",
            var_name = "message",
            value = '"Hello, World!"',
            range = { start = { line = 1, col = 1 }, end_pos = { line = 1, col = 28 } },
          },
        },
      }

      local result = docs.get_initial_value(ast, "message")

      assert.is_not_nil(result)
      assert.equals('"Hello, World!"', result)
    end)

    it("should return nil for empty AST", function()
      local ast = { type = "script", children = {} }

      local result = docs.get_initial_value(ast, "any_var")

      assert.is_nil(result)
    end)

    it("should handle nil AST gracefully", function()
      local result = docs.get_initial_value(nil, "any_var")

      assert.is_nil(result)
    end)
  end)
end)
