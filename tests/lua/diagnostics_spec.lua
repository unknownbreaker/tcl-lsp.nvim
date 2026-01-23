describe("diagnostics", function()
  local diagnostics

  before_each(function()
    package.loaded["tcl-lsp.features.diagnostics"] = nil
    diagnostics = require("tcl-lsp.features.diagnostics")
  end)

  describe("module structure", function()
    it("exports setup function", function()
      assert.is_function(diagnostics.setup)
    end)

    it("exports check_buffer function", function()
      assert.is_function(diagnostics.check_buffer)
    end)

    it("exports clear function", function()
      assert.is_function(diagnostics.clear)
    end)
  end)
end)
