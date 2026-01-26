-- lua/tcl-lsp/server.lua
-- LSP server wrapper and lifecycle management

local config = require "tcl-lsp.config"

local M = {}

-- Server state
M.state = {
  client_id = nil,
  root_dir = nil,
  status = "stopped",
}

-- Find project root directory
local function find_root_dir(start_path)
  start_path = start_path or vim.fn.getcwd()

  -- Convert file path to directory path
  if vim.fn.isdirectory(start_path) == 0 then
    start_path = vim.fn.fnamemodify(start_path, ":h")
  end

  -- Resolve symlinks and normalize path
  start_path = vim.fn.resolve(vim.fn.fnamemodify(start_path, ":p"))

  local current_dir = start_path
  local user_config = config.get()
  local root_markers = user_config.root_markers or { ".git", "tcl.toml", "project.tcl" }

  while current_dir ~= "/" and current_dir ~= "" do
    for _, marker in ipairs(root_markers) do
      local marker_path = current_dir .. "/" .. marker
      if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
        return vim.fn.resolve(vim.fn.fnamemodify(current_dir, ":p"))
      end
    end

    local parent = vim.fn.fnamemodify(current_dir, ":h")
    if parent == current_dir then
      break
    end
    current_dir = parent
  end

  -- Fallback to current directory
  return vim.fn.resolve(vim.fn.fnamemodify(start_path, ":p"))
end

-- Get server command
function M._get_server_cmd()
  local user_config = config.get()
  local user_cmd = user_config.cmd

  if user_cmd and type(user_cmd) == "table" and #user_cmd > 0 then
    return user_cmd
  end

  if vim.fn.executable "tclsh" == 0 then
    return nil
  end

  return {
    "tclsh",
    "-c",
    "puts 'TCL LSP'; while {1} { if {[gets stdin line] < 0} break; if {$line eq \"quit\"} break }",
  }
end

-- Start LSP server
function M.start(filepath)
  if M.state.status == "running" and M.state.client_id then
    local current_root = find_root_dir(filepath)
    if current_root == M.state.root_dir then
      return M.state.client_id
    end
  end

  local root_dir = find_root_dir(filepath)
  local cmd = M._get_server_cmd()
  if not cmd then
    return nil
  end

  M.state.status = "starting"
  M.state.root_dir = root_dir

  local user_config = config.get()

  local client_config = {
    name = "tcl-lsp",
    cmd = cmd,
    root_dir = root_dir,
    filetypes = user_config.filetypes or { "tcl", "rvt" },
    settings = user_config.settings or {},
    -- Remove all notifications to avoid fast event context errors
  }

  local client_id = vim.lsp.start(client_config)

  if client_id then
    M.state.client_id = client_id
    M.state.status = "running"

    -- Start background indexer (if enabled)
    local indexer_config = user_config.indexer or {}
    if indexer_config.enabled then
      local indexer = require("tcl-lsp.analyzer.indexer")
      if indexer.get_status().status == "idle" then
        indexer.start(root_dir)
      end
    end

    return client_id
  else
    M.state.status = "stopped"
    return nil
  end
end

-- Stop LSP server
function M.stop()
  if M.state.client_id then
    local client = vim.lsp.get_client_by_id(M.state.client_id)
    if client then
      client.stop()
      -- Clear state immediately for tests
      M.state.client_id = nil
      M.state.status = "stopped"
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

  if M.state.client_id then
    local client = vim.lsp.get_client_by_id(M.state.client_id)
    if client then
      client.stop()
    end
  end

  M.state.client_id = nil
  M.state.status = "stopped"

  vim.defer_fn(function()
    M.start(old_root)
  end, 200)

  return true
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
