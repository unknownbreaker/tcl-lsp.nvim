-- tests/lua/analyzer/ref_extractor_spec.lua
-- Tests for Reference Extractor - extracts references (calls, exports) from AST

describe("Reference Extractor", function()
  local ref_extractor

  before_each(function()
    package.loaded["tcl-lsp.analyzer.ref_extractor"] = nil
    ref_extractor = require("tcl-lsp.analyzer.ref_extractor")
  end)

  describe("extract_references", function()
    it("should extract proc call references", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "command",
            name = "helper",
            args = { "$arg1", "$arg2" },
            range = { start = { line = 5, col = 1 }, end_pos = { line = 5, col = 20 } },
          },
        },
      }

      local refs = ref_extractor.extract_references(ast, "/test.tcl")

      assert.equals(1, #refs)
      assert.equals("call", refs[1].type)
      assert.equals("helper", refs[1].name)
      assert.equals("/test.tcl", refs[1].file)
    end)

    it("should extract namespace export references", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "utils",
            body = {
              children = {
                {
                  type = "namespace_export",
                  exports = { "formatDate", "validateInput" },
                  range = { start = { line = 10, col = 3 }, end_pos = { line = 10, col = 40 } },
                },
              },
            },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 20, col = 1 } },
          },
        },
      }

      local refs = ref_extractor.extract_references(ast, "/utils.tcl")

      assert.equals(2, #refs)
      assert.equals("export", refs[1].type)
      assert.equals("formatDate", refs[1].name)
      assert.equals("export", refs[2].type)
      assert.equals("validateInput", refs[2].name)
    end)

    it("should extract interp alias references", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "interp_alias",
            alias = "::shortName",
            target = "::full::longName",
            range = { start = { line = 3, col = 1 }, end_pos = { line = 3, col = 50 } },
          },
        },
      }

      local refs = ref_extractor.extract_references(ast, "/aliases.tcl")

      assert.equals(1, #refs)
      assert.equals("export", refs[1].type)
      assert.equals("::full::longName", refs[1].target)
    end)

    it("should track namespace context for unqualified calls", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "myns",
            body = {
              children = {
                {
                  type = "command",
                  name = "localProc",
                  args = {},
                  range = { start = { line = 5, col = 5 }, end_pos = { line = 5, col = 15 } },
                },
              },
            },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
          },
        },
      }

      local refs = ref_extractor.extract_references(ast, "/ns.tcl")

      assert.equals(1, #refs)
      assert.equals("::myns", refs[1].namespace)
    end)
  end)
end)
