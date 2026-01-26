-- tests/lua/features/completion_spec.lua
describe("completion", function()
  local completion

  before_each(function()
    package.loaded["tcl-lsp.features.completion"] = nil
    completion = require("tcl-lsp.features.completion")
  end)

  describe("detect_context", function()
    it("detects variable context after $", function()
      assert.equals("variable", completion.detect_context("set x $", 7))
      assert.equals("variable", completion.detect_context("puts $foo", 9))
    end)

    it("detects variable context with partial name", function()
      assert.equals("variable", completion.detect_context("puts $var", 9))
    end)

    it("detects namespace context after ::", function()
      assert.equals("namespace", completion.detect_context("::ns::", 6))
      assert.equals("namespace", completion.detect_context("::foo::bar", 10))
    end)

    it("detects package context after package require", function()
      assert.equals("package", completion.detect_context("package require ", 16))
      assert.equals("package", completion.detect_context("package require htt", 19))
    end)

    it("returns command context by default", function()
      assert.equals("command", completion.detect_context("pu", 2))
      assert.equals("command", completion.detect_context("set x [for", 10))
    end)
  end)
end)
