-- tests/integration/test_lsp_server.lua
-- Integration tests for LSP server lifecycle with real Neovim environment
-- These tests run in actual Neovim instances to test real-world scenarios

local helpers = require "tests.spec.test_helpers"

describe("TCL LSP Server Integration", function()
  local temp_dir
  local server

  before_each(function()
    -- Create temporary test directory
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    -- Create test TCL files
    local test_file_content = [[
# Test TCL file for LSP testing
proc hello_world {} {
    puts "Hello, World!"
}

set test_var "test value"
hello_world
]]

    local test_file = temp_dir .. "/test.tcl"
    helpers.write_file(test_file, test_file_content)

    -- Create project markers
    helpers.write_file(temp_dir .. "/.git/config", "[core]\nrepositoryformatversion = 0")
    helpers.write_file(temp_dir .. "/tcl.toml", '[project]\nname = "test-project"')

    -- Change to test directory
    vim.cmd("cd " .. temp_dir)

    -- Require server module
    server = require "tcl-lsp.server"
  end)

  after_each(function()
    -- Clean up server
    if server then
      server.stop()
    end

    -- Clean up temporary directory
    if temp_dir then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("Real Neovim Environment", function()
    it("should start LSP server in real Neovim buffer", function()
      -- Open test file in buffer
      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local bufnr = vim.api.nvim_get_current_buf()

      -- Start LSP server
      local client_id = server.start(temp_dir .. "/test.tcl")

      -- Verify server started
      assert.is_number(client_id)
      assert.is_not_nil(server.state.client_id)

      -- Verify client is registered with Neovim
      local clients = vim.lsp.get_clients { bufnr = bufnr }
      local found_client = false
      for _, client in ipairs(clients) do
        if client.name == "tcl-lsp" then
          found_client = true
          break
        end
      end
      assert.is_true(found_client, "TCL LSP client should be registered with buffer")
    end)

    it("should detect correct root directory in real project", function()
      -- Test with .git directory
      vim.cmd("edit " .. temp_dir .. "/src/nested/test.tcl")

      local client_id = server.start()
      assert.equals(temp_dir, server.state.root_dir)
    end)

    it("should handle multiple files in same project", function()
      -- Create additional test files
      helpers.write_file(temp_dir .. "/main.tcl", "source test.tcl\nhello_world")
      helpers.write_file(temp_dir .. "/utils.tcl", "proc utility {} { return 42 }")

      -- Open first file
      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local client_id1 = server.start()

      -- Open second file
      vim.cmd("edit " .. temp_dir .. "/main.tcl")
      local client_id2 = server.start()

      -- Should reuse same server for same project
      assert.equals(client_id1, client_id2)
    end)

    it("should restart server after crash", function()
      -- Start server
      local client_id = server.start(temp_dir .. "/test.tcl")
      assert.is_not_nil(client_id)

      -- Simulate server crash by stopping client
      vim.lsp.stop_client(client_id, true)

      -- Wait for server to stop
      helpers.wait_for(function()
        return server.get_status().state == "stopped"
      end, 5000, "Server should stop after crash")

      -- Restart server
      local new_client_id = server.start(temp_dir .. "/test.tcl")
      assert.is_not_nil(new_client_id)
      assert.not_equals(client_id, new_client_id)
    end)
  end)

  describe("LSP Communication", function()
    it("should establish LSP communication with TCL parser", function()
      -- Skip if tclsh not available
      if vim.fn.executable "tclsh" == 0 then
        pending "tclsh not available for testing"
        return
      end

      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local client_id = server.start()

      -- Wait for server initialization
      helpers.wait_for(function()
        local client = vim.lsp.get_client_by_id(client_id)
        return client and client.initialized
      end, 10000, "LSP server should initialize")

      local client = vim.lsp.get_client_by_id(client_id)
      assert.is_not_nil(client)
      assert.is_true(client.initialized)
    end)

    it("should handle LSP initialize request", function()
      if vim.fn.executable "tclsh" == 0 then
        pending "tclsh not available for testing"
        return
      end

      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local client_id = server.start()

      -- Wait for initialization
      helpers.wait_for(function()
        local client = vim.lsp.get_client_by_id(client_id)
        return client and client.server_capabilities
      end, 10000, "LSP server should provide capabilities")

      local client = vim.lsp.get_client_by_id(client_id)
      assert.is_not_nil(client.server_capabilities)
    end)

    it("should handle shutdown gracefully", function()
      if vim.fn.executable "tclsh" == 0 then
        pending "tclsh not available for testing"
        return
      end

      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local client_id = server.start()

      -- Wait for initialization
      helpers.wait_for(function()
        local client = vim.lsp.get_client_by_id(client_id)
        return client and client.initialized
      end, 10000, "LSP server should initialize")

      -- Stop server
      local stopped = server.stop()
      assert.is_true(stopped)

      -- Verify client is gone
      helpers.wait_for(function()
        local client = vim.lsp.get_client_by_id(client_id)
        return client == nil
      end, 5000, "LSP client should be removed")
    end)
  end)

  describe("Error Recovery", function()
    it("should handle invalid TCL files gracefully", function()
      -- Create invalid TCL file
      local invalid_content = [[
proc broken {
    # Missing closing brace
    puts "This will cause syntax error"
]]
      helpers.write_file(temp_dir .. "/broken.tcl", invalid_content)

      vim.cmd("edit " .. temp_dir .. "/broken.tcl")

      -- Server should still start even with syntax errors
      local client_id = server.start()
      assert.is_not_nil(client_id)
    end)

    it("should handle missing TCL executable", function()
      -- Mock vim.fn.executable to return false
      local original_executable = vim.fn.executable
      vim.fn.executable = function()
        return 0
      end

      vim.cmd("edit " .. temp_dir .. "/test.tcl")

      -- Should handle gracefully
      local success, result = pcall(server.start)

      -- Restore original function
      vim.fn.executable = original_executable

      -- Server start should fail but not crash
      assert.is_false(success or result == nil)
    end)

    it("should recover from temporary network issues", function()
      -- This test would be more relevant for remote LSP servers
      -- For now, just test basic resilience
      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local client_id = server.start()

      -- Simulate temporary issue by force-stopping
      if client_id then
        vim.lsp.stop_client(client_id, true)
      end

      -- Should be able to restart
      local new_client_id = server.start()
      assert.is_not_nil(new_client_id)
    end)
  end)

  describe("Performance", function()
    it("should start server within reasonable time", function()
      local start_time = vim.loop.hrtime()

      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local client_id = server.start()

      local end_time = vim.loop.hrtime()
      local duration_ms = (end_time - start_time) / 1000000 -- Convert to milliseconds

      assert.is_not_nil(client_id)
      assert.is_true(
        duration_ms < 5000,
        "Server should start within 5 seconds, took " .. duration_ms .. "ms"
      )
    end)

    it("should handle large TCL files efficiently", function()
      -- Create a large TCL file
      local large_content = {}
      for i = 1, 1000 do
        table.insert(large_content, string.format('proc test_proc_%d {} { puts "Test %d" }', i, i))
      end

      helpers.write_file(temp_dir .. "/large.tcl", table.concat(large_content, "\n"))

      local start_time = vim.loop.hrtime()
      vim.cmd("edit " .. temp_dir .. "/large.tcl")
      local client_id = server.start()

      if client_id then
        -- Wait for server to process the large file
        helpers.wait_for(function()
          local client = vim.lsp.get_client_by_id(client_id)
          return client and client.initialized
        end, 15000, "Server should handle large file")
      end

      local end_time = vim.loop.hrtime()
      local duration_ms = (end_time - start_time) / 1000000

      assert.is_not_nil(client_id)
      assert.is_true(duration_ms < 15000, "Large file processing should complete within 15 seconds")
    end)

    it("should handle multiple rapid start/stop cycles", function()
      vim.cmd("edit " .. temp_dir .. "/test.tcl")

      for i = 1, 5 do
        local client_id = server.start()
        assert.is_not_nil(client_id, "Start cycle " .. i .. " should succeed")

        local stopped = server.stop()
        assert.is_true(stopped, "Stop cycle " .. i .. " should succeed")

        -- Brief pause between cycles
        vim.wait(100)
      end
    end)
  end)

  describe("Multi-Project Support", function()
    local temp_dir2

    before_each(function()
      -- Create second project directory
      temp_dir2 = vim.fn.tempname()
      vim.fn.mkdir(temp_dir2, "p")

      helpers.write_file(temp_dir2 .. "/project2.tcl", 'proc project2_proc {} { puts "Project 2" }')
      helpers.write_file(temp_dir2 .. "/.git/config", "[core]\nrepositoryformatversion = 0")
    end)

    after_each(function()
      if temp_dir2 then
        vim.fn.delete(temp_dir2, "rf")
      end
    end)

    it("should handle multiple projects simultaneously", function()
      -- Open file from first project
      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local client_id1 = server.start()
      local root_dir1 = server.state.root_dir

      -- Open file from second project
      vim.cmd("edit " .. temp_dir2 .. "/project2.tcl")
      local client_id2 = server.start()
      local root_dir2 = server.state.root_dir

      -- Should have different root directories
      assert.not_equals(root_dir1, root_dir2)

      -- Should use appropriate client for each project
      assert.is_not_nil(client_id1)
      assert.is_not_nil(client_id2)
    end)

    it("should switch between projects correctly", function()
      -- Start with first project
      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      server.start()
      local original_root = server.state.root_dir

      -- Switch to second project
      vim.cmd("edit " .. temp_dir2 .. "/project2.tcl")
      server.start()
      local new_root = server.state.root_dir

      assert.not_equals(original_root, new_root)
      assert.equals(temp_dir2, new_root)
    end)
  end)

  describe("Configuration Integration", function()
    it("should respect buffer-local configuration", function()
      vim.cmd("edit " .. temp_dir .. "/test.tcl")

      -- Set buffer-local configuration
      vim.b.tcl_lsp_config = {
        cmd = { "echo", "custom-command" },
        root_markers = { "custom.marker" },
      }

      local client_id = server.start()
      -- Test would need to verify custom command was used
      assert.is_not_nil(client_id)
    end)

    it("should handle configuration changes", function()
      vim.cmd("edit " .. temp_dir .. "/test.tcl")
      local client_id1 = server.start()

      -- Change configuration
      require("tcl-lsp.config").update {
        cmd = { "tclsh", "--new-option" },
      }

      -- Restart should use new configuration
      server.stop()
      local client_id2 = server.start()

      assert.not_equals(client_id1, client_id2)
    end)
  end)
end)

-- Test helper function implementations
local M = {}

-- Write content to file, creating directories as needed
function M.write_file(filepath, content)
  local dir = vim.fn.fnamemodify(filepath, ":h")
  vim.fn.mkdir(dir, "p")

  local file = io.open(filepath, "w")
  if file then
    file:write(content)
    file:close()
  else
    error("Could not write to file: " .. filepath)
  end
end

-- Wait for condition with timeout
function M.wait_for(condition, timeout_ms, error_msg)
  local start_time = vim.loop.hrtime()
  local timeout_ns = (timeout_ms or 5000) * 1000000 -- Convert to nanoseconds

  while true do
    if condition() then
      return true
    end

    local elapsed = vim.loop.hrtime() - start_time
    if elapsed > timeout_ns then
      error(error_msg or "Timeout waiting for condition")
    end

    vim.wait(50) -- Wait 50ms before checking again
  end
end

-- Create test TCL project structure
function M.create_test_project(base_dir, files)
  vim.fn.mkdir(base_dir, "p")

  for filepath, content in pairs(files or {}) do
    M.write_file(base_dir .. "/" .. filepath, content)
  end

  -- Add default git marker
  M.write_file(base_dir .. "/.git/config", "[core]\nrepositoryformatversion = 0")

  return base_dir
end

-- Performance measurement utilities
function M.measure_time(func)
  local start_time = vim.loop.hrtime()
  local result = func()
  local end_time = vim.loop.hrtime()
  local duration_ms = (end_time - start_time) / 1000000

  return result, duration_ms
end

-- Memory measurement (basic)
function M.get_memory_usage()
  return collectgarbage "count" * 1024 -- Convert KB to bytes
end

-- Test environment validation
function M.validate_test_environment()
  local issues = {}

  -- Check for required executables
  if vim.fn.executable "tclsh" == 0 then
    table.insert(issues, "tclsh executable not found")
  end

  -- Check for write permissions in temp directory
  local temp_test = vim.fn.tempname()
  local success, _ = pcall(M.write_file, temp_test, "test")
  if not success then
    table.insert(issues, "Cannot write to temporary directory")
  else
    vim.fn.delete(temp_test)
  end

  -- Check Neovim version
  local version = vim.version()
  if version.major == 0 and version.minor < 8 then
    table.insert(issues, "Neovim version too old (need 0.8+)")
  end

  return issues
end

-- Export helper functions
return M
