describe("packages", function()
  local packages

  before_each(function()
    packages = require("tcl-lsp.data.packages")
  end)

  after_each(function()
    package.loaded["tcl-lsp.data.packages"] = nil
  end)

  it("returns a table", function()
    assert.is_table(packages)
  end)

  it("contains common TCL packages", function()
    local names = {}
    for _, name in ipairs(packages) do
      names[name] = true
    end
    assert.is_true(names["Tcl"])
    assert.is_true(names["http"])
    assert.is_true(names["json"])
  end)

  it("contains only strings", function()
    for _, name in ipairs(packages) do
      assert.is_string(name)
    end
  end)

  it("contains at least 15 packages", function()
    assert.is_true(#packages >= 15)
  end)
end)
