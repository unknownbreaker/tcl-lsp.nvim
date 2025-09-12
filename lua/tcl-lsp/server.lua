-- lua/tcl-lsp/server.lua
-- LSP server wrapper and lifecycle management

local config = require "tcl-lsp.config"

local M = {}

-- Server state
M.state = {
  client_id = nil,
  root_dir = nil,
  status = "stopped", -- stopped, starting, running, stopping
}

-- Default root directory markers
local DEFAULT_ROOT_MARKERS = {
  ".git",
  "tcl.toml",
  "project.tcl",
  ".project",
  ".tcl",
}

-- Find project root directory
local function find_root_dir(start_path)
  start_path = start_path or vim.fn.getcwd()

  -- Convert file path to directory path
  if vim.fn.isdirectory(start_path) == 0 then
    start_path = vim.fn.fnamemodify(start_path, ":h")
  end

  local current_dir = start_path
  local root_markers = config.get "root_markers" or DEFAULT_ROOT_MARKERS

  while current_dir ~= "/" and current_dir ~= "" do
    for _, marker in ipairs(root_markers) do
      local marker_path = current_dir .. "/" .. marker
      if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
        return current_dir
      end
    end

    -- Move up one directory
    local parent = vim.fn.fnamemodify(current_dir, ":h")
    if parent == current_dir then
      break -- Reached filesystem root
    end
    current_dir = parent
  end

  -- Fallback to current directory
  return start_path
end

-- Get server command
function M._get_server_cmd()
  local user_cmd = config.get "cmd"
  if user_cmd then
    return user_cmd
  end

  -- Default command
  return { "tclsh", "-" } -- Placeholder for now
end

-- Start LSP server
function M.start(filepath)
  if M.state.status == "running" and M.state.client_id then
    -- Server already running, check if same project
    local current_root = find_root_dir(filepath)
    if current_root == M.state.root_dir then
      return M.state.client_id -- Reuse existing server
    end
  end

  -- Determine root directory
  local root_dir = find_root_dir(filepath)

  -- Check if tclsh is available
  if vim.fn.executable "tclsh" == 0 then
    vim.notify("TCL LSP: tclsh executable not found", vim.log.levels.ERROR)
    return nil
  end

  M.state.status = "starting"
  M.state.root_dir = root_dir

  -- Server command
  local cmd = M._get_server_cmd()

  -- Basic LSP client configuration
  local client_config = {
    name = "tcl-lsp",
    cmd = cmd,
    root_dir = root_dir,
    filetypes = { "tcl", "rvt" },
    settings = config.get "settings" or {},
    on_attach = function(client, bufnr)
      vim.notify("TCL LSP attached to buffer " .. bufnr, vim.log.levels.INFO)
    end,
    on_exit = function(code, signal, client_id)
      M.state.status = "stopped"
      M.state.client_id = nil
      vim.notify("TCL LSP server exited (code: " .. code .. ")", vim.log.levels.WARN)
    end,
  }

  -- Start the LSP client
  local client_id = vim.lsp.start(client_config)

  if client_id then
    M.state.client_id = client_id
    M.state.status = "running"
    return client_id
  else
    M.state.status = "stopped"
    vim.notify("Failed to start TCL LSP server", vim.log.levels.ERROR)
    return nil
  end
end

-- Stop LSP server
function M.stop()
  if M.state.client_id then
    local client = vim.lsp.get_client_by_id(M.state.client_id)
    if client then
      client.stop()
      M.state.status = "stopping"
      return true
    end
  end

  M.state.status = "stopped"
  M.state.client_id = nil
  return false
end

-- Restart LSP server
function M.restart()
  local old_root = M.state.root_dir
  local stopped = M.stop()

  if stopped then
    -- Wait a moment for cleanup
    vim.defer_fn(function()
      M.start(old_root)
    end, 100)
    return true
  end

  return false
end

-- Get server status
function M.get_status()
  return {
    state = M.state.status,
    client_id = M.state.client_id,
    root_dir = M.state.root_dir,
  }
end

return M
