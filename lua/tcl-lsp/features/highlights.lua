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
  local filetype = vim.bo[bufnr].filetype

  -- Handle empty buffers
  if code == "" or #lines == 0 then
    return { data = {} }
  end

  local all_tokens = {}

  if filetype == "rvt" then
    -- RVT files: extract TCL blocks and process each separately
    local rvt = require("tcl-lsp.parser.rvt")
    local blocks = rvt.find_blocks(code)

    for _, block in ipairs(blocks) do
      local ast = parser.parse(block.code, filepath)
      if ast then
        local tokens = semantic_tokens.extract_tokens(ast)
        -- Offset tokens by block position
        -- Parser returns 1-indexed lines, RVT block positions are also 1-indexed
        -- Token line 1 from parser corresponds to block.start_line in file
        for _, token in ipairs(tokens) do
          -- Line offset: token.line 1 -> block.start_line
          token.line = token.line + block.start_line - 1
          -- Note: After line offset, token.line == block.start_line is only true
          -- when original token.line was 1 (first line of block). This is when we
          -- need to apply column offset since the block may not start at column 0.
          if token.line == block.start_line then
            token.start_char = token.start_char + block.start_col - 1
          end
          table.insert(all_tokens, token)
        end
      end
    end
  else
    -- Regular TCL files: parse entire content
    local ast = parser.parse(code, filepath)
    if ast then
      all_tokens = semantic_tokens.extract_tokens(ast)
    end
  end

  return { data = semantic_tokens.encode_tokens(all_tokens) }
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
