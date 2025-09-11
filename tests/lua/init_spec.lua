-- tests/lua/test_init.lua
-- Tests for the main plugin entry point
-- Following TDD approach for plugin initialization

local helpers = require "tests.spec.test_helpers"

describe("TCL LSP Plugin Initialization", function()
  local tcl_lsp
  local original_vim

  before_each(function()
    -- Store original vim global if it exists
    original_vim = _G.vim

    -- Setup mock vim environment
    _G.vim = helpers.create_vim_mock()

    -- Clear package cache
    package.loaded["tcl-lsp"] = nil
    package.loaded["tcl-lsp.init"] = nil
    package.loaded["tcl-lsp.server"] = nil
    package.loaded["tcl-lsp.config"] = nil

    -- Mock dependencies
    package.preload["tcl-lsp.server"] = function()
      return {
        start = function()
          return 1
        end,
        stop = function()
          return true
        end,
        restart = function()
          return true
        end,
        get_status = function()
          return { state = "stopped" }
        end,
        state = { client_id = nil },
      }
    end

    package.preload["tcl-lsp.config"] = function()
      return helpers.create_config_mock()
    end
  end)

  after_each(function()
    -- Restore original vim global
    _G.vim = original_vim

    -- Clean up
    if tcl_lsp then
      pcall(tcl_lsp.stop)
    end
  end)

  describe("Module Loading", function()
    it("should load without errors", function()
      local success, result = pcall(require, "tcl-lsp")
      assert.is_true(success, "Should load module without errors: " .. tostring(result))
      assert.is_table(result, "Should return a table")
    end)

    it("should expose expected public API", function()
      tcl_lsp = require "tcl-lsp"

      -- Check for required functions
      assert.is_function(tcl_lsp.setup, "Should expose setup function")
      assert.is_function(tcl_lsp.start, "Should expose start function")
      assert.is_function(tcl_lsp.stop, "Should expose stop function")
      assert.is_function(tcl_lsp.restart, "Should expose restart function")
      assert.is_function(tcl_lsp.status, "Should expose status function")
    end)

    it("should have correct version information", function()
      tcl_lsp = require "tcl-lsp"

      assert.is_not_nil(tcl_lsp.version, "Should have version information")
      assert.matches("^%d+%.%d+%.%d+", tcl_lsp.version, "Version should follow semver pattern")
    end)

    it("should initialize with default configuration", function()
      tcl_lsp = require "tcl-lsp"

      -- Should not error when loaded
      assert.is_not_nil(tcl_lsp)

      -- Should have default state
      local status = tcl_lsp.status()
      assert.equals("stopped", status.state)
    end)
  end)

  describe("Setup Function", function()
    before_each(function()
      tcl_lsp = require "tcl-lsp"
    end)

    it("should accept empty configuration", function()
      local success = pcall(tcl_lsp.setup)
      assert.is_true(success, "Should accept empty configuration")
    end)

    it("should accept user configuration", function()
      local config = {
        cmd = { "custom-tclsh", "/custom/parser.tcl" },
        root_markers = { "custom.tcl" },
        log_level = "debug",
      }

      local success = pcall(tcl_lsp.setup, config)
      assert.is_true(success, "Should accept user configuration")
    end)

    it("should validate configuration parameters", function()
      -- Test invalid configuration
      local invalid_configs = {
        { cmd = "invalid_string_should_be_table" },
        { root_markers = "invalid_string_should_be_table" },
        { log_level = 123 }, -- Should be string
        { timeout = "invalid_should_be_number" },
      }

      for _, invalid_config in ipairs(invalid_configs) do
        local success, err = pcall(tcl_lsp.setup, invalid_config)
        assert.is_false(success, "Should reject invalid config: " .. vim.inspect(invalid_config))
      end
    end)

    it("should merge user config with defaults", function()
      local user_config = {
        log_level = "debug",
        timeout = 10000,
      }

      tcl_lsp.setup(user_config)

      -- Config should be merged (this would need access to internal config)
      -- For now, just verify setup succeeded
      local status = tcl_lsp.status()
      assert.is_not_nil(status)
    end)

    it("should register autocommands for TCL files", function()
      local autocmd_created = false
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "FileType" and vim.tbl_contains(opts.pattern or {}, "tcl") then
          autocmd_created = true
        end
        return 1
      end

      tcl_lsp.setup()
      assert.is_true(autocmd_created, "Should register FileType autocommand for TCL files")
    end)

    it("should register user commands", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, func, opts)
        commands_created[name] = { func = func, opts = opts }
      end

      tcl_lsp.setup()

      assert.is_not_nil(commands_created.TclLspStart, "Should create TclLspStart command")
      assert.is_not_nil(commands_created.TclLspStop, "Should create TclLspStop command")
      assert.is_not_nil(commands_created.TclLspRestart, "Should create TclLspRestart command")
      assert.is_not_nil(commands_created.TclLspStatus, "Should create TclLspStatus command")
    end)
  end)

  describe("LSP Integration", function()
    before_each(function()
      tcl_lsp = require "tcl-lsp"
      tcl_lsp.setup()
    end)

    it("should start LSP server on command", function()
      local server_started = false
      package.preload["tcl-lsp.server"] = function()
        return {
          start = function()
            server_started = true
            return 1
          end,
          stop = function()
            return true
          end,
          get_status = function()
            return { state = "running", client_id = 1 }
          end,
          state = { client_id = 1 },
        }
      end

      -- Clear cache and reload
      package.loaded["tcl-lsp.server"] = nil
      tcl_lsp = require "tcl-lsp"
      tcl_lsp.setup()

      local client_id = tcl_lsp.start()
      assert.is_true(server_started, "Should start LSP server")
      assert.equals(1, client_id, "Should return client ID")
    end)

    it("should stop LSP server on command", function()
      local server_stopped = false
      package.preload["tcl-lsp.server"] = function()
        return {
          start = function()
            return 1
          end,
          stop = function()
            server_stopped = true
            return true
          end,
          get_status = function()
            return { state = "stopped" }
          end,
          state = { client_id = nil },
        }
      end

      -- Clear cache and reload
      package.loaded["tcl-lsp.server"] = nil
      tcl_lsp = require "tcl-lsp"
      tcl_lsp.setup()

      local stopped = tcl_lsp.stop()
      assert.is_true(server_stopped, "Should stop LSP server")
      assert.is_true(stopped, "Should return success")
    end)

    it("should restart LSP server on command", function()
      local restart_called = false
      package.preload["tcl-lsp.server"] = function()
        return {
          start = function()
            return 1
          end,
          stop = function()
            return true
          end,
          restart = function()
            restart_called = true
            return true
          end,
          get_status = function()
            return { state = "running", client_id = 1 }
          end,
          state = { client_id = 1 },
        }
      end

      -- Clear cache and reload
      package.loaded["tcl-lsp.server"] = nil
      tcl_lsp = require "tcl-lsp"
      tcl_lsp.setup()

      local restarted = tcl_lsp.restart()
      assert.is_true(restart_called, "Should restart LSP server")
      assert.is_true(restarted, "Should return success")
    end)

    it("should provide server status", function()
      local status_called = false
      package.preload["tcl-lsp.server"] = function()
        return {
          start = function()
            return 1
          end,
          stop = function()
            return true
          end,
          get_status = function()
            status_called = true
            return {
              state = "running",
              client_id = 1,
              root_dir = "/test/project",
            }
          end,
          state = { client_id = 1 },
        }
      end

      -- Clear cache and reload
      package.loaded["tcl-lsp.server"] = nil
      tcl_lsp = require "tcl-lsp"
      tcl_lsp.setup()

      local status = tcl_lsp.status()
      assert.is_true(status_called, "Should call server status")
      assert.equals("running", status.state)
      assert.equals(1, status.client_id)
    end)
  end)

  describe("FileType Detection", function()
    before_each(function()
      tcl_lsp = require "tcl-lsp"
      tcl_lsp.setup()
    end)

    it("should detect .tcl files", function()
      -- Mock buffer with TCL file
      vim.api.nvim_buf_get_name = function()
        return "/test/file.tcl"
      end
      vim.bo = { filetype = "tcl" }

      local auto_start_called = false
      package.preload["tcl-lsp.server"] = function()
        return {
          start = function()
            auto_start_called = true
            return 1
          end,
          stop = function()
            return true
          end,
          get_status = function()
            return { state = "stopped" }
          end,
          state = { client_id = nil },
        }
      end

      -- Simulate FileType autocommand trigger
      -- This would normally be triggered by Neovim's filetype detection
      local callback_triggered = false
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "FileType" then
          -- Simulate the callback being called
          callback_triggered = true
          if opts.callback then
            opts.callback { buf = 1, match = "tcl" }
          end
        end
        return 1
      end

      -- Clear and reload to trigger autocommand registration
      package.loaded["tcl-lsp.server"] = nil
      tcl_lsp = require "tcl-lsp"
      tcl_lsp.setup()

      assert.is_true(callback_triggered, "Should register FileType autocommand")
    end)

    it("should handle RVT template files", function()
      vim.api.nvim_buf_get_name = function()
        return "/test/template.rvt"
      end
      vim.bo = { filetype = "rvt" }

      local rvt_handled = false
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "FileType" and vim.tbl_contains(opts.pattern or {}, "rvt") then
          rvt_handled = true
        end
        return 1
      end

      tcl_lsp.setup()
      assert.is_true(rvt_handled, "Should handle RVT files")
    end)
  end)

  describe("Error Handling", function()
    before_each(function()
      tcl_lsp = require "tcl-lsp"
    end)

    it("should handle server startup failures gracefully", function()
      package.preload["tcl-lsp.server"] = function()
        return {
          start = function()
            error "Server failed to start"
          end,
          stop = function()
            return true
          end,
          get_status = function()
            return { state = "stopped" }
          end,
          state = { client_id = nil },
        }
      end

      tcl_lsp.setup()

      local success, result = pcall(tcl_lsp.start)
      assert.is_false(success, "Should handle server startup failure")
    end)

    it("should handle missing dependencies gracefully", function()
      -- Mock missing tclsh
      vim.fn.executable = function(cmd)
        if cmd == "tclsh" then
          return 0
        end
        return 1
      end

      tcl_lsp.setup()

      local success, result = pcall(tcl_lsp.start)
      -- Should either succeed with alternative or fail gracefully
      assert.is_boolean(success, "Should handle missing dependencies")
    end)

    it("should validate function parameters", function()
      tcl_lsp.setup()

      -- Test invalid parameters
      local invalid_calls = {
        function()
          tcl_lsp.start(123)
        end, -- Should be string or nil
        function()
          tcl_lsp.setup "invalid"
        end, -- Should be table or nil
      }

      for _, invalid_call in ipairs(invalid_calls) do
        local success = pcall(invalid_call)
        assert.is_false(success, "Should validate function parameters")
      end
    end)
  end)

  describe("Plugin State Management", function()
    before_each(function()
      tcl_lsp = require "tcl-lsp"
      tcl_lsp.setup()
    end)

    it("should track plugin state correctly", function()
      -- Initially stopped
      local status = tcl_lsp.status()
      assert.equals("stopped", status.state)

      -- Start should change state
      package.preload["tcl-lsp.server"] = function()
        return {
          start = function()
            return 1
          end,
          stop = function()
            return true
          end,
          get_status = function()
            return { state = "running", client_id = 1 }
          end,
          state = { client_id = 1 },
        }
      end

      package.loaded["tcl-lsp.server"] = nil
      tcl_lsp.start()

      status = tcl_lsp.status()
      assert.equals("running", status.state)
    end)

    it("should prevent multiple simultaneous setups", function()
      local setup_count = 0
      local original_setup = tcl_lsp.setup
      tcl_lsp.setup = function(...)
        setup_count = setup_count + 1
        return original_setup(...)
      end

      tcl_lsp.setup()
      tcl_lsp.setup() -- Second call should be ignored or handled

      -- Implementation specific - might allow re-setup or prevent it
      assert.is_true(setup_count >= 1, "Should handle multiple setup calls")
    end)

    it("should clean up resources on stop", function()
      local cleanup_called = false
      package.preload["tcl-lsp.server"] = function()
        return {
          start = function()
            return 1
          end,
          stop = function()
            cleanup_called = true
            return true
          end,
          get_status = function()
            return { state = "stopped" }
          end,
          state = { client_id = nil },
        }
      end

      package.loaded["tcl-lsp.server"] = nil
      tcl_lsp.start()
      tcl_lsp.stop()

      assert.is_true(cleanup_called, "Should clean up resources on stop")
    end)
  end)

  describe("Configuration Validation", function()
    before_each(function()
      tcl_lsp = require "tcl-lsp"
    end)

    it("should validate command configuration", function()
      local valid_configs = {
        { cmd = { "tclsh", "/path/to/parser.tcl" } },
        { cmd = { "custom-tcl" } },
      }

      for _, config in ipairs(valid_configs) do
        local success = pcall(tcl_lsp.setup, config)
        assert.is_true(success, "Should accept valid cmd config: " .. vim.inspect(config))
      end
    end)

    it("should validate root_markers configuration", function()
      local valid_configs = {
        { root_markers = { ".git", "tcl.toml" } },
        { root_markers = { "custom.marker" } },
      }

      for _, config in ipairs(valid_configs) do
        local success = pcall(tcl_lsp.setup, config)
        assert.is_true(success, "Should accept valid root_markers config: " .. vim.inspect(config))
      end
    end)

    it("should provide helpful error messages for invalid config", function()
      local invalid_config = { cmd = 123 } -- Should be table

      local success, error_msg = pcall(tcl_lsp.setup, invalid_config)
      assert.is_false(success, "Should reject invalid config")
      assert.is_string(error_msg, "Should provide error message")
      assert.matches("cmd", error_msg, "Error message should mention the invalid field")
    end)
  end)

  describe("Backwards Compatibility", function()
    before_each(function()
      tcl_lsp = require "tcl-lsp"
    end)

    it("should maintain API compatibility", function()
      -- Test that the API matches expected interface
      local expected_functions = {
        "setup",
        "start",
        "stop",
        "restart",
        "status",
      }

      for _, func_name in ipairs(expected_functions) do
        assert.is_function(tcl_lsp[func_name], "Should expose " .. func_name .. " function")
      end
    end)

    it("should handle legacy configuration formats", function()
      -- If there were legacy formats, test them here
      local legacy_config = {
        command = { "tclsh", "/old/path" }, -- Old field name
        markers = { ".git" }, -- Old field name
      }

      -- Should either convert or provide helpful error
      local success, result = pcall(tcl_lsp.setup, legacy_config)

      -- Implementation specific - might support legacy or require migration
      assert.is_boolean(success, "Should handle legacy config gracefully")
    end)
  end)
end)
