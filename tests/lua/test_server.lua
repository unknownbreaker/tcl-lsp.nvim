-- tests/lua/test_server.lua
-- Comprehensive tests for LSP server lifecycle management
-- Following TDD approach as outlined in the project documentation

local helpers = require "tests.spec.test_helpers"

-- Mock vim.lsp module for testing
local mock_lsp = {
  protocol = {
    make_client_capabilities = function()
      return {
        textDocument = {
          completion = {
            completionItem = {},
          },
          foldingRange = {},
          codeAction = {},
        },
      }
    end,
  },
  get_clients = function()
    return {}
  end,
  start = function()
    return 1
  end,
  stop_client = function()
    return true
  end,
  get_client_by_id = function()
    return nil
  end,
  buf_attach_client = function()
    return true
  end,
  buf_detach_client = function()
    return true
  end,
}

-- Mock vim.fs module
local mock_fs = {
  dirname = function(path)
    return "/test/project"
  end,
  find = function()
    return { "/test/project/.git" }
  end,
}

-- Mock vim.loop for time functions
local mock_loop = {
  now = function()
    return 1000
  end,
}

-- Setup mocks before requiring our module
_G.vim = {
  lsp = mock_lsp,
  fs = mock_fs,
  loop = mock_loop,
  fn = {
    getcwd = function()
      return "/test/project"
    end,
    fnamemodify = function()
      return "/test/tcl-lsp/tcl/core/parser.tcl"
    end,
  },
  api = {
    nvim_buf_get_name = function()
      return "/test/project/test.tcl"
    end,
  },
  tbl_deep_extend = function(mode, t1, t2)
    -- Simple merge for testing
    local result = {}
    for k, v in pairs(t1) do
      result[k] = v
    end
    for k, v in pairs(t2) do
      result[k] = v
    end
    return result
  end,
}

describe("TCL LSP Server", function()
  local server

  before_each(function()
    -- Reset mocks and state before each test
    mock_lsp.get_clients = function()
      return {}
    end
    mock_lsp.start = function()
      return 1
    end

    -- Clear package cache to get fresh module
    package.loaded["tcl-lsp.server"] = nil
    package.loaded["tcl-lsp.config"] = nil
    package.loaded["tcl-lsp.utils.logger"] = nil

    -- Mock dependencies
    package.preload["tcl-lsp.config"] = function()
      return {
        get = function()
          return {
            root_markers = { ".git", "tcl.toml", "project.tcl" },
            cmd = nil,
            log_level = "info",
          }
        end,
      }
    end

    package.preload["tcl-lsp.utils.logger"] = function()
      return {
        debug = function() end,
        info = function() end,
        warn = function() end,
        error = function() end,
      }
    end

    server = require "tcl-lsp.server"
  end)

  after_each(function()
    -- Clean up after each test
    if server and server.state and server.state.client_id then
      server.stop()
    end
  end)

  describe("Server State Management", function()
    it("should initialize with correct default state", function()
      assert.is_nil(server.state.client_id)
      assert.is_nil(server.state.server_process)
      assert.is_nil(server.state.root_dir)
      assert.is_nil(server.state.capabilities)
      assert.is_false(server.state.is_starting)
      assert.is_false(server.state.is_stopping)
      assert.equals(0, server.state.restart_count)
      assert.equals(3, server.state.max_restarts)
      assert.equals(0, server.state.last_restart_time)
      assert.equals(5000, server.state.restart_cooldown)
    end)

    it("should track server state during lifecycle", function()
      -- Test state changes during start
      server.start "/test/project/test.tcl"
      assert.is_not_nil(server.state.client_id)
      assert.is_not_nil(server.state.root_dir)

      -- Test state changes during stop
      server.stop()
      assert.is_nil(server.state.client_id)
    end)
  end)

  describe("Root Directory Detection", function()
    it("should find root directory with .git marker", function()
      mock_fs.find = function()
        return { "/test/project/.git" }
      end

      local root_dir = server._find_root_dir "/test/project/src/test.tcl"
      assert.equals("/test/project", root_dir)
    end)

    it("should find root directory with tcl.toml marker", function()
      mock_fs.find = function()
        return { "/test/project/tcl.toml" }
      end

      local root_dir = server._find_root_dir "/test/project/src/test.tcl"
      assert.equals("/test/project", root_dir)
    end)

    it("should find root directory with project.tcl marker", function()
      mock_fs.find = function()
        return { "/test/project/project.tcl" }
      end

      local root_dir = server._find_root_dir "/test/project/src/test.tcl"
      assert.equals("/test/project", root_dir)
    end)

    it("should fallback to current working directory when no markers found", function()
      mock_fs.find = function()
        return {}
      end

      local root_dir = server._find_root_dir "/test/project/src/test.tcl"
      assert.equals("/test/project", root_dir)
    end)

    it("should handle nested project structures", function()
      mock_fs.find = function()
        return { "/test/parent/.git" }
      end
      mock_fs.dirname = function()
        return "/test/parent"
      end

      local root_dir = server._find_root_dir "/test/parent/child/test.tcl"
      assert.equals("/test/parent", root_dir)
    end)
  end)

  describe("Server Command Generation", function()
    it("should use user-provided command when available", function()
      package.loaded["tcl-lsp.config"] = nil
      package.preload["tcl-lsp.config"] = function()
        return {
          get = function()
            return {
              cmd = { "custom-tclsh", "/custom/path/parser.tcl" },
              root_markers = { ".git" },
            }
          end,
        }
      end

      local cmd = server._get_server_cmd()
      assert.same({ "custom-tclsh", "/custom/path/parser.tcl" }, cmd)
    end)

    it("should generate default command when no user command provided", function()
      local cmd = server._get_server_cmd()
      assert.equals("tclsh", cmd[1])
      assert.matches("parser%.tcl", cmd[2])
      assert.equals("--lsp-mode", cmd[3])
    end)

    it("should handle missing TCL script gracefully", function()
      vim.fn.fnamemodify = function()
        return "/nonexistent/parser.tcl"
      end

      local cmd = server._get_server_cmd()
      assert.is_not_nil(cmd)
      assert.equals("tclsh", cmd[1])
    end)
  end)

  describe("LSP Capabilities", function()
    it("should provide modern LSP capabilities", function()
      local capabilities = server._get_default_capabilities()

      -- Test completion capabilities
      assert.is_true(capabilities.textDocument.completion.completionItem.snippetSupport)
      assert.is_true(capabilities.textDocument.completion.completionItem.preselectSupport)
      assert.is_true(capabilities.textDocument.completion.completionItem.insertReplaceSupport)

      -- Test code action capabilities
      assert.is_not_nil(capabilities.textDocument.codeAction.codeActionLiteralSupport)
      assert.is_true(capabilities.textDocument.codeAction.isPreferredSupport)
      assert.is_true(capabilities.textDocument.codeAction.dataSupport)

      -- Test folding capabilities
      assert.is_true(capabilities.textDocument.foldingRange.lineFoldingOnly)
    end)

    it("should integrate nvim-cmp capabilities when available", function()
      -- Mock nvim-cmp
      package.preload["cmp_nvim_lsp"] = function()
        return {
          default_capabilities = function()
            return {
              textDocument = {
                completion = {
                  completionItem = {
                    snippetSupport = true,
                    resolveSupport = { properties = { "documentation" } },
                  },
                },
              },
            }
          end,
        }
      end

      local capabilities = server._get_default_capabilities()
      assert.is_true(capabilities.textDocument.completion.completionItem.snippetSupport)
    end)

    it("should work without nvim-cmp installed", function()
      package.preload["cmp_nvim_lsp"] = function()
        error "Module not found"
      end

      local capabilities = server._get_default_capabilities()
      assert.is_not_nil(capabilities)
      assert.is_not_nil(capabilities.textDocument)
    end)
  end)

  describe("Server Lifecycle - Start", function()
    it("should start server successfully", function()
      local client_id = server.start "/test/project/test.tcl"

      assert.is_number(client_id)
      assert.equals(client_id, server.state.client_id)
      assert.equals("/test/project", server.state.root_dir)
      assert.is_false(server.state.is_starting)
    end)

    it("should not start multiple servers for same root directory", function()
      mock_lsp.get_clients = function()
        return {
          {
            name = "tcl-lsp",
            config = { root_dir = "/test/project" },
            id = 1,
          },
        }
      end

      local client_id = server.start "/test/project/test.tcl"
      assert.equals(1, client_id)
    end)

    it("should prevent concurrent starts", function()
      server.state.is_starting = true

      local result = server.start "/test/project/test.tcl"
      assert.is_nil(result)
    end)

    it("should return existing client if already running", function()
      server.state.client_id = 5

      local client_id = server.start "/test/project/test.tcl"
      assert.equals(5, client_id)
    end)

    it("should handle start failures gracefully", function()
      mock_lsp.start = function()
        error "Failed to start server"
      end

      local success, result = pcall(server.start, "/test/project/test.tcl")
      assert.is_false(success)
      assert.is_nil(server.state.client_id)
      assert.is_false(server.state.is_starting)
    end)
  end)

  describe("Server Lifecycle - Stop", function()
    before_each(function()
      server.state.client_id = 1
      server.state.root_dir = "/test/project"
    end)

    it("should stop server successfully", function()
      local result = server.stop()

      assert.is_true(result)
      assert.is_nil(server.state.client_id)
      assert.is_nil(server.state.root_dir)
      assert.is_false(server.state.is_stopping)
    end)

    it("should handle stop when no server running", function()
      server.state.client_id = nil

      local result = server.stop()
      assert.is_true(result) -- Should succeed even if nothing to stop
    end)

    it("should prevent concurrent stops", function()
      server.state.is_stopping = true

      local result = server.stop()
      assert.is_nil(result)
    end)

    it("should handle stop failures gracefully", function()
      mock_lsp.stop_client = function()
        return false
      end

      local result = server.stop()
      assert.is_false(result)
      -- State should still be cleaned up
      assert.is_nil(server.state.client_id)
    end)
  end)

  describe("Server Lifecycle - Restart", function()
    before_each(function()
      server.state.client_id = 1
      server.state.root_dir = "/test/project"
      server.state.restart_count = 0
      server.state.last_restart_time = 0
    end)

    it("should restart server successfully", function()
      local result = server.restart()

      assert.is_true(result)
      assert.equals(1, server.state.restart_count)
      assert.is_number(server.state.last_restart_time)
    end)

    it("should enforce restart cooldown", function()
      server.state.last_restart_time = 999 -- Recent restart
      mock_loop.now = function()
        return 1000
      end -- 1 second later

      local result = server.restart()
      assert.is_false(result) -- Should be blocked by cooldown
    end)

    it("should allow restart after cooldown period", function()
      server.state.last_restart_time = 0
      mock_loop.now = function()
        return 6000
      end -- 6 seconds later

      local result = server.restart()
      assert.is_true(result)
    end)

    it("should enforce maximum restart limit", function()
      server.state.restart_count = 3 -- At max limit

      local result = server.restart()
      assert.is_false(result)
    end)

    it("should reset restart count after successful operation", function()
      server.state.restart_count = 2
      server.reset_restart_count()

      assert.equals(0, server.state.restart_count)
    end)
  end)

  describe("Error Handling", function()
    it("should handle server process exit gracefully", function()
      local error_handled = false
      server._handle_server_error = function()
        error_handled = true
      end

      server._handle_server_error({ code = 1 }, nil)
      assert.is_true(error_handled)
    end)

    it("should attempt restart on recoverable errors", function()
      server.state.restart_count = 0
      server.state.last_restart_time = 0
      mock_loop.now = function()
        return 6000
      end

      local restart_attempted = false
      server.restart = function()
        restart_attempted = true
        return true
      end

      server._handle_server_error({ code = 1 }, nil)
      assert.is_true(restart_attempted)
    end)

    it("should not restart on non-recoverable errors", function()
      server.state.restart_count = 5 -- Exceeded max

      local restart_attempted = false
      server.restart = function()
        restart_attempted = true
        return true
      end

      server._handle_server_error({ code = 1 }, nil)
      assert.is_false(restart_attempted)
    end)

    it("should handle missing TCL executable", function()
      mock_lsp.start = function()
        error "tclsh: command not found"
      end

      local success, error_msg = pcall(server.start, "/test/project/test.tcl")
      assert.is_false(success)
      assert.matches("tclsh", error_msg)
    end)
  end)

  describe("Server Status", function()
    it("should report correct status when stopped", function()
      local status = server.get_status()

      assert.equals("stopped", status.state)
      assert.is_nil(status.client_id)
      assert.is_nil(status.root_dir)
      assert.equals(0, status.restart_count)
    end)

    it("should report correct status when running", function()
      server.state.client_id = 1
      server.state.root_dir = "/test/project"
      server.state.restart_count = 1

      local status = server.get_status()

      assert.equals("running", status.state)
      assert.equals(1, status.client_id)
      assert.equals("/test/project", status.root_dir)
      assert.equals(1, status.restart_count)
    end)

    it("should report correct status when starting", function()
      server.state.is_starting = true

      local status = server.get_status()
      assert.equals("starting", status.state)
    end)

    it("should report correct status when stopping", function()
      server.state.is_stopping = true

      local status = server.get_status()
      assert.equals("stopping", status.state)
    end)
  end)

  describe("Configuration Integration", function()
    it("should respect user configuration for root markers", function()
      package.loaded["tcl-lsp.config"] = nil
      package.preload["tcl-lsp.config"] = function()
        return {
          get = function()
            return {
              root_markers = { "custom.toml", ".custom" },
            }
          end,
        }
      end

      mock_fs.find = function(patterns)
        assert.contains("custom.toml", patterns)
        assert.contains(".custom", patterns)
        return { "/test/project/custom.toml" }
      end

      local root_dir = server._find_root_dir "/test/project/src/test.tcl"
      assert.equals("/test/project", root_dir)
    end)

    it("should respect user configuration for server command", function()
      package.loaded["tcl-lsp.config"] = nil
      package.preload["tcl-lsp.config"] = function()
        return {
          get = function()
            return {
              cmd = { "custom-tcl", "--lsp", "--debug" },
            }
          end,
        }
      end

      local cmd = server._get_server_cmd()
      assert.same({ "custom-tcl", "--lsp", "--debug" }, cmd)
    end)
  end)
end)

-- Helper function to check if table contains value
function assert.contains(expected, actual_table)
  for _, value in ipairs(actual_table) do
    if value == expected then
      return true
    end
  end
  error("Expected table to contain '" .. expected .. "' but it didn't")
end
