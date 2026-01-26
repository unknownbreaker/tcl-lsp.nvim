-- lua/tcl-lsp/config.lua
-- Configuration management for TCL LSP plugin
-- Handles defaults, validation, user config merging, and buffer-local overrides

local M = {}

-- Default configuration - these values work out of the box
local defaults = {
  -- Server command (nil = auto-detect tclsh + parser.tcl)
  cmd = nil,

  -- Root directory markers for project detection
  root_markers = {
    ".git", -- Git repository
    "tcl.toml", -- Modern TCL project file
    "project.tcl", -- Legacy TCL project file
    "pkgIndex.tcl", -- TCL package index
    "Makefile", -- Build system
    ".gitroot", -- Custom root marker
  },

  -- Logging configuration
  log_level = "info", -- debug, info, warn, error

  -- Server timeout and retry configuration
  timeout = 5000, -- 5 seconds
  restart_limit = 3, -- Maximum restart attempts
  restart_cooldown = 5000, -- 5 seconds between restarts

  -- Supported file types
  filetypes = { "tcl", "rvt" },

  -- Schema validation configuration
  schema_validation = {
    enabled = false, -- Off by default for performance
    mode = "dev", -- "off", "dev", "always"
    strict = false, -- Collect all errors vs fail fast
    log_violations = true, -- Log validation errors
  },

  -- Semantic tokens configuration
  semantic_tokens = {
    enabled = true, -- Enable semantic highlighting
    debounce_ms = 150, -- Debounce delay for token requests
    large_file_threshold = 1000, -- Line count above which to skip highlighting
  },

  -- Formatting configuration
  formatting = {
    on_save = false, -- Auto-format on save (default: off)
    indent_size = nil, -- nil = auto-detect, or 2/4
    indent_style = nil, -- nil = auto-detect, or "spaces"/"tabs"
  },
}

-- Internal state management
local state = {
  config = nil, -- Current merged configuration
  has_changes = false, -- Track configuration changes - SHOULD BE FALSE INITIALLY
  initialized = false, -- Track if setup() has been called
}

-- Validation helper functions
local function validate_cmd(cmd)
  if cmd == nil then
    return true -- Auto-detect is valid
  end

  if type(cmd) ~= "table" then
    return false, "cmd must be a table (array of strings), got: " .. type(cmd)
  end

  if #cmd == 0 then
    return false, "cmd cannot be empty array"
  end

  for i, arg in ipairs(cmd) do
    if type(arg) ~= "string" then
      return false, "cmd[" .. i .. "] must be string, got: " .. type(arg)
    end
  end

  return true
end

local function validate_root_markers(markers)
  if type(markers) ~= "table" then
    return false, "root_markers must be a table, got: " .. type(markers)
  end

  if #markers == 0 then
    return false, "root_markers cannot be empty"
  end

  for i, marker in ipairs(markers) do
    if type(marker) ~= "string" then
      return false, "root_markers[" .. i .. "] must be string, got: " .. type(marker)
    end
  end

  return true
end

local function validate_log_level(level)
  if type(level) ~= "string" then
    return false, "log_level must be string, got: " .. type(level)
  end

  local valid_levels = { "debug", "info", "warn", "error" }
  for _, valid_level in ipairs(valid_levels) do
    if level == valid_level then
      return true
    end
  end

  return false, "log_level must be one of: " .. table.concat(valid_levels, ", ")
end

local function validate_numeric_field(value, field_name, allow_zero)
  if type(value) ~= "number" then
    return false, field_name .. " must be number, got: " .. type(value)
  end

  if allow_zero and value < 0 then
    return false, field_name .. " must be non-negative"
  elseif not allow_zero and value <= 0 then
    return false, field_name .. " must be positive"
  end

  return true
end

local function validate_filetypes(filetypes)
  if type(filetypes) ~= "table" then
    return false, "filetypes must be a table, got: " .. type(filetypes)
  end

  if #filetypes == 0 then
    return false, "filetypes cannot be empty"
  end

  for i, filetype in ipairs(filetypes) do
    if type(filetype) ~= "string" then
      return false, "filetypes[" .. i .. "] must be string, got: " .. type(filetype)
    end
  end

  return true
end

-- Check for circular references in configuration tables
local function has_circular_reference(tbl, seen)
  seen = seen or {}

  if seen[tbl] then
    return true
  end

  seen[tbl] = true

  for _, value in pairs(tbl) do
    if type(value) == "table" and has_circular_reference(value, seen) then
      return true
    end
  end

  seen[tbl] = nil
  return false
end

-- Comprehensive configuration validation
local function validate_config(config)
  local errors = {}

  -- Check for circular references
  if type(config) == "table" and has_circular_reference(config) then
    table.insert(errors, "Configuration contains circular references")
    return false, errors
  end

  -- Validate individual fields
  if config.cmd ~= nil then
    local valid, err = validate_cmd(config.cmd)
    if not valid then
      table.insert(errors, err)
    end
  end

  if config.root_markers then
    local valid, err = validate_root_markers(config.root_markers)
    if not valid then
      table.insert(errors, err)
    end
  end

  if config.log_level then
    local valid, err = validate_log_level(config.log_level)
    if not valid then
      table.insert(errors, err)
    end
  end

  -- Validate numeric fields
  local numeric_fields = {
    { "timeout", false }, -- Must be positive
    { "restart_limit", true }, -- Can be zero
    { "restart_cooldown", false }, -- Must be positive
  }

  for _, field_info in ipairs(numeric_fields) do
    local field_name, allow_zero = field_info[1], field_info[2]
    if config[field_name] then
      local valid, err = validate_numeric_field(config[field_name], field_name, allow_zero)
      if not valid then
        table.insert(errors, err)
      end
    end
  end

  if config.filetypes then
    local valid, err = validate_filetypes(config.filetypes)
    if not valid then
      table.insert(errors, err)
    end
  end

  return #errors == 0, (#errors > 0 and errors or nil)
end

-- Deep copy utility for immutable operations
local function deep_copy(original)
  if type(original) ~= "table" then
    return original
  end

  local copy = {}
  for key, value in pairs(original) do
    copy[key] = deep_copy(value)
  end

  return copy
end

-- PUBLIC API FUNCTIONS

-- Initialize configuration with user settings
function M.setup(user_config)
  user_config = user_config or {}

  -- Validate user configuration before applying
  local valid, errors = validate_config(user_config)
  if not valid then
    error("Invalid configuration: " .. table.concat(errors, "; "))
  end

  -- Deep merge user config with defaults
  state.config = vim.tbl_deep_extend("force", deep_copy(defaults), user_config)
  state.has_changes = false -- Should be false after setup
  state.initialized = true

  return true
end

-- Get current configuration with optional buffer-local overrides
function M.get(bufnr)
  -- Use current config or defaults if not initialized
  local base_config = state.config or defaults

  -- Get buffer number (current buffer if not specified)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Get buffer-local configuration if it exists
  local buffer_config = {}
  local success, buf_var = pcall(vim.api.nvim_buf_get_var, bufnr, "tcl_lsp_config")
  if success and buf_var then
    buffer_config = buf_var

    -- Validate buffer-local configuration
    local valid, errors = validate_config(buffer_config)
    if not valid then
      error("Invalid buffer-local configuration: " .. table.concat(errors, "; "))
    end
  end

  -- Merge base config with buffer-local overrides
  return vim.tbl_deep_extend("force", deep_copy(base_config), buffer_config)
end

-- Reset configuration to defaults
function M.reset()
  state.config = nil
  state.has_changes = false -- Should be false after reset
  state.initialized = false
end

-- Update configuration with partial changes
function M.update(partial_config)
  partial_config = partial_config or {}

  -- Validate partial configuration
  local valid, errors = validate_config(partial_config)
  if not valid then
    error("Invalid configuration update: " .. table.concat(errors, "; "))
  end

  -- Ensure we have a base configuration
  if not state.config then
    state.config = deep_copy(defaults)
  end

  -- Merge partial config with existing
  state.config = vim.tbl_deep_extend("force", state.config, partial_config)
  state.has_changes = true

  return true
end

-- Check if configuration has changed since last check (resets flag)
function M.has_changed()
  local changed = state.has_changes
  state.has_changes = false -- Reset flag after check
  return changed
end

-- Validate configuration without applying it
function M.validate(config)
  return validate_config(config)
end

-- Export current configuration (deep copy for immutability)
function M.export()
  local current_config = state.config or defaults
  return deep_copy(current_config)
end

-- Import configuration (alias for setup for clarity)
function M.import(config)
  return M.setup(config)
end

-- Get default configuration (useful for documentation/testing)
function M.get_defaults()
  return deep_copy(defaults)
end

-- Check if configuration has been initialized
function M.is_initialized()
  return state.initialized
end

-- INTERNAL FUNCTIONS (for testing and debugging)

-- Get internal state (for testing)
function M._get_state()
  return {
    config = state.config and deep_copy(state.config) or nil,
    has_changes = state.has_changes,
    initialized = state.initialized,
  }
end

-- Set internal state (for testing)
function M._set_state(new_state)
  state.config = new_state.config and deep_copy(new_state.config) or nil
  state.has_changes = new_state.has_changes or false
  state.initialized = new_state.initialized or false
end

-- Validate individual field types (for testing)
function M._validate_cmd(cmd)
  return validate_cmd(cmd)
end

function M._validate_root_markers(markers)
  return validate_root_markers(markers)
end

function M._validate_log_level(level)
  return validate_log_level(level)
end

function M._validate_filetypes(filetypes)
  return validate_filetypes(filetypes)
end

return M
