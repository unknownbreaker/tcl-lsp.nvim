-- lua/tcl-lsp/parser/ast.lua
-- AST Parser Implementation
-- Delegates to TCL's built-in parser via tclsh
--
-- ✅ FIXED: Path resolution improved
-- ✅ FIXED: Better error handling
-- ✅ FIXED: Proper vim.json.decode usage

local M = {}

-- Get path to TCL parser script
local function get_parser_script_path()
  -- Try multiple strategies to find the parser
  local strategies = {
    -- Strategy 1: Use debug info (works when loaded as a plugin)
    function()
      local source = debug.getinfo(1, "S").source
      if source:sub(1,1) == "@" then
        local file_path = source:sub(2)
        -- Go from lua/tcl-lsp/parser/ast.lua -> project root
        local plugin_root = vim.fn.fnamemodify(file_path, ":h:h:h:h")
        local parser_path = plugin_root .. "/tcl/core/parser.tcl"
        if vim.fn.filereadable(parser_path) == 1 then
          return parser_path
        end
      end
    end,

    -- Strategy 2: Search runtime paths
    function()
      local rtp_paths = vim.api.nvim_list_runtime_paths()
      for _, path in ipairs(rtp_paths) do
        if path:match("tcl%-lsp") then
          local parser_path = path .. "/tcl/core/parser.tcl"
          if vim.fn.filereadable(parser_path) == 1 then
            return parser_path
          end
        end
      end
    end,

    -- Strategy 3: Relative to current file (for testing)
    function()
      local dir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
      local parser_path = dir .. "../../../tcl/core/parser.tcl"
      if vim.fn.filereadable(parser_path) == 1 then
        return parser_path
      end
    end,
  }

  -- Try each strategy
  for i, strategy in ipairs(strategies) do
    local path = strategy()
    if path and vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  -- If all fail, return nil and let the error handler deal with it
  return nil
end

-- Execute TCL parser and get JSON result
local function execute_tcl_parser(code, filepath)
  -- Check if tclsh is available
  if vim.fn.executable("tclsh") == 0 then
    return nil, "tclsh executable not found in PATH. Please install TCL."
  end

  local parser_script = get_parser_script_path()

  if not parser_script then
    return nil, "TCL parser script not found. Please check plugin installation."
  end

  -- Check if parser script exists
  if vim.fn.filereadable(parser_script) == 0 then
    return nil, "Parser script not found: " .. parser_script
  end

  -- Create temporary file for TCL code
  local temp_file = vim.fn.tempname() .. ".tcl"
  local file = io.open(temp_file, "w")
  if not file then
    return nil, "Failed to create temporary file"
  end
  file:write(code)
  file:close()

  -- Execute parser
  local cmd = string.format(
    "tclsh %s %s 2>&1",
    vim.fn.shellescape(parser_script),
    vim.fn.shellescape(temp_file)
  )

  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  -- Clean up temp file
  vim.fn.delete(temp_file)

  if exit_code ~= 0 then
    return nil, "Parser error: " .. output
  end

  -- Parse JSON output
  local ok, result = pcall(vim.json.decode, output)
  if not ok then
    return nil, "Failed to parse JSON output: " .. tostring(result) .. "\nOutput was: " .. output:sub(1, 200)
  end

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
