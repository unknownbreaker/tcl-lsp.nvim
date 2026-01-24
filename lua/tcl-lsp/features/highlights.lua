-- lua/tcl-lsp/features/highlights.lua
-- Semantic tokens feature for TCL LSP

local M = {}

local semantic_tokens = require("tcl-lsp.analyzer.semantic_tokens")
local parser = require("tcl-lsp.parser")

--- Get LSP server capabilities for semantic tokens
---@return table capabilities Semantic tokens provider configuration
function M.get_capabilities()
  return {
    semanticTokensProvider = {
      legend = {
        tokenTypes = semantic_tokens.token_types_legend,
        tokenModifiers = semantic_tokens.token_modifiers_legend,
      },
      full = true,
      delta = false, -- Phase 1: no delta support yet
    },
  }
end

--- Handle semantic tokens request for a buffer
---@param bufnr number Buffer number
---@return table result LSP SemanticTokens response with data array
function M.handle_semantic_tokens(bufnr)
  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return { data = {} }
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local code = table.concat(lines, "\n")
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Handle empty buffers
  if code == "" or #lines == 0 then
    return { data = {} }
  end

  local ast = parser.parse(code, filepath)
  if not ast then
    return { data = {} }
  end

  local tokens = semantic_tokens.extract_tokens(ast)
  local encoded = semantic_tokens.encode_tokens(tokens)

  return { data = encoded }
end

--- Setup semantic tokens for TCL/RVT filetypes
function M.setup()
  -- Register for TCL/RVT filetypes
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      -- Enable semantic tokens for this buffer
      vim.b[args.buf].tcl_lsp_semantic_tokens = true
    end,
  })
end

return M
