-- tests/lua/test_config.lua
-- Tests for TCL LSP configuration management
-- Following TDD approach - these tests define the expected behavior

local helpers = require "tests.spec.test_helpers"

describe("TCL LSP Configuration", function()
  local config
  local original_vim

  before_each(function()
    -- Store original vim and replace with mock
    original_vim = _G.vim

    -- Create enhanced mock vim with all needed APIs
    local mock_vim = helpers.create_vim_mock()

    -- Add vim.inspect mock
    mock_vim.inspect = function(obj)
      if type(obj) == "table" then
        local str = "{"
        local first = true
        for k, v in pairs(obj) do
          if not first then
            str = str .. ", "
          end
          first = false
          str = str .. tostring(k) .. " = " .. tostring(v)
        end
        return str .. "}"
      else
        return tostring(obj)
      end
    end

    -- Add vim.json mock
    mock_vim.json = {
      encode = function(obj)
        -- Simple JSON encoding for basic objects
        if type(obj) == "table" then
          local str = "{"
          local first = true
          for k, v in pairs(obj) do
            if not first then
              str = str .. ","
            end
            first = false
            str = str
              .. '"'
              .. tostring(k)
              .. '":'
              .. (type(v) == "string" and '"' .. v .. '"' or tostring(v))
          end
          return str .. "}"
        else
          return type(obj) == "string" and '"' .. obj .. '"' or tostring(obj)
        end
      end,

      decode = function(str)
        -- Simple JSON decoding - just return a basic table for testing
        return {
          log_level = "debug",
          root_markers = { ".git", "tcl.toml" },
          timeout = 8000,
        }
      end,
    }

    -- Set the enhanced mock
    _G.vim = mock_vim

    -- Clear package cache to get fresh module
    package.loaded["tcl-lsp.config"] = nil

    -- Require fresh config module
    config = require "tcl-lsp.config"

    -- Ensure completely clean state - reset multiple times if needed
    if config.reset then
      config.reset()
      config.reset() -- Double reset to be sure
    end
  end)

  after_each(function()
    -- Restore original vim
    _G.vim = original_vim

    -- Reset config state aggressively
    if config and config.reset then
      config.reset()
    end

    -- Clear package cache to prevent state leakage
    package.loaded["tcl-lsp.config"] = nil
  end)
end)

describe("TCL LSP Configuration", function()
  local config
  local original_vim

  before_each(function()
    -- Store original vim and replace with mock
    original_vim = _G.vim
    _G.vim = mock_vim

    -- Clear package cache to get fresh module
    package.loaded["tcl-lsp.config"] = nil

    -- Require fresh config module
    config = require "tcl-lsp.config"

    -- Ensure clean state
    config.reset()
  end)

  after_each(function()
    -- Restore original vim
    _G.vim = original_vim

    -- Reset config state
    if config and config.reset then
      config.reset()
    end
  end)

  describe("Default Configuration", function()
    it("should provide sensible defaults", function()
      local defaults = config.get()

      -- Command configuration
      assert.is_nil(defaults.cmd, "cmd should be nil by default (auto-detect)")

      -- Root markers for project detection
      assert.is_table(defaults.root_markers, "root_markers should be a table")
      assert.contains(".git", defaults.root_markers)
      assert.contains("tcl.toml", defaults.root_markers)
      assert.contains("project.tcl", defaults.root_markers)
      assert.contains("pkgIndex.tcl", defaults.root_markers)

      -- Logging configuration
      assert.equals("info", defaults.log_level)

      -- Timeout and retry configuration
      assert.is_number(defaults.timeout)
      assert.is_true(defaults.timeout > 0, "timeout should be positive")
      assert.is_number(defaults.restart_limit)
      assert.is_true(defaults.restart_limit >= 0, "restart_limit should be non-negative")
      assert.is_number(defaults.restart_cooldown)
      assert.is_true(defaults.restart_cooldown > 0, "restart_cooldown should be positive")

      -- File type support
      assert.is_table(defaults.filetypes, "filetypes should be a table")
      assert.contains("tcl", defaults.filetypes)
      assert.contains("rvt", defaults.filetypes)
    end)

    it("should have reasonable default values", function()
      local defaults = config.get()

      -- Check specific expected values
      assert.equals("info", defaults.log_level)
      assert.equals(5000, defaults.timeout) -- 5 seconds
      assert.equals(3, defaults.restart_limit)
      assert.equals(5000, defaults.restart_cooldown) -- 5 seconds
    end)

    it("should include all necessary root markers", function()
      local defaults = config.get()
      local expected_markers = {
        ".git", -- Git repository
        "tcl.toml", -- Modern TCL project file
        "project.tcl", -- Legacy TCL project file
        "pkgIndex.tcl", -- TCL package index
        "Makefile", -- Build system
        ".gitroot", -- Custom root marker
      }

      for _, marker in ipairs(expected_markers) do
        assert.contains(marker, defaults.root_markers, "Should include root marker: " .. marker)
      end
    end)

    it("should support both TCL and RVT filetypes", function()
      local defaults = config.get()

      assert.contains("tcl", defaults.filetypes)
      assert.contains("rvt", defaults.filetypes)
      assert.equals(2, #defaults.filetypes, "Should have exactly 2 default filetypes")
    end)
  end)

  describe("Configuration Setup", function()
    it("should accept empty setup call", function()
      local success = pcall(config.setup)
      assert.is_true(success, "setup() should work without arguments")

      local result = config.get()
      assert.is_table(result, "Should return table after empty setup")
    end)

    it("should accept nil configuration", function()
      local success = pcall(config.setup, nil)
      assert.is_true(success, "setup(nil) should work")

      local result = config.get()
      assert.is_table(result, "Should return table after nil setup")
    end)

    it("should merge user configuration with defaults", function()
      local user_config = {
        log_level = "debug",
        timeout = 10000,
        custom_option = "test_value",
      }

      config.setup(user_config)
      local result = config.get()

      -- User values should override defaults
      assert.equals("debug", result.log_level)
      assert.equals(10000, result.timeout)
      assert.equals("test_value", result.custom_option)

      -- Defaults should be preserved where not overridden
      assert.equals(3, result.restart_limit)
      assert.is_table(result.root_markers)
      assert.contains(".git", result.root_markers)
    end)

    it("should perform deep merge for nested tables", function()
      local user_config = {
        root_markers = { "custom.marker", ".git" },
        nested_config = {
          option1 = "value1",
          option2 = "value2",
        },
      }

      config.setup(user_config)
      local result = config.get()

      -- Should replace entire root_markers array
      assert.same({ "custom.marker", ".git" }, result.root_markers)

      -- Should merge nested configuration
      assert.equals("value1", result.nested_config.option1)
      assert.equals("value2", result.nested_config.option2)
    end)

    it("should allow multiple setup calls", function()
      -- First setup
      config.setup { log_level = "debug" }
      local result1 = config.get()
      assert.equals("debug", result1.log_level)

      -- Second setup should override
      config.setup { log_level = "warn", timeout = 8000 }
      local result2 = config.get()
      assert.equals("warn", result2.log_level)
      assert.equals(8000, result2.timeout)
    end)
  end)

  describe("Configuration Validation", function()
    it("should validate cmd field type", function()
      local invalid_configs = {
        { cmd = "should_be_table" },
        { cmd = 123 },
        { cmd = true },
      }

      for _, invalid_config in ipairs(invalid_configs) do
        local success, error_msg = pcall(config.setup, invalid_config)
        assert.is_false(success, "Should reject invalid cmd: " .. vim.inspect(invalid_config.cmd))
        assert.matches("cmd.*table", error_msg, "Error should mention cmd and table")
      end
    end)

    it("should accept valid cmd configurations", function()
      local valid_configs = {
        { cmd = { "tclsh", "/path/to/parser.tcl" } },
        { cmd = { "custom-tcl" } },
        { cmd = { "tclsh", "--option", "value" } },
      }

      for _, valid_config in ipairs(valid_configs) do
        local success = pcall(config.setup, valid_config)
        assert.is_true(success, "Should accept valid cmd: " .. vim.inspect(valid_config.cmd))
      end
    end)

    it("should validate root_markers field type", function()
      local invalid_configs = {
        { root_markers = "should_be_table" },
        { root_markers = 123 },
        { root_markers = { 123, 456 } }, -- Should be strings
      }

      for _, invalid_config in ipairs(invalid_configs) do
        local success, error_msg = pcall(config.setup, invalid_config)
        assert.is_false(
          success,
          "Should reject invalid root_markers: " .. vim.inspect(invalid_config.root_markers)
        )
        assert.matches("root_markers", error_msg, "Error should mention root_markers")
      end
    end)

    it("should validate log_level values", function()
      local valid_levels = { "debug", "info", "warn", "error" }

      for _, level in ipairs(valid_levels) do
        local success = pcall(config.setup, { log_level = level })
        assert.is_true(success, "Should accept valid log_level: " .. level)
      end

      local invalid_levels = { "invalid", 123, true, {} }

      for _, level in ipairs(invalid_levels) do
        local success, error_msg = pcall(config.setup, { log_level = level })
        assert.is_false(success, "Should reject invalid log_level: " .. vim.inspect(level))
        assert.matches("log_level", error_msg, "Error should mention log_level")
      end
    end)

    it("should validate numeric fields", function()
      local numeric_fields = { "timeout", "restart_limit", "restart_cooldown" }

      for _, field in ipairs(numeric_fields) do
        -- Test invalid types
        local invalid_values = { "string", true, {}, function() end }

        for _, value in ipairs(invalid_values) do
          local invalid_config = {}
          invalid_config[field] = value

          local success, error_msg = pcall(config.setup, invalid_config)
          assert.is_false(
            success,
            "Should reject non-numeric " .. field .. ": " .. vim.inspect(value)
          )
          assert.matches(field, error_msg, "Error should mention " .. field)
        end

        -- Test negative values (should be rejected for most fields)
        if field ~= "restart_limit" then -- restart_limit can be 0
          local negative_config = {}
          negative_config[field] = -1

          local success, error_msg = pcall(config.setup, negative_config)
          assert.is_false(success, "Should reject negative " .. field)
        end
      end
    end)

    it("should validate filetypes field", function()
      -- Valid filetypes
      local valid_configs = {
        { filetypes = { "tcl" } },
        { filetypes = { "tcl", "rvt" } },
        { filetypes = { "tcl", "rvt", "tm" } },
      }

      for _, valid_config in ipairs(valid_configs) do
        local success = pcall(config.setup, valid_config)
        assert.is_true(
          success,
          "Should accept valid filetypes: " .. vim.inspect(valid_config.filetypes)
        )
      end

      -- Invalid filetypes
      local invalid_configs = {
        { filetypes = "should_be_table" },
        { filetypes = {} }, -- Empty table
        { filetypes = { 123, "tcl" } }, -- Mixed types
      }

      for _, invalid_config in ipairs(invalid_configs) do
        local success, error_msg = pcall(config.setup, invalid_config)
        assert.is_false(
          success,
          "Should reject invalid filetypes: " .. vim.inspect(invalid_config.filetypes)
        )
        assert.matches("filetypes", error_msg, "Error should mention filetypes")
      end
    end)
  end)

  describe("Buffer-Local Configuration", function()
    it("should support buffer-local overrides", function()
      -- Set global config
      config.setup { log_level = "info", timeout = 5000 }

      -- Set buffer-local config
      vim.b = vim.b or {}
      vim.b[1] = vim.b[1] or {}
      vim.b[1].tcl_lsp_config = {
        log_level = "debug",
        custom_buffer_option = "buffer_value",
      }

      -- Get config for specific buffer
      local buffer_config = config.get(1)

      -- Should merge global and buffer-local
      assert.equals("debug", buffer_config.log_level) -- Overridden
      assert.equals(5000, buffer_config.timeout) -- From global
      assert.equals("buffer_value", buffer_config.custom_buffer_option) -- Buffer-only
    end)

    it("should fall back to global config without buffer overrides", function()
      config.setup { log_level = "warn", timeout = 8000 }

      -- No buffer-local config set
      local buffer_config = config.get(1)

      assert.equals("warn", buffer_config.log_level)
      assert.equals(8000, buffer_config.timeout)
    end)

    it("should handle current buffer when no buffer specified", function()
      config.setup { log_level = "error" }

      -- Mock current buffer
      vim.api.nvim_get_current_buf = function()
        return 5
      end
      vim.b = vim.b or {}
      vim.b[5] = { tcl_lsp_config = { log_level = "debug" } }

      local current_config = config.get() -- No buffer specified
      assert.equals("debug", current_config.log_level)
    end)

    it("should validate buffer-local configuration", function()
      config.setup { log_level = "info" }

      -- Set invalid buffer-local config
      vim.b = vim.b or {}
      vim.b[1] = { tcl_lsp_config = { cmd = "invalid_should_be_table" } }

      local success, error_msg = pcall(config.get, 1)
      assert.is_false(success, "Should validate buffer-local config")
      assert.matches("cmd.*table", error_msg, "Should provide helpful error")
    end)
  end)

  describe("Configuration Utilities", function()
    it("should provide configuration reset function", function()
      config.setup { log_level = "debug", custom_option = "test" }

      assert.is_function(config.reset, "Should provide reset function")

      config.reset()
      local reset_config = config.get()

      -- Should return to defaults
      assert.equals("info", reset_config.log_level)
      assert.is_nil(reset_config.custom_option)
    end)

    it("should provide configuration update function", function()
      config.setup { log_level = "info", timeout = 5000 }

      assert.is_function(config.update, "Should provide update function")

      config.update { log_level = "debug" }
      local updated_config = config.get()

      assert.equals("debug", updated_config.log_level)
      assert.equals(5000, updated_config.timeout) -- Preserved
    end)

    it("should detect configuration changes", function()
      config.setup { log_level = "info" }

      assert.is_function(config.has_changed, "Should provide has_changed function")

      -- Should not be changed initially
      assert.is_false(config.has_changed(), "Should not be changed initially")

      config.update { log_level = "debug" }

      -- Should detect change
      assert.is_true(config.has_changed(), "Should detect configuration change")

      -- Should reset change flag after check
      config.has_changed() -- Reset flag
      assert.is_false(config.has_changed(), "Should reset change flag")
    end)

    it("should provide configuration validation function", function()
      assert.is_function(config.validate, "Should provide validate function")

      local valid_config = {
        cmd = { "tclsh", "parser.tcl" },
        log_level = "debug",
        timeout = 10000,
      }

      local is_valid, errors = config.validate(valid_config)
      assert.is_true(is_valid, "Should validate correct config")
      assert.is_nil(errors, "Should not return errors for valid config")

      local invalid_config = {
        cmd = "invalid",
        log_level = "invalid_level",
      }

      is_valid, errors = config.validate(invalid_config)
      assert.is_false(is_valid, "Should reject invalid config")
      assert.is_table(errors, "Should return error details")
      assert.is_true(#errors > 0, "Should have error messages")
    end)
  end)

  describe("Configuration Export/Import", function()
    it("should export current configuration", function()
      config.setup {
        log_level = "debug",
        timeout = 10000,
        custom_option = "test",
      }

      assert.is_function(config.export, "Should provide export function")

      local exported = config.export()
      assert.is_table(exported, "Should export as table")
      assert.equals("debug", exported.log_level)
      assert.equals(10000, exported.timeout)
      assert.equals("test", exported.custom_option)
    end)

    it("should import configuration", function()
      local import_config = {
        log_level = "warn",
        timeout = 15000,
        imported_option = "imported",
      }

      assert.is_function(config.import, "Should provide import function")

      config.import(import_config)
      local result = config.get()

      assert.equals("warn", result.log_level)
      assert.equals(15000, result.timeout)
      assert.equals("imported", result.imported_option)
    end)

    it("should handle configuration serialization", function()
      config.setup {
        log_level = "debug",
        root_markers = { ".git", "tcl.toml" },
        timeout = 8000,
      }

      -- Export, serialize, deserialize, import
      local exported = config.export()
      local serialized = vim.json.encode(exported)
      local deserialized = vim.json.decode(serialized)

      config.reset()
      config.import(deserialized)

      local result = config.get()
      assert.equals("debug", result.log_level)
      assert.same({ ".git", "tcl.toml" }, result.root_markers)
      assert.equals(8000, result.timeout)
    end)
  end)

  describe("Edge Cases", function()
    it("should handle deeply nested configuration", function()
      local deep_config = {
        server = {
          options = {
            parser = {
              strict_mode = true,
              error_recovery = false,
            },
          },
        },
      }

      local success = pcall(config.setup, deep_config)
      assert.is_true(success, "Should handle deeply nested config")

      local result = config.get()
      assert.is_true(result.server.options.parser.strict_mode)
      assert.is_false(result.server.options.parser.error_recovery)
    end)

    it("should handle circular references gracefully", function()
      local circular_config = {}
      circular_config.self = circular_config

      local success, error_msg = pcall(config.setup, circular_config)
      assert.is_false(success, "Should handle circular references")
      assert.matches("circular", error_msg, "Should mention circular reference")
    end)

    it("should handle very large configurations", function()
      local large_config = {
        root_markers = {},
      }

      -- Add many root markers
      for i = 1, 1000 do
        table.insert(large_config.root_markers, "marker_" .. i)
      end

      local success = pcall(config.setup, large_config)
      assert.is_true(success, "Should handle large configurations")

      local result = config.get()
      assert.equals(1000, #result.root_markers)
    end)

    it("should handle special characters in configuration", function()
      local special_config = {
        custom_path = "/path/with spaces/and-special_chars.tcl",
        regex_pattern = "[\\w\\s]+\\.tcl$",
        unicode_text = "测试配置",
      }

      local success = pcall(config.setup, special_config)
      assert.is_true(success, "Should handle special characters")

      local result = config.get()
      assert.equals("/path/with spaces/and-special_chars.tcl", result.custom_path)
      assert.equals("[\\w\\s]+\\.tcl$", result.regex_pattern)
      assert.equals("测试配置", result.unicode_text)
    end)
  end)
end)

-- Helper function to check if table contains value
function assert.contains(expected, actual_table)
  if type(actual_table) ~= "table" then
    error("Expected table, got " .. type(actual_table))
  end

  for _, value in ipairs(actual_table) do
    if value == expected then
      return true
    end
  end
  error(
    "Expected table to contain '"
      .. tostring(expected)
      .. "' but it didn't. Table contents: "
      .. vim.inspect(actual_table)
  )
end
