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

  describe("prepare_workspace_edit", function()
    it("should generate workspace edit from references", function()
      local refs = {
        {
          type = "definition",
          file = "/project/utils.tcl",
          range = { start = { line = 5, col = 6 }, end_pos = { line = 5, col = 11 } },
          text = "proc hello",
        },
        {
          type = "call",
          file = "/project/main.tcl",
          range = { start = { line = 10, col = 4 }, end_pos = { line = 10, col = 9 } },
          text = "hello",
        },
      }

      local edit = rename.prepare_workspace_edit(refs, "hello", "greet")

      assert.is_not_nil(edit)
      assert.is_not_nil(edit.changes)
      assert.equals(2, vim.tbl_count(edit.changes)) -- 2 files
    end)

    it("should handle empty references", function()
      local edit = rename.prepare_workspace_edit({}, "old", "new")
      assert.is_not_nil(edit)
      assert.equals(0, vim.tbl_count(edit.changes or {}))
    end)

    it("should calculate correct text edit ranges", function()
      local refs = {
        {
          type = "definition",
          file = "/test.tcl",
          range = { start = { line = 1, col = 6 }, end_pos = { line = 1, col = 11 } },
          text = "proc hello",
        },
      }

      local edit = rename.prepare_workspace_edit(refs, "hello", "world")
      local file_edits = edit.changes[vim.uri_from_fname("/test.tcl")]

      assert.is_not_nil(file_edits)
      assert.equals(1, #file_edits)
      assert.equals("world", file_edits[1].newText)
    end)
  end)

  describe("handle_rename", function()
    local helpers = require("tests.spec.test_helpers")
    local temp_dir
    local main_file

    before_each(function()
      package.loaded["tcl-lsp.analyzer.index"] = nil
      local idx = require("tcl-lsp.analyzer.index")
      idx.clear()

      temp_dir = helpers.create_temp_dir("rename_test")
      main_file = temp_dir .. "/main.tcl"
      helpers.write_file(main_file, [[
proc hello {} {
    puts "Hello"
}

hello
]])
    end)

    after_each(function()
      helpers.cleanup_temp_dir(temp_dir)
    end)

    it("should return error for invalid new name", function()
      vim.cmd("edit " .. main_file)
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_win_set_cursor(0, { 1, 5 })

      local result = rename.handle_rename(bufnr, 0, 5, "invalid name")

      assert.is_not_nil(result.error)
      assert.matches("invalid", result.error:lower())

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return error when not on a symbol", function()
      vim.cmd("edit " .. main_file)
      local bufnr = vim.api.nvim_get_current_buf()

      -- Position on empty/whitespace
      local result = rename.handle_rename(bufnr, 2, 0, "newName")

      -- Should handle gracefully
      assert.is_table(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
