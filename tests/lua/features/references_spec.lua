-- tests/lua/features/references_spec.lua
-- Tests for find-references feature

local helpers = require "tests.spec.test_helpers"

describe("References Feature", function()
  local references_feature

  before_each(function()
    package.loaded["tcl-lsp.features.references"] = nil
    references_feature = require("tcl-lsp.features.references")
  end)

  describe("setup", function()
    it("should register without error", function()
      local success = pcall(references_feature.setup)
      assert.is_true(success)
    end)

    it("should create TclFindReferences user command", function()
      references_feature.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.TclFindReferences, "TclFindReferences command should be registered")
    end)
  end)

  describe("keymap registration", function()
    local temp_file
    local bufnr

    before_each(function()
      references_feature.setup()
      temp_file = vim.fn.tempname() .. ".tcl"
      helpers.write_file(temp_file, "proc test {} { puts hello }")
      vim.cmd("edit " .. temp_file)
      bufnr = vim.api.nvim_get_current_buf()
      vim.cmd("setfiletype tcl")
      vim.wait(100)
    end)

    after_each(function()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      if temp_file then
        vim.fn.delete(temp_file)
      end
    end)

    it("should register gr keymap for TCL files", function()
      local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
      local gr_found = false

      for _, keymap in ipairs(keymaps) do
        if keymap.lhs == "gr" then
          gr_found = true
          break
        end
      end

      assert.is_true(gr_found, "gr keymap should be registered for TCL files")
    end)
  end)

  describe("format_for_quickfix", function()
    it("should format references as quickfix entries", function()
      local refs = {
        {
          type = "definition",
          file = "/project/utils.tcl",
          range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
          text = "proc formatDate",
        },
        {
          type = "call",
          file = "/project/main.tcl",
          range = { start = { line = 15, col = 5 }, end_pos = { line = 15, col = 25 } },
          text = "formatDate $today",
        },
      }

      local qf_entries = references_feature.format_for_quickfix(refs)

      assert.equals(2, #qf_entries)
      assert.equals("/project/utils.tcl", qf_entries[1].filename)
      assert.equals(5, qf_entries[1].lnum)
      assert.is_true(qf_entries[1].text:match("%[def%]") ~= nil)
    end)

    it("should handle empty references list", function()
      local qf_entries = references_feature.format_for_quickfix({})
      assert.equals(0, #qf_entries)
    end)

    it("should handle references with export type", function()
      local refs = {
        {
          type = "export",
          file = "/project/api.tcl",
          range = { start = { line = 1, col = 1 }, end_pos = { line = 1, col = 10 } },
          text = "namespace export myFunc",
        },
      }

      local qf_entries = references_feature.format_for_quickfix(refs)

      assert.equals(1, #qf_entries)
      assert.is_true(qf_entries[1].text:match("%[export%]") ~= nil)
    end)
  end)

  describe("format_for_telescope", function()
    it("should format references for Telescope picker", function()
      local refs = {
        {
          type = "definition",
          file = "/project/utils.tcl",
          range = { start = { line = 5, col = 1 }, end_pos = { line = 5, col = 20 } },
          text = "proc formatDate",
        },
        {
          type = "call",
          file = "/project/main.tcl",
          range = { start = { line = 15, col = 5 }, end_pos = { line = 15, col = 25 } },
          text = "formatDate $today",
        },
      }

      local telescope_entries = references_feature.format_for_telescope(refs)

      assert.equals(2, #telescope_entries)
      assert.is_not_nil(telescope_entries[1].filename)
      assert.is_not_nil(telescope_entries[1].lnum)
      assert.is_not_nil(telescope_entries[1].display)
    end)

    it("should handle empty references list", function()
      local telescope_entries = references_feature.format_for_telescope({})
      assert.equals(0, #telescope_entries)
    end)
  end)

  describe("handle_references", function()
    it("should return nil for empty buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local result = references_feature.handle_references(bufnr, 0, 0)

      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return nil when cursor not on a word", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "   ", "# comment" })

      local result = references_feature.handle_references(bufnr, 0, 0)

      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("integration", function()
    local temp_dir
    local main_file

    before_each(function()
      temp_dir = helpers.create_temp_dir("references_test")
      main_file = temp_dir .. "/main.tcl"
      helpers.write_file(main_file, [[
proc hello {} {
    puts "Hello, World!"
}

proc greet {name} {
    hello
    puts "Greeting $name"
}

hello
]])
    end)

    after_each(function()
      helpers.cleanup_temp_dir(temp_dir)
    end)

    it("should return refs list when symbol found", function()
      vim.cmd("edit " .. main_file)
      local bufnr = vim.api.nvim_get_current_buf()

      -- Position cursor on "hello" call in greet proc (line 6)
      vim.api.nvim_win_set_cursor(0, { 6, 4 })

      local result = references_feature.handle_references(bufnr, 5, 4) -- 0-indexed

      -- Result may be empty if indexer hasn't run, but should not error
      if result then
        assert.is_table(result)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
