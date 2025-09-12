-- tests/lua/config_spec.lua
-- Tests for TCL LSP configuration management using real Neovim APIs

describe("TCL LSP Configuration", function()
  local config

  before_each(function()
    -- Clear package cache to get fresh module
    package.loaded["tcl-lsp.config"] = nil

    -- Load fresh config module
    config = require "tcl-lsp.config"

    -- Reset to clean state
    config.reset()

    -- Clear any buffer-local variables
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(function()
          vim.api.nvim_buf_del_var(bufnr, "tcl_lsp_config")
        end)
      end
    end
  end)

  after_each(function()
    -- Clean up
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
      assert.truthy(vim.tbl_contains(defaults.root_markers, ".git"))
      assert.truthy(vim.tbl_contains(defaults.root_markers, "tcl.toml"))
      assert.truthy(vim.tbl_contains(defaults.root_markers, "project.tcl"))
      assert.truthy(vim.tbl_contains(defaults.root_markers, "pkgIndex.tcl"))
      assert.truthy(vim.tbl_contains(defaults.root_markers, "Makefile"))
      assert.truthy(vim.tbl_contains(defaults.root_markers, ".gitroot"))

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
      assert.truthy(vim.tbl_contains(defaults.filetypes, "tcl"))
      assert.truthy(vim.tbl_contains(defaults.filetypes, "rvt"))
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
        assert.truthy(
          vim.tbl_contains(defaults.root_markers, marker),
          "Should include root marker: " .. marker
        )
      end
    end)

    it("should support both TCL and RVT filetypes", function()
      local defaults = config.get()

      assert.truthy(vim.tbl_contains(defaults.filetypes, "tcl"))
      assert.truthy(vim.tbl_contains(defaults.filetypes, "rvt"))
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
      assert.truthy(vim.tbl_contains(result.root_markers, ".git"))
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
      local valid_configs = {
        { timeout = 1000 },
        { restart_limit = 0 }, -- Zero is valid for restart_limit
        { restart_cooldown = 1 },
      }

      for _, valid_config in ipairs(valid_configs) do
        local success = pcall(config.setup, valid_config)
        assert.is_true(success, "Should accept valid config: " .. vim.inspect(valid_config))
      end

      local invalid_configs = {
        { timeout = -1 }, -- Must be positive
        { timeout = "not_a_number" },
        { restart_limit = -1 }, -- Must be non-negative
        { restart_cooldown = 0 }, -- Must be positive
      }

      for _, invalid_config in ipairs(invalid_configs) do
        local success, error_msg = pcall(config.setup, invalid_config)
        assert.is_false(success, "Should reject invalid config: " .. vim.inspect(invalid_config))
      end
    end)

    it("should validate filetypes field", function()
      local valid_configs = {
        { filetypes = { "tcl" } },
        { filetypes = { "tcl", "rvt", "custom" } },
      }

      for _, valid_config in ipairs(valid_configs) do
        local success = pcall(config.setup, valid_config)
        assert.is_true(
          success,
          "Should accept valid filetypes: " .. vim.inspect(valid_config.filetypes)
        )
      end

      local invalid_configs = {
        { filetypes = "not_a_table" },
        { filetypes = {} }, -- Empty array
        { filetypes = { 123, 456 } }, -- Should be strings
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
      -- Setup global config
      config.setup { log_level = "info" }

      -- Create a test buffer
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Set buffer-local override
      vim.api.nvim_buf_set_var(bufnr, "tcl_lsp_config", {
        log_level = "debug",
      })

      -- Get config for specific buffer
      local buffer_config = config.get(bufnr)
      assert.equals("debug", buffer_config.log_level, "Should use buffer-local override")

      -- Get config for different buffer (should use global)
      local other_bufnr = vim.api.nvim_create_buf(false, true)
      local other_config = config.get(other_bufnr)
      assert.equals("info", other_config.log_level, "Should use global config for other buffer")

      -- Cleanup
      vim.api.nvim_buf_delete(bufnr, { force = true })
      vim.api.nvim_buf_delete(other_bufnr, { force = true })
    end)

    it("should fall back to global config without buffer overrides", function()
      config.setup { log_level = "warn" }

      local bufnr = vim.api.nvim_create_buf(false, true)
      local config_result = config.get(bufnr)
      assert.equals(
        "warn",
        config_result.log_level,
        "Should use global config when no buffer override"
      )

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should handle current buffer when no buffer specified", function()
      config.setup { log_level = "error" }

      -- Create and switch to a test buffer
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      -- Set buffer-local config for current buffer
      vim.api.nvim_buf_set_var(bufnr, "tcl_lsp_config", {
        log_level = "debug",
      })

      -- Get config without specifying buffer (should use current buffer)
      local config_result = config.get()
      assert.equals("debug", config_result.log_level, "Should use current buffer config")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should validate buffer-local configuration", function()
      config.setup { log_level = "info" }

      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Set invalid buffer-local config
      vim.api.nvim_buf_set_var(bufnr, "tcl_lsp_config", {
        log_level = "invalid_level",
      })

      -- Should fail validation
      local success, error_msg = pcall(config.get, bufnr)
      assert.is_false(success, "Should validate buffer-local config")
      assert.matches("log_level", error_msg, "Should mention invalid log_level")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("Configuration Utilities", function()
    it("should provide configuration reset function", function()
      config.setup { log_level = "debug" }
      assert.equals("debug", config.get().log_level)

      config.reset()
      assert.equals("info", config.get().log_level, "Should reset to defaults")
    end)

    it("should provide configuration update function", function()
      config.setup { log_level = "info", timeout = 5000 }

      config.update { log_level = "debug" }
      local result = config.get()

      assert.equals("debug", result.log_level, "Should update specific fields")
      assert.equals(5000, result.timeout, "Should preserve other fields")
    end)

    it("should detect configuration changes", function()
      config.setup { log_level = "info" }
      assert.is_false(config.has_changed(), "Should not have changes after setup")

      config.update { log_level = "debug" }
      assert.is_true(config.has_changed(), "Should detect changes after update")
      assert.is_false(config.has_changed(), "Should reset change flag after check")
    end)

    it("should provide configuration validation function", function()
      local valid_config = { log_level = "debug", timeout = 1000 }
      local is_valid, errors = config.validate(valid_config)
      assert.is_true(is_valid, "Should validate correct config")
      assert.is_nil(errors, "Should not have errors for valid config")

      local invalid_config = { log_level = "invalid" }
      is_valid, errors = config.validate(invalid_config)
      assert.is_false(is_valid, "Should reject invalid config")
      assert.is_table(errors, "Should return error details")
    end)
  end)

  describe("Configuration Export/Import", function()
    it("should export current configuration", function()
      config.setup { log_level = "debug", custom_field = "test" }

      local exported = config.export()

      assert.is_table(exported, "Should export as table")
      assert.equals("debug", exported.log_level)
      assert.equals("test", exported.custom_field)

      -- Should be a deep copy (modifying export shouldn't affect original)
      exported.log_level = "info"
      assert.equals("debug", config.get().log_level)
    end)

    it("should import configuration", function()
      local import_config = { log_level = "warn", timeout = 8000 }

      config.import(import_config)
      local result = config.get()

      assert.equals("warn", result.log_level)
      assert.equals(8000, result.timeout)
    end)

    it("should handle configuration serialization", function()
      config.setup { log_level = "debug", nested = { option = "value" } }

      local exported = config.export()
      local serialized = vim.inspect(exported)

      assert.is_string(serialized, "Should serialize to string")
      assert.matches("debug", serialized, "Should contain config values")
    end)
  end)

  describe("Edge Cases", function()
    it("should handle deeply nested configuration", function()
      local deep_config = {
        level1 = {
          level2 = {
            level3 = {
              level4 = {
                value = "deep_value",
              },
            },
          },
        },
      }

      local success = pcall(config.setup, deep_config)
      assert.is_true(success, "Should handle deep nesting")

      local result = config.get()
      assert.equals("deep_value", result.level1.level2.level3.level4.value)
    end)

    it("should handle circular references gracefully", function()
      local circular_config = { log_level = "info" }
      circular_config.self = circular_config -- Create circular reference

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
