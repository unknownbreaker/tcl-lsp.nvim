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

  describe("check_conflicts", function()
    local index

    before_each(function()
      -- Clear index first, then reload rename so it gets fresh index reference
      package.loaded["tcl-lsp.analyzer.index"] = nil
      package.loaded["tcl-lsp.features.rename"] = nil
      index = require("tcl-lsp.analyzer.index")
      index.clear()
      rename = require("tcl-lsp.features.rename")
    end)

    it("should detect conflict when name exists in same scope", function()
      -- Add existing symbol
      index.add_symbol({
        qualified_name = "::existingProc",
        name = "existingProc",
        type = "proc",
        file = "/test.tcl",
        scope = "::",
      })

      local has_conflict, msg = rename.check_conflicts("newName", "::", "existingProc")
      assert.is_false(has_conflict) -- No conflict with different name

      has_conflict, msg = rename.check_conflicts("existingProc", "::", "oldName")
      assert.is_true(has_conflict)
      assert.matches("existingProc", msg)
    end)

    it("should not conflict with same name in different scope", function()
      index.add_symbol({
        qualified_name = "::other::existingProc",
        name = "existingProc",
        type = "proc",
        file = "/test.tcl",
        scope = "::other",
      })

      local has_conflict = rename.check_conflicts("existingProc", "::", "oldName")
      assert.is_false(has_conflict)
    end)

    it("should not conflict when renaming to same name", function()
      index.add_symbol({
        qualified_name = "::myProc",
        name = "myProc",
        type = "proc",
        file = "/test.tcl",
        scope = "::",
      })

      -- Renaming myProc to myProc (same name) - current symbol itself
      local has_conflict = rename.check_conflicts("myProc", "::", "myProc")
      assert.is_false(has_conflict)
    end)
  end)
end)
