-- tests/lua/utils/variable_spec.lua
-- Tests for shared variable utilities

describe("Variable Utils", function()
  local variable

  before_each(function()
    package.loaded["tcl-lsp.utils.variable"] = nil
    variable = require("tcl-lsp.utils.variable")
  end)

  describe("safe_var_name", function()
    it("should return string as-is", function()
      assert.equals("count", variable.safe_var_name("count"))
    end)

    it("should extract name from table with name field", function()
      assert.equals("arr", variable.safe_var_name({ name = "arr", key = "$x" }))
    end)

    it("should return nil for table without name field", function()
      assert.is_nil(variable.safe_var_name({ key = "$x" }))
    end)

    it("should return nil for nil", function()
      assert.is_nil(variable.safe_var_name(nil))
    end)

    it("should return nil for number", function()
      assert.is_nil(variable.safe_var_name(42))
    end)

    it("should return nil for boolean", function()
      assert.is_nil(variable.safe_var_name(true))
    end)

    it("should handle empty string", function()
      assert.equals("", variable.safe_var_name(""))
    end)

    it("should handle empty table", function()
      assert.is_nil(variable.safe_var_name({}))
    end)
  end)

  describe("extract_variable_name", function()
    it("should return non-$ words unchanged", function()
      assert.equals("puts", variable.extract_variable_name("puts"))
    end)

    it("should strip $ prefix", function()
      assert.equals("var", variable.extract_variable_name("$var"))
    end)

    it("should handle braced variables", function()
      assert.equals("varname", variable.extract_variable_name("${varname}"))
    end)

    it("should handle braced namespace variables", function()
      assert.equals("ns::var", variable.extract_variable_name("${ns::var}"))
    end)

    it("should handle unclosed brace (best effort)", function()
      assert.equals("var", variable.extract_variable_name("${var"))
    end)

    it("should extract array name from $arr(key)", function()
      assert.equals("arr", variable.extract_variable_name("$arr(key)"))
    end)

    it("should handle qualified variables", function()
      assert.equals("::ns::var", variable.extract_variable_name("$::ns::var"))
    end)

    it("should handle simple single-char variable", function()
      assert.equals("x", variable.extract_variable_name("$x"))
    end)
  end)
end)
