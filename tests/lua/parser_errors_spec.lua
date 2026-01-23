describe("parser.parse_with_errors", function()
  local parser = require("tcl-lsp.parser")

  it("returns empty errors for valid code", function()
    local result = parser.parse_with_errors("set x 1", "test.tcl")
    assert.is_table(result)
    assert.is_table(result.errors)
    assert.equals(0, #result.errors)
    assert.is_table(result.ast)
  end)

  it("returns errors with ranges for invalid code", function()
    local result = parser.parse_with_errors("if", "test.tcl")
    assert.is_table(result)
    assert.is_table(result.errors)
    assert.is_true(#result.errors > 0)
    assert.is_string(result.errors[1].message)
  end)

  it("handles empty input", function()
    local result = parser.parse_with_errors("", "test.tcl")
    assert.is_table(result)
    assert.equals(0, #result.errors)
  end)

  it("handles whitespace-only input", function()
    local result = parser.parse_with_errors("   \n\n  ", "test.tcl")
    assert.is_table(result)
    assert.equals(0, #result.errors)
  end)

  it("includes range information when available", function()
    local result = parser.parse_with_errors("if", "test.tcl")
    if result.errors[1] and result.errors[1].range then
      assert.is_table(result.errors[1].range)
    end
  end)
end)
