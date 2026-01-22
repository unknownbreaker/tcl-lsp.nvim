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

  describe("reference tracking", function()
    it("should add references to a symbol", function()
      index.add_symbol({
        type = "proc",
        name = "helper",
        qualified_name = "::utils::helper",
        file = "/project/utils.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
        scope = "::utils",
      })

      index.add_reference("::utils::helper", {
        type = "call",
        file = "/project/main.tcl",
        range = { start = { line = 20, col = 5 }, end_pos = { line = 20, col = 11 } },
        text = "helper $arg",
      })

      local refs = index.get_references("::utils::helper")
      assert.equals(1, #refs)
      assert.equals("call", refs[1].type)
      assert.equals("/project/main.tcl", refs[1].file)
    end)

    it("should return empty list for symbol with no references", function()
      index.add_symbol({
        type = "proc",
        name = "unused",
        qualified_name = "::unused",
        file = "/project/lib.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
        scope = "::",
      })

      local refs = index.get_references("::unused")
      assert.is_table(refs)
      assert.equals(0, #refs)
    end)

    it("should remove references when file is removed", function()
      index.add_symbol({
        type = "proc",
        name = "target",
        qualified_name = "::target",
        file = "/project/target.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
        scope = "::",
      })

      index.add_reference("::target", {
        type = "call",
        file = "/project/caller.tcl",
        range = { start = { line = 10, col = 1 }, end_pos = { line = 10, col = 7 } },
        text = "target",
      })

      index.remove_file("/project/caller.tcl")

      local refs = index.get_references("::target")
      assert.equals(0, #refs)
    end)
  end)
end)
