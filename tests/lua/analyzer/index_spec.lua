-- tests/lua/analyzer/index_spec.lua
-- Tests for Symbol Index - core data structure for storing and looking up symbol definitions

describe("Symbol Index", function()
  local index

  before_each(function()
    package.loaded["tcl-lsp.analyzer.index"] = nil
    index = require("tcl-lsp.analyzer.index")
    index.clear()
  end)

  describe("add_symbol", function()
    it("should store a proc symbol", function()
      local symbol = {
        type = "proc",
        name = "add",
        qualified_name = "::math::add",
        file = "/project/math.tcl",
        range = { start = { line = 10, col = 1 }, end_pos = { line = 20, col = 1 } },
        scope = "::math",
      }

      index.add_symbol(symbol)
      local found = index.find("::math::add")

      assert.is_not_nil(found)
      assert.equals("proc", found.type)
      assert.equals("add", found.name)
      assert.equals("/project/math.tcl", found.file)
    end)
  end)

  describe("find", function()
    it("should return nil for unknown symbol", function()
      local found = index.find("::unknown::symbol")
      assert.is_nil(found)
    end)
  end)

  describe("remove_file", function()
    it("should remove all symbols from a file", function()
      index.add_symbol({
        qualified_name = "::math::add",
        file = "/project/math.tcl",
        type = "proc",
        name = "add",
      })
      index.add_symbol({
        qualified_name = "::math::subtract",
        file = "/project/math.tcl",
        type = "proc",
        name = "subtract",
      })
      index.add_symbol({
        qualified_name = "::utils::helper",
        file = "/project/utils.tcl",
        type = "proc",
        name = "helper",
      })

      index.remove_file("/project/math.tcl")

      assert.is_nil(index.find("::math::add"))
      assert.is_nil(index.find("::math::subtract"))
      assert.is_not_nil(index.find("::utils::helper"))
    end)
  end)
end)
