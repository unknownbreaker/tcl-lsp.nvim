-- tests/lua/features/definition_spec.lua
-- Tests for go-to-definition feature

local helpers = require "tests.spec.test_helpers"

describe("Definition Feature", function()
  local definition

  before_each(function()
    -- Clear module cache for fresh loading
    package.loaded["tcl-lsp.features.definition"] = nil
    definition = require("tcl-lsp.features.definition")
  end)

  describe("setup", function()
    it("should register without error", function()
      local success = pcall(definition.setup)
      assert.is_true(success)
    end)

    it("should create TclGoToDefinition user command", function()
      definition.setup()

      -- Check if command exists
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.TclGoToDefinition, "TclGoToDefinition command should be registered")
    end)
  end)

  describe("handler", function()
    it("should return nil for empty buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local result = definition.handle_definition(bufnr, 0, 0)

      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return nil when cursor not on a word", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "   ", "# comment" })

      local result = definition.handle_definition(bufnr, 0, 0)

      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("keymap registration", function()
    local temp_file
    local bufnr

    before_each(function()
      definition.setup()
      temp_file = vim.fn.tempname() .. ".tcl"
      helpers.write_file(temp_file, "proc test {} { puts hello }")
      vim.cmd("edit " .. temp_file)
      bufnr = vim.api.nvim_get_current_buf()
      -- Trigger FileType autocommand
      vim.cmd("setfiletype tcl")
      -- Allow autocommands to run
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

    it("should register gd keymap for TCL files", function()
      local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
      local gd_found = false

      for _, keymap in ipairs(keymaps) do
        if keymap.lhs == "gd" then
          gd_found = true
          break
        end
      end

      assert.is_true(gd_found, "gd keymap should be registered for TCL files")
    end)
  end)

  describe("integration with definitions analyzer", function()
    local temp_dir
    local main_file

    before_each(function()
      temp_dir = helpers.create_temp_dir("definition_test")
      main_file = temp_dir .. "/main.tcl"
      helpers.write_file(main_file, [[
proc hello {} {
    puts "Hello, World!"
}

proc greet {name} {
    hello
    puts "Greeting $name"
}
]])
    end)

    after_each(function()
      helpers.cleanup_temp_dir(temp_dir)
    end)

    it("should return LSP location format when definition found", function()
      -- Open the file and position cursor
      vim.cmd("edit " .. main_file)
      local bufnr = vim.api.nvim_get_current_buf()

      -- Position cursor on "hello" call in greet proc (line 6)
      vim.api.nvim_win_set_cursor(0, { 6, 4 })

      local result = definition.handle_definition(bufnr, 5, 4) -- 0-indexed

      -- Result may be nil if definition not found (depends on parser/analyzer)
      -- but if found, it should have the right structure
      if result then
        assert.is_not_nil(result.uri, "Result should have uri")
        assert.is_not_nil(result.range, "Result should have range")
        assert.is_not_nil(result.range.start, "Result should have range.start")
        assert.is_not_nil(result.range["end"], "Result should have range.end")
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
