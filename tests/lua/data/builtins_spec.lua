describe("builtins", function()
  local builtins

  before_each(function()
    package.loaded["tcl-lsp.data.builtins"] = nil
    builtins = require("tcl-lsp.data.builtins")
  end)

  it("returns a module table", function()
    assert.is_table(builtins)
    assert.is_table(builtins.list)
    assert.is_table(builtins.is_builtin)
  end)

  it("contains common TCL commands", function()
    local names = {}
    for _, item in ipairs(builtins.list) do
      names[item.name] = true
    end
    assert.is_true(names["puts"])
    assert.is_true(names["set"])
    assert.is_true(names["if"])
    assert.is_true(names["proc"])
    assert.is_true(names["foreach"])
  end)

  it("has required fields for each item", function()
    for _, item in ipairs(builtins.list) do
      assert.is_string(item.name)
      assert.equals("builtin", item.type)
    end
  end)

  it("contains at least 50 commands", function()
    assert.is_true(#builtins.list >= 50)
  end)

  describe("is_builtin lookup", function()
    it("should return true for known builtins", function()
      assert.is_true(builtins.is_builtin["puts"])
      assert.is_true(builtins.is_builtin["set"])
      assert.is_true(builtins.is_builtin["if"])
      assert.is_true(builtins.is_builtin["proc"])
    end)

    it("should return nil for non-builtins", function()
      assert.is_nil(builtins.is_builtin["my_custom_proc"])
      assert.is_nil(builtins.is_builtin[""])
    end)

    it("should have same count as list", function()
      local count = 0
      for _ in pairs(builtins.is_builtin) do
        count = count + 1
      end
      assert.equals(#builtins.list, count)
    end)
  end)
end)
