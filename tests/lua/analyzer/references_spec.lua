-- tests/lua/analyzer/references_spec.lua
-- Tests for References Analyzer - finds all references to a symbol

describe("References Analyzer", function()
  local references
  local index

  before_each(function()
    package.loaded["tcl-lsp.analyzer.references"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil
    references = require("tcl-lsp.analyzer.references")
    index = require("tcl-lsp.analyzer.index")
    index.clear()
  end)

  describe("find_references", function()
    it("should return definition as first result", function()
      index.add_symbol({
        type = "proc",
        name = "helper",
        qualified_name = "::utils::helper",
        file = "/project/utils.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
        scope = "::utils",
      })

      local results = references.find_references("::utils::helper")

      assert.is_true(#results >= 1)
      assert.equals("definition", results[1].type)
      assert.equals("/project/utils.tcl", results[1].file)
    end)

    it("should group results by type: definition, export, call", function()
      index.add_symbol({
        type = "proc",
        name = "formatDate",
        qualified_name = "::utils::formatDate",
        file = "/project/utils.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
        scope = "::utils",
      })

      index.add_reference("::utils::formatDate", {
        type = "export",
        file = "/project/utils.tcl",
        range = { start = { line = 20, col = 1 }, end_pos = { line = 20, col = 30 } },
        text = "namespace export formatDate",
      })

      index.add_reference("::utils::formatDate", {
        type = "call",
        file = "/project/main.tcl",
        range = { start = { line = 15, col = 5 }, end_pos = { line = 15, col = 25 } },
        text = "::utils::formatDate $today",
      })

      local results = references.find_references("::utils::formatDate")

      assert.equals(3, #results)
      assert.equals("definition", results[1].type)
      assert.equals("export", results[2].type)
      assert.equals("call", results[3].type)
    end)

    it("should return empty list for unknown symbol", function()
      local results = references.find_references("::nonexistent::proc")

      assert.is_table(results)
      assert.equals(0, #results)
    end)

    it("should sort calls by file then line", function()
      index.add_symbol({
        type = "proc",
        name = "target",
        qualified_name = "::target",
        file = "/project/lib.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
        scope = "::",
      })

      -- Add calls in non-sorted order
      index.add_reference("::target", {
        type = "call",
        file = "/project/z_file.tcl",
        range = { start = { line = 10, col = 1 }, end_pos = { line = 10, col = 7 } },
        text = "target",
      })
      index.add_reference("::target", {
        type = "call",
        file = "/project/a_file.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 5, col = 7 } },
        text = "target",
      })
      index.add_reference("::target", {
        type = "call",
        file = "/project/a_file.tcl",
        range = { start = { line = 20, col = 1 }, end_pos = { line = 20, col = 7 } },
        text = "target",
      })

      local results = references.find_references("::target")

      -- Skip definition, check calls are sorted
      assert.equals("/project/a_file.tcl", results[2].file)
      assert.equals(5, results[2].range.start.line)
      assert.equals("/project/a_file.tcl", results[3].file)
      assert.equals(20, results[3].range.start.line)
      assert.equals("/project/z_file.tcl", results[4].file)
    end)
  end)
end)
