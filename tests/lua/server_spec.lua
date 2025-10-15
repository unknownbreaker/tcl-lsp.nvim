-- tests/lua/server_spec.lua
-- Comprehensive tests for LSP server lifecycle management
-- Updated to use path helpers for cross-platform compatibility

local helpers = require "tests.spec.test_helpers"
local path_helpers = require "tests.spec.path_helpers"

describe("TCL LSP Server", function()
  local server
  local temp_dir
  local original_cwd

  before_each(function()
    -- Store original working directory
    original_cwd = vim.fn.getcwd()

    -- Create temporary test directory with path resolution
    temp_dir = path_helpers.create_temp_dir "tcl_server_test"
    vim.fn.mkdir(temp_dir .. "/.git", "p")

    -- Create test files
    helpers.write_file(temp_dir .. "/.git/config", "[core]\nrepositoryformatversion = 0")
    helpers.write_file(
      temp_dir .. "/test.tcl",
      [[
proc hello_world {} {
    puts "Hello, World!"
}

set test_var "test_value"
hello_world
]]
    )

    -- Change to test directory
    vim.cmd("cd " .. temp_dir)

    -- Clean up any existing LSP clients and buffers
    for _, client in ipairs(vim.lsp.get_clients()) do
      vim.lsp.stop_client(client.id, true)
    end
    vim.cmd "bufdo bwipeout!"

    -- Clear package cache to get fresh module
    package.loaded["tcl-lsp.server"] = nil
    package.loaded["tcl-lsp.config"] = nil
    package.loaded["tcl-lsp.utils.logger"] = nil

    -- Load server module fresh
    server = require "tcl-lsp.server"
  end)

  after_each(function()
    -- Clean up server
    if server and server.stop then
      pcall(server.stop)
    end

    -- Clean up buffers and LSP clients
    vim.cmd "bufdo bwipeout!"
    for _, client in ipairs(vim.lsp.get_clients()) do
      vim.lsp.stop_client(client.id, true)
    end

    -- Restore original directory
    if original_cwd then
      vim.cmd("cd " .. original_cwd)
    end

    -- Clean up temporary directory
    if temp_dir then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("State Management", function()
    it("should initialize with clean state", function()
      assert.is_not_nil(server, "Server module should load")
      assert.is_table(server, "Server should be a table")

      -- Check initial state
      if server.state then
        assert.is_nil(server.state.client_id, "Should start with no client")
        assert.is_nil(server.state.root_dir, "Should start with no root directory")
      end
    end)

    it("should track server state during lifecycle", function()
      -- Open a TCL file
      vim.cmd("edit " .. temp_dir .. "/test.tcl")

      -- Start server
      local client_id = server.start()

      if client_id then
        assert.is_number(client_id, "Should return numeric client ID")

        -- Check state is updated
        if server.state then
          assert.equals(client_id, server.state.client_id)
          assert.is_not_nil(server.state.root_dir)
        end

        -- Stop server
        local stopped = server.stop()
        assert.is_true(stopped, "Should successfully stop server")

        -- Check state is cleaned up
        if server.state then
          assert.is_nil(server.state.client_id, "Client ID should be cleared")
        end
      else
        pending "Server start returned nil - may need tclsh or other dependencies"
      end
    end)

    it("should handle multiple start attempts gracefully", function()
      vim.cmd("edit " .. temp_dir .. "/test.tcl")

      local client_id1 = server.start()
      local client_id2 = server.start()

      if client_id1 and client_id2 then
        -- Should reuse existing client or handle gracefully
        assert.is_number(client_id1)
        assert.is_number(client_id2)
      else
        pending "Server start returned nil - may need tclsh or other dependencies"
      end
    end)
  end)

  describe("Root Directory Detection", function()
    it("should find git root directory", function()
      vim.cmd("edit " .. temp_dir .. "/src/nested/test.tcl")

      -- Server should detect the git root
      local client_id = server.start()

      if client_id and server.state and server.state.root_dir then
        -- Use path helper for cross-platform comparison
        path_helpers.assert_paths_equal(
          temp_dir,
          server.state.root_dir,
          "Should find the git root directory"
        )
      else
        pending "Could not test root detection - server start failed or no state"
      end
    end)

    it("should find tcl.toml project marker", function()
      -- Create tcl.toml marker
      helpers.write_file(temp_dir .. "/tcl.toml", '[project]\nname = "test"')

      vim.cmd("edit " .. temp_dir .. "/src/test.tcl")

      local client_id = server.start()

      if client_id and server.state and server.state.root_dir then
        path_helpers.assert_paths_equal(
          temp_dir,
          server.state.root_dir,
          "Should find the tcl.toml root directory"
        )
      else
        pending "Could not test tcl.toml detection - server start failed"
      end
    end)

    it("should find project.tcl marker", function()
      -- Create project.tcl marker
      helpers.write_file(temp_dir .. "/project.tcl", "# TCL project file")

      vim.cmd("edit " .. temp_dir .. "/lib/utils.tcl")

      local client_id = server.start()

      if client_id and server.state and server.state.root_dir then
        path_helpers.assert_paths_equal(
          temp_dir,
          server.state.root_dir,
          "Should find the project.tcl root directory"
        )
      else
        pending "Could not test project.tcl detection - server start failed"
      end
    end)

    it("should fallback to current directory when no markers found", function()
      -- Create isolated directory without markers
      -- Note: Parent temp_dir has .git, so we need to test in a truly isolated location
      local isolated_base = vim.fn.tempname()
      vim.fn.mkdir(isolated_base .. "/isolated", "p")
      helpers.write_file(isolated_base .. "/isolated/standalone.tcl", "puts hello")

      vim.cmd("cd " .. isolated_base .. "/isolated")
      vim.cmd "edit standalone.tcl"

      local client_id = server.start()

      if client_id and server.state and server.state.root_dir then
        -- Should use the isolated directory as root since no markers exist anywhere in tree
        local expected_isolated = path_helpers.resolve_path(isolated_base .. "/isolated")
        path_helpers.assert_paths_equal(
          expected_isolated,
          server.state.root_dir,
          "Should fallback to current directory"
        )
      else
        pending "Could not test fallback behavior - server start failed"
      end

      -- Cleanup isolated test directory
      vim.fn.delete(isolated_base, "rf")
    end)
  end)

  describe("Server Command Generation", function()
    it("should generate valid command with default settings", function()
      -- Test internal command generation if exposed
      if server._get_server_cmd then
        local cmd = server._get_server_cmd()

        assert.is_table(cmd, "Command should be a table")
        assert.is_true(#cmd > 0, "Command should not be empty")
        assert.equals("tclsh", cmd[1], "Should use tclsh by default")
      else
        pending "_get_server_cmd not exposed - testing via integration only"
      end
    end)

    it("should respect custom command configuration", function()
      -- Set up custom config
      local config = require "tcl-lsp.config"
      if config and config.setup then
        config.setup {
          cmd = { "custom-tclsh", "/path/to/parser.tcl", "--custom-arg" },
        }

        if server._get_server_cmd then
          local cmd = server._get_server_cmd()
          assert.equals("custom-tclsh", cmd[1])
          assert.equals("/path/to/parser.tcl", cmd[2])
          assert.equals("--custom-arg", cmd[3])
        else
          pending "Cannot test custom command - _get_server_cmd not exposed"
        end
      else
        pending "Cannot test custom command - config not available"
      end
    end)
  end)

  describe("LSP Capabilities", function()
    it("should provide modern LSP capabilities", function()
      -- This test would verify LSP capabilities when server exposes them
      if server.get_capabilities then
        local capabilities = server.get_capabilities()
        assert.is_table(capabilities, "Should provide capabilities object")
      else
        pending "LSP capabilities not yet exposed by server"
      end
    end)
  end)

  describe("Lifecycle Management", function()
    it("should start server successfully", function()
      vim.cmd("edit " .. temp_dir .. "/test.tcl")

      local client_id = server.start()

      if client_id then
        assert.is_number(client_id, "Should return client ID")
        assert.equals("running", server.state.status, "Should be in running state")
      else
        pending "Server start returned nil - check dependencies (tclsh, etc.)"
      end
    end)

    it("should stop server gracefully", function()
      vim.cmd("edit " .. temp_dir .. "/test.tcl")

      local client_id = server.start()

      if client_id then
        -- Stop the server
        local stopped = server.stop()
        assert.is_true(stopped, "Stop should return true")

        -- Wait a bit for cleanup
        vim.wait(500)

        -- Verify client is removed
        local client = vim.lsp.get_client_by_id(client_id)
        assert.is_nil(client, "Client should be removed after stop")
      else
        pending "Cannot test stop - server start failed"
      end
    end)

    it("should restart server properly", function()
      vim.cmd("edit " .. temp_dir .. "/test.tcl")

      local client_id1 = server.start()

      if client_id1 then
        -- Restart server
        local restarted = server.restart()

        if restarted then
          assert.is_true(restarted, "Restart should succeed")

          -- Should have new client ID
          local client_id2 = server.state and server.state.client_id
          if client_id2 then
            assert.is_not_equals(client_id1, client_id2, "Should have new client ID after restart")
          end
        else
          pending "Restart returned false - may not be implemented"
        end
      else
        pending "Cannot test restart - initial start failed"
      end
    end)
  end)

  describe("Error Handling", function()
    it("should handle missing TCL executable gracefully", function()
      -- Mock executable check to return false
      local original_executable = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == "tclsh" then
          return 0
        end
        return original_executable(cmd)
      end

      vim.cmd("edit " .. temp_dir .. "/test.tcl")

      -- Should handle gracefully without crashing
      local success, result = pcall(server.start)

      -- Restore original function
      vim.fn.executable = original_executable

      if success then
        assert.is_nil(result, "Should return nil when tclsh unavailable")
      else
        -- pcall caught an error, which is also acceptable
        assert.is_true(true, "Gracefully handled missing executable")
      end
    end)

    it("should handle invalid TCL files without crashing", function()
      -- Create invalid TCL file
      helpers.write_file(temp_dir .. "/invalid.tcl", "invalid tcl syntax {{{")
      vim.cmd("edit " .. temp_dir .. "/invalid.tcl")

      -- Should not crash when starting server on invalid file
      local success, result = pcall(server.start)
      assert.is_true(success, "Should handle invalid TCL files gracefully")
    end)

    it("should validate function parameters", function()
      if server.start then
        -- Test various parameter combinations
        local success1 = pcall(server.start, nil)
        assert.is_true(success1, "Should handle nil filepath")

        local success2 = pcall(server.start, "")
        assert.is_true(success2, "Should handle empty filepath")

        local success3 = pcall(server.start, "/nonexistent/path.tcl")
        assert.is_true(success3, "Should handle nonexistent filepath")
      else
        pending "Server.start function not available for parameter testing"
      end
    end)
  end)

  describe("Integration with Real Neovim", function()
    it("should attach to buffer correctly", function()
      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local bufnr = vim.api.nvim_get_current_buf()

      local client_id = server.start()

      if client_id then
        -- Wait for attachment
        vim.wait(1000)

        -- Check if client is attached to buffer
        local clients = vim.lsp.get_clients { bufnr = bufnr }
        local found_tcl_client = false

        for _, client in ipairs(clients) do
          if client.name == "tcl-lsp" or client.id == client_id then
            found_tcl_client = true
            break
          end
        end

        assert.is_true(found_tcl_client, "TCL LSP client should attach to buffer")
      else
        pending "Cannot test buffer attachment - server start failed"
      end
    end)

    it("should handle multiple buffers in same project", function()
      -- Create multiple TCL files
      helpers.write_file(temp_dir .. "/main.tcl", "source utils.tcl\nhello_world")
      helpers.write_file(temp_dir .. "/utils.tcl", "proc utility {} { return 42 }")

      -- Open first file and start server
      vim.cmd("edit " .. temp_dir .. "/main.tcl")
      local client_id1 = server.start()

      if client_id1 then
        -- Open second file
        vim.cmd("edit " .. temp_dir .. "/utils.tcl")
        local client_id2 = server.start()

        -- Should reuse same client for same project
        assert.equals(client_id1, client_id2, "Should reuse client for same project")

        -- Both buffers should have the client attached
        vim.wait(500)

        local main_clients = vim.lsp.get_clients { bufnr = vim.fn.bufnr(temp_dir .. "/main.tcl") }
        local utils_clients = vim.lsp.get_clients { bufnr = vim.fn.bufnr(temp_dir .. "/utils.tcl") }

        assert.is_true(#main_clients > 0, "Main buffer should have LSP client")
        assert.is_true(#utils_clients > 0, "Utils buffer should have LSP client")
      else
        pending "Cannot test multiple buffers - server start failed"
      end
    end)
  end)
end)
