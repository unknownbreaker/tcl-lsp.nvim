-- lua/tcl-lsp/parser/ast.lua
-- AST Parser Implementation
-- Delegates to TCL's built-in parser via tclsh

local M = {}

-- Debug logging (disabled by default, enable via TCL_LSP_DEBUG=1 env var)
local DEBUG = os.getenv("TCL_LSP_DEBUG") == "1"
local function debug_print(...)
  if DEBUG then
    print(...)
  end
end

-- Lazy-load validator to avoid circular dependency
local validator_loaded = false
local validator = nil

local function get_validator()
  if not validator_loaded then
    validator_loaded = true
    local ok, v = pcall(require, "tcl-lsp.parser.validator")
    if ok then
      validator = v
    end
  end
  return validator
end

-- Check if schema validation is enabled
local function should_validate()
  local ok, config = pcall(require, "tcl-lsp.config")
  if not ok then
    return false
  end

  local cfg = config.get()
  if not cfg.schema_validation then
    return false
  end

  if not cfg.schema_validation.enabled then
    return false
  end

  local mode = cfg.schema_validation.mode or "dev"
  if mode == "off" then
    return false
  end

  return true
end

-- Run schema validation on AST if enabled
local function validate_if_enabled(ast)
  if not should_validate() then
    return
  end

  local v = get_validator()
  if not v then
    return
  end

  local ok, config = pcall(require, "tcl-lsp.config")
  if not ok then
    return
  end

  local cfg = config.get()
  local strict = cfg.schema_validation.strict or false
  local log_violations = cfg.schema_validation.log_violations

  local result = v.validate_ast(ast, { strict = strict })

  if not result.valid and log_violations then
    for _, err in ipairs(result.errors) do
      debug_print(string.format("[Schema] %s at %s", err.message, err.path))
    end
  end
end

-- Get path to TCL parser script
local function get_parser_script_path()
  debug_print("[DEBUG] Starting parser path resolution...")

  -- Try multiple strategies to find the parser
  local strategies = {
    -- Strategy 1: Use debug info (works when loaded as a plugin)
    function()
      debug_print("[DEBUG] Strategy 1: Using debug info")
      local source = debug.getinfo(1, "S").source
      if source:sub(1,1) == "@" then
        local file_path = source:sub(2)
        -- Go from lua/tcl-lsp/parser/ast.lua -> project root
        local plugin_root = vim.fn.fnamemodify(file_path, ":h:h:h:h")
        local parser_path = plugin_root .. "/tcl/core/parser.tcl"
        debug_print("[DEBUG] Strategy 1 path:", parser_path)
        if vim.fn.filereadable(parser_path) == 1 then
          debug_print("[DEBUG] Strategy 1 SUCCESS")
          return parser_path
        end
      end
      debug_print("[DEBUG] Strategy 1 failed")
      return nil
    end,

    -- Strategy 2: Search runtime paths
    function()
      debug_print("[DEBUG] Strategy 2: Searching runtime paths")
      local rtp_paths = vim.api.nvim_list_runtime_paths()
      for i, path in ipairs(rtp_paths) do
        if path:match("tcl%-lsp") then
          local parser_path = path .. "/tcl/core/parser.tcl"
          debug_print(string.format("[DEBUG] Strategy 2 checking: %s", parser_path))
          if vim.fn.filereadable(parser_path) == 1 then
            debug_print("[DEBUG] Strategy 2 SUCCESS")
            return parser_path
          end
        end
      end
      debug_print("[DEBUG] Strategy 2 failed")
      return nil
    end,

    -- Strategy 3: Relative to current file (for testing)
    function()
      debug_print("[DEBUG] Strategy 3: Relative path")
      local dir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
      local parser_path = dir .. "../../../tcl/core/parser.tcl"
      debug_print("[DEBUG] Strategy 3 path:", parser_path)
      if vim.fn.filereadable(parser_path) == 1 then
        debug_print("[DEBUG] Strategy 3 SUCCESS")
        return parser_path
      end
      debug_print("[DEBUG] Strategy 3 failed")
      return nil
    end,
  }

  -- Try each strategy
  for i, strategy in ipairs(strategies) do
    local path = strategy()
    if path and vim.fn.filereadable(path) == 1 then
      debug_print(string.format("[DEBUG] ✓ Found parser at: %s", path))
      return path
    end
  end

  -- If all fail, return nil and let the error handler deal with it
  debug_print("[DEBUG] ✗ ERROR: No parser found by any strategy!")
  return nil
end

-- Execute TCL parser and get JSON result
local function execute_tcl_parser(code, filepath)
  debug_print("\n========================================")
  debug_print("TCL PARSER EXECUTION DEBUG")
  debug_print("========================================")

  debug_print("[Step 1] Input validation")
  debug_print("Code length:", #code)
  debug_print("Code sample:", code:sub(1, 50) .. (#code > 50 and "..." or ""))
  debug_print("Filepath:", filepath)

  -- Check if tclsh is available
  debug_print("\n[Step 2] Checking tclsh availability")
  if vim.fn.executable("tclsh") == 0 then
    debug_print("✗ ERROR: tclsh not found!")
    return nil, "tclsh executable not found in PATH. Please install TCL."
  end
  debug_print("✓ tclsh found")

  debug_print("\n[Step 3] Locating TCL parser script")
  local parser_script = get_parser_script_path()
  debug_print("Parser path:", tostring(parser_script))

  if not parser_script then
    debug_print("✗ ERROR: Parser script not found!")
    return nil, "TCL parser script not found. Please check plugin installation."
  end
  debug_print("✓ Parser script located")

  -- Check if parser script exists
  debug_print("\n[Step 4] Verifying parser file")
  if vim.fn.filereadable(parser_script) == 0 then
    debug_print("✗ ERROR: Parser file not readable!")
    return nil, "Parser script not found: " .. parser_script
  end
  debug_print("✓ Parser file readable")

  -- Create temporary file for TCL code
  debug_print("\n[Step 5] Creating temporary file")
  local temp_file = vim.fn.tempname() .. ".tcl"
  debug_print("Temp file:", temp_file)

  local file = io.open(temp_file, "w")
  if not file then
    debug_print("✗ ERROR: Cannot create temp file!")
    return nil, "Failed to create temporary file"
  end
  file:write(code)
  file:close()
  debug_print("✓ Temp file created and written")

  -- Execute parser
  debug_print("\n[Step 6] Executing TCL parser")
  local cmd = string.format(
    "tclsh %s %s 2>&1",
    vim.fn.shellescape(parser_script),
    vim.fn.shellescape(temp_file)
  )
  debug_print("Command:", cmd)

  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  debug_print("\n[Step 7] Parser execution results")
  debug_print("Exit code:", exit_code)
  debug_print("Output length:", #output)
  debug_print("Output sample:", output:sub(1, 200) .. (#output > 200 and "..." or ""))

  -- Clean up temp file
  vim.fn.delete(temp_file)
  debug_print("✓ Temp file cleaned up")

  if exit_code ~= 0 then
    debug_print("\n  ✗ ERROR: Parser exited with non-zero code!")
    debug_print("Full output:", output)
    return nil, "Parser error: " .. output
  end
  debug_print("✓ Parser executed successfully")

  -- Parse JSON output
  debug_print("\n[Step 8] Parsing JSON output")
  local ok, result = pcall(vim.json.decode, output)

  if not ok then
    debug_print("✗ ERROR: JSON parsing failed!")
    debug_print("Parse error:", result)
    debug_print("Raw output:", output)
    return nil, "Failed to parse JSON output: " .. tostring(result) .. "\nOutput was: " .. output:sub(1, 200)
  end

  debug_print("✓ JSON parsed successfully")
  debug_print("Result type:", type(result))
  if type(result) == "table" then
    local keys = {}
    for k, _ in pairs(result) do
      table.insert(keys, k)
    end
    debug_print("Result keys:", table.concat(keys, ", "))
  end

  debug_print("========================================")
  debug_print("DEBUG COMPLETE - Parser Success!")
  debug_print("========================================\n")

  return result, nil
end

-- Parse TCL code and return AST
function M.parse(code, filepath)
  -- Handle empty input
  if not code or code == "" then
    return {
      type = "root",
      children = {},
      range = {
        start = { line = 1, column = 1 },
        end_pos = { line = 1, column = 1 },
      },
    },
      nil
  end

  -- Check if code is only whitespace
  if code:match("^%s*$") then
    return {
      type = "root",
      children = {},
      range = {
        start = { line = 1, column = 1 },
        end_pos = { line = 1, column = 1 },
      },
    },
      nil
  end

  -- Execute TCL parser
  local ast, err = execute_tcl_parser(code, filepath or "<string>")

  if err then
    return nil, err
  end

  if not ast then
    return nil, "Parser returned nil"
  end

  -- Check if AST has errors and convert to nil return
  -- This makes tests that expect nil for syntax errors work correctly
  if ast.had_error and (ast.had_error == 1 or ast.had_error == true) then
    local error_messages = {}

    if ast.errors and type(ast.errors) == "table" then
      for _, error_node in ipairs(ast.errors) do
        if type(error_node) == "table" and error_node.message then
          local msg = error_node.message
          if type(msg) == "string" then
            table.insert(error_messages, msg)
          elseif type(msg) == "table" then
            table.insert(error_messages, vim.inspect(msg))
          else
            table.insert(error_messages, tostring(msg))
          end
        elseif type(error_node) == "string" then
          table.insert(error_messages, error_node)
        end
      end
    elseif type(ast.errors) == "string" then
      table.insert(error_messages, ast.errors)
    end

    local error_msg = "Syntax error"
    if #error_messages > 0 then
      error_msg = table.concat(error_messages, "; ")
    end

    return nil, error_msg
  end

  -- Run schema validation if enabled
  validate_if_enabled(ast)

  return ast, nil
end

-- Parse TCL file and return AST
function M.parse_file(filepath)
  -- Check if file exists
  if vim.fn.filereadable(filepath) == 0 then
    return nil, "File not found or not readable: " .. filepath
  end

  -- Read file content
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Failed to open file: " .. filepath
  end

  local content = file:read("*all")
  file:close()

  -- Parse content
  return M.parse(content, filepath)
end

return M
