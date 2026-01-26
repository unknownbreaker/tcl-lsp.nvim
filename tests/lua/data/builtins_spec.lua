describe("builtins", function()
  local builtins

  before_each(function()
    builtins = require("tcl-lsp.data.builtins")
  end)

  after_each(function()
    package.loaded["tcl-lsp.data.builtins"] = nil
  end)

  it("returns a table", function()
    assert.is_table(builtins)
  end)

  it("contains common TCL commands", function()
    local names = {}
    for _, item in ipairs(builtins) do
      names[item.name] = true
    end
    assert.is_true(names["puts"])
    assert.is_true(names["set"])
    assert.is_true(names["if"])
    assert.is_true(names["proc"])
    assert.is_true(names["foreach"])
  end)

  it("has required fields for each item", function()
    for _, item in ipairs(builtins) do
      assert.is_string(item.name)
      assert.equals("builtin", item.type)
    end
  end)

  it("contains at least 50 commands", function()
    assert.is_true(#builtins >= 50)
  end)
end)
