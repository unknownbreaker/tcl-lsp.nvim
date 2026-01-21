-- scripts/run-validator.lua
-- Headless Neovim validator runner
-- Reads JSON from stdin, validates against schema, prints results

-- Read JSON from stdin
local stdin = vim.loop.new_pipe(false)
stdin:open(0) -- stdin fd

local json_chunks = {}
local done = false

-- Read all input
stdin:read_start(function(err, chunk)
  if err then
    print("ERROR: Failed to read stdin: " .. tostring(err))
    vim.cmd "cquit 1"
    return
  end

  if chunk then
    table.insert(json_chunks, chunk)
  else
    done = true
    stdin:read_stop()
    stdin:close()
  end
end)

-- Wait for input to complete
vim.wait(5000, function()
  return done
end)

local json_input = table.concat(json_chunks)

if json_input == "" then
  print "ERROR: No input received on stdin"
  vim.cmd "cquit 1"
  return
end

-- Parse JSON
local ok, ast = pcall(vim.json.decode, json_input)
if not ok then
  print("ERROR: Failed to parse JSON: " .. tostring(ast))
  vim.cmd "cquit 1"
  return
end

-- Load validator module
local validator_ok, validator = pcall(require, "tcl-lsp.parser.validator")
if not validator_ok then
  print("ERROR: Failed to load validator: " .. tostring(validator))
  vim.cmd "cquit 1"
  return
end

-- Validate AST
local result = validator.validate_ast(ast, { strict = true })

if not result.valid then
  for _, err in ipairs(result.errors) do
    print(string.format("ERROR: %s at %s", err.message, err.path))
  end
  vim.cmd "cquit 1"
  return
end

print "OK"
vim.cmd "quit"
