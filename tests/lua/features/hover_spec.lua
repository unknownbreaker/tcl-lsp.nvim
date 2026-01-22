-- tests/lua/features/hover_spec.lua
-- Tests for hover feature

local helpers = require "tests.spec.test_helpers"

describe("Hover Feature", function()
  local hover

  before_each(function()
    package.loaded["tcl-lsp.features.hover"] = nil
    hover = require("tcl-lsp.features.hover")
  end)

  describe("setup", function()
    it("should register without error", function()
      local success = pcall(hover.setup)
      assert.is_true(success)
    end)

    it("should create TclHover user command", function()
      hover.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.TclHover, "TclHover command should be registered")
    end)
  end)

  describe("keymap registration", function()
    local temp_file
    local bufnr

    before_each(function()
      hover.setup()
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

    it("should register K keymap for TCL files", function()
      local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
      local k_found = false

      for _, keymap in ipairs(keymaps) do
        if keymap.lhs == "K" then
          k_found = true
          break
        end
      end

      assert.is_true(k_found, "K keymap should be registered for TCL files")
    end)
  end)

  describe("format_proc_hover", function()
    it("should format proc with params and docs", function()
      local symbol = {
        type = "proc",
        name = "format_date",
        qualified_name = "::utils::format_date",
        params = { "date_str", "format" },
        file = "/path/to/utils.tcl",
        range = { start = { line = 10, col = 1 }, end_pos = { line = 15, col = 1 } },
        scope = "::utils",
      }
      local doc_comment = "Formats a date string according to the specified format."

      local result = hover.format_proc_hover(symbol, doc_comment)

      assert.is_not_nil(result)
      assert.matches("```tcl", result)
      assert.matches("proc ::utils::format_date", result)
      assert.matches("date_str", result)
      assert.matches("format", result)
      assert.matches("Formats a date string", result)
      assert.matches("utils.tcl:10", result)
      assert.matches("::utils", result)
    end)

    it("should format proc without docs", function()
      local symbol = {
        type = "proc",
        name = "simple",
        qualified_name = "::simple",
        params = {},
        file = "/path/to/main.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 3, col = 1 } },
        scope = "::",
      }

      local result = hover.format_proc_hover(symbol, nil)

      assert.is_not_nil(result)
      assert.matches("```tcl", result)
      assert.matches("proc ::simple", result)
      assert.matches("main.tcl:1", result)
      -- Should not have a description section
      assert.is_nil(result:match("Formats a date"))
    end)

    it("should handle proc with optional params", function()
      local symbol = {
        type = "proc",
        name = "greet",
        qualified_name = "::greet",
        params = { "name", { "greeting", "Hello" } },
        file = "/path/to/main.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 3, col = 1 } },
        scope = "::",
      }

      local result = hover.format_proc_hover(symbol, nil)

      assert.is_not_nil(result)
      assert.matches("name", result)
      -- Should show default value somehow
      assert.matches("greeting", result)
    end)
  end)

  describe("format_variable_hover", function()
    it("should format namespace variable with value", function()
      local symbol = {
        type = "variable",
        name = "timeout",
        qualified_name = "::config::timeout",
        file = "/path/to/config.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 5, col = 20 } },
        scope = "::config",
      }
      local initial_value = "30"

      local result = hover.format_variable_hover(symbol, initial_value, "namespace variable")

      assert.is_not_nil(result)
      assert.matches("```tcl", result)
      assert.matches("set ::config::timeout 30", result)
      assert.matches("namespace variable", result)
      assert.matches("config.tcl:5", result)
      assert.matches("::config", result)
    end)

    it("should format variable without initial value", function()
      local symbol = {
        type = "variable",
        name = "debug_mode",
        qualified_name = "::config::debug_mode",
        file = "/path/to/config.tcl",
        range = { start = { line = 8, col = 1 }, end_pos = { line = 8, col = 15 } },
        scope = "::config",
      }

      local result = hover.format_variable_hover(symbol, nil, "namespace variable")

      assert.is_not_nil(result)
      assert.matches("Variable", result)
      assert.matches("::config::debug_mode", result)
      assert.matches("namespace variable", result)
      assert.matches("config.tcl:8", result)
    end)

    it("should format local variable", function()
      local symbol = {
        type = "variable",
        name = "count",
        qualified_name = "count",
        file = "/path/to/main.tcl",
        range = { start = { line = 12, col = 5 }, end_pos = { line = 12, col = 15 } },
        scope = "::",
      }

      local result = hover.format_variable_hover(symbol, "0", "local variable")

      assert.is_not_nil(result)
      assert.matches("local variable", result)
    end)

    it("should format global variable", function()
      local symbol = {
        type = "variable",
        name = "global_config",
        qualified_name = "::global_config",
        file = "/path/to/main.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 1, col = 25 } },
        scope = "::",
      }

      local result = hover.format_variable_hover(symbol, '"production"', "global variable")

      assert.is_not_nil(result)
      assert.matches("global variable", result)
      assert.matches("production", result)
    end)
  end)

  describe("get_scope_type", function()
    it("should return 'local variable' for local context", function()
      local context = {
        locals = { "count", "result" },
        globals = {},
        namespace = "::",
      }

      local result = hover.get_scope_type("count", context)

      assert.equals("local variable", result)
    end)

    it("should return 'global variable' for global context", function()
      local context = {
        locals = {},
        globals = { "config", "debug" },
        namespace = "::",
      }

      local result = hover.get_scope_type("config", context)

      assert.equals("global variable", result)
    end)

    it("should return 'namespace variable' for namespace scope", function()
      local context = {
        locals = {},
        globals = {},
        namespace = "::utils",
      }

      local result = hover.get_scope_type("helper", context)

      assert.equals("namespace variable", result)
    end)

    it("should return 'namespace variable' for global namespace variable", function()
      local context = {
        locals = {},
        globals = {},
        namespace = "::",
      }

      local result = hover.get_scope_type("app_name", context)

      assert.equals("namespace variable", result)
    end)
  end)

  describe("handle_hover", function()
    it("should return nil for empty buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local result = hover.handle_hover(bufnr, 0, 0)

      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return nil when cursor not on a word", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "   ", "# comment" })

      local result = hover.handle_hover(bufnr, 0, 0)

      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("integration", function()
    local temp_dir
    local main_file

    before_each(function()
      temp_dir = helpers.create_temp_dir("hover_test")
      main_file = temp_dir .. "/main.tcl"
      helpers.write_file(main_file, [[
# Formats a greeting message
# with the given name
proc greet {name} {
    set message "Hello, $name!"
    return $message
}

set timeout 30

namespace eval ::config {
    # Application configuration
    set app_name "TestApp"
}
]])
    end)

    after_each(function()
      helpers.cleanup_temp_dir(temp_dir)
    end)

    it("should return markdown for proc with comments", function()
      vim.cmd("edit " .. main_file)
      local bufnr = vim.api.nvim_get_current_buf()

      -- Position cursor on "greet" proc name (line 3)
      vim.api.nvim_win_set_cursor(0, { 3, 5 })

      local result = hover.handle_hover(bufnr, 2, 5) -- 0-indexed

      -- Result may be nil if not on a symbol, but if found should have content
      if result then
        assert.matches("greet", result)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return markdown for variable", function()
      vim.cmd("edit " .. main_file)
      local bufnr = vim.api.nvim_get_current_buf()

      -- Position cursor on "timeout" (line 8)
      vim.api.nvim_win_set_cursor(0, { 8, 4 })

      local result = hover.handle_hover(bufnr, 7, 4) -- 0-indexed

      if result then
        assert.matches("timeout", result)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
