-- tests/lua/features/rename_spec.lua
-- Tests for rename feature

describe("Rename Feature", function()
  local rename

  before_each(function()
    package.loaded["tcl-lsp.features.rename"] = nil
    rename = require("tcl-lsp.features.rename")
  end)

  describe("validate_name", function()
    it("should reject empty names", function()
      local ok, err = rename.validate_name("")
      assert.is_false(ok)
      assert.matches("empty", err)
    end)

    it("should reject whitespace-only names", function()
      local ok, err = rename.validate_name("   ")
      assert.is_false(ok)
      assert.matches("empty", err)
    end)

    it("should reject names with spaces", function()
      local ok, err = rename.validate_name("my proc")
      assert.is_false(ok)
      assert.matches("invalid", err:lower())
    end)

    it("should accept valid identifier", function()
      local ok, err = rename.validate_name("myProc")
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("should accept underscores", function()
      local ok, err = rename.validate_name("my_proc_name")
      assert.is_true(ok)
    end)

    it("should accept namespaced names", function()
      local ok, err = rename.validate_name("::utils::helper")
      assert.is_true(ok)
    end)

    it("should reject special characters", function()
      local ok, err = rename.validate_name("proc@name")
      assert.is_false(ok)
    end)

    it("should reject single colon (not part of ::)", function()
      local ok, err = rename.validate_name("my:proc")
      assert.is_false(ok)
      assert.matches("namespace", err:lower())
    end)

    it("should reject triple colon", function()
      local ok, err = rename.validate_name("my:::proc")
      assert.is_false(ok)
      assert.matches("namespace", err:lower())
    end)

    it("should reject mixed valid :: with invalid single colon", function()
      local ok, err = rename.validate_name("::my:proc")
      assert.is_false(ok)
      assert.matches("namespace", err:lower())
    end)

    it("should reject leading single colon", function()
      local ok, err = rename.validate_name(":start")
      assert.is_false(ok)
      assert.matches("namespace", err:lower())
    end)

    it("should reject trailing single colon", function()
      local ok, err = rename.validate_name("end:")
      assert.is_false(ok)
      assert.matches("namespace", err:lower())
    end)
  end)
end)
