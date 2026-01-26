-- lua/tcl-lsp/features/references.lua
-- Find-references feature for TCL LSP

local M = {}

local definitions = require("tcl-lsp.analyzer.definitions")
local references = require("tcl-lsp.analyzer.references")

--- Type label mapping for display
local TYPE_LABELS = {
  definition = "[def]",
  export = "[export]",
  call = "[call]",
}

--- Format references for quickfix list
---@param refs table List of references from analyzer
---@return table List of quickfix entries
function M.format_for_quickfix(refs)
  local entries = {}

  for _, ref in ipairs(refs) do
    local label = TYPE_LABELS[ref.type] or "[ref]"
    local line = ref.range and ref.range.start and ref.range.start.line or 1
    local col = ref.range and ref.range.start and (ref.range.start.col or ref.range.start.column or 1) or 1

    table.insert(entries, {
      filename = ref.file,
      lnum = line,
      col = col,
      text = label .. " " .. (ref.text or ""),
    })
  end

  return entries
end

--- Format references for Telescope picker
---@param refs table List of references from analyzer
---@return table List of Telescope entries
function M.format_for_telescope(refs)
  local entries = {}

  for _, ref in ipairs(refs) do
    local label = TYPE_LABELS[ref.type] or "[ref]"
    local line = ref.range and ref.range.start and ref.range.start.line or 1
    local col = ref.range and ref.range.start and (ref.range.start.col or ref.range.start.column or 1) or 1

    -- Get just the filename for display
    local filename = ref.file
    local display_name = vim.fn.fnamemodify(filename, ":t")

    table.insert(entries, {
      filename = filename,
      lnum = line,
      col = col,
      display = string.format("%s %s:%d %s", label, display_name, line, ref.text or ""),
      ordinal = filename .. ":" .. line,
      text = ref.text or "",
      type = ref.type,
    })
  end

  return entries
end

--- Find references within a single file's AST
---@param ast table Parsed AST
---@param word string Symbol name to find
---@param filepath string Path to the file
---@return table List of references found in the file
local function find_refs_in_ast(ast, word, filepath)
  local results = {}
  local extractor = require("tcl-lsp.analyzer.extractor")
  local ref_extractor = require("tcl-lsp.analyzer.ref_extractor")

  -- Get symbol definitions in this file
  local symbols = extractor.extract_symbols(ast, filepath)
  for _, sym in ipairs(symbols) do
    if sym.name == word or sym.qualified_name:match("::" .. word .. "$") then
      table.insert(results, {
        type = "definition",
        file = filepath,
        range = sym.range,
        text = sym.type .. " " .. sym.name,
      })
    end
  end

  -- Get references (calls) in this file
  local refs = ref_extractor.extract_references(ast, filepath)
  for _, ref in ipairs(refs) do
    if ref.name == word or ref.name:match("::" .. word .. "$") then
      table.insert(results, {
        type = ref.type,
        file = filepath,
        range = ref.range,
        text = ref.text,
      })
    end
  end

  return results
end

--- Handle find-references request
---@param bufnr number Buffer number
---@param line number Line number (0-indexed)
---@param col number Column number (0-indexed)
---@return table|nil List of references, or nil if not found
function M.handle_references(bufnr, line, col)
  -- Get word under cursor
  local word = vim.fn.expand("<cword>")
  if not word or word == "" then
    return nil
  end

  -- Strip $ prefix from variables
  if word:sub(1, 1) == "$" then
    word = word:sub(2)
  end

  -- Get buffer content and parse
  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local parser = require("tcl-lsp.parser")
  local ast, err = parser.parse(table.concat(content, "\n"))
  if not ast then
    return nil
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Get scope context at cursor position (1-indexed)
  local scope = require("tcl-lsp.parser.scope")
  local context = scope.get_context(ast, line + 1, col + 1)

  -- First try the cross-file index
  local symbol = definitions.find_in_index(word, context)
  if symbol then
    local refs = references.find_references(symbol.qualified_name)
    if refs and #refs > 0 then
      return refs
    end
  end

  -- Fallback: search current file AST for references
  return find_refs_in_ast(ast, word, filepath)
end

--- Show references in UI (Telescope if available, otherwise quickfix)
---@param refs table List of references
---@param word string The symbol being looked up
local function show_references(refs, word)
  if #refs == 0 then
    vim.notify("No references found for: " .. word, vim.log.levels.INFO)
    return
  end

  -- Try Telescope first
  local has_telescope, pickers = pcall(require, "telescope.pickers")
  if has_telescope then
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local telescope_entries = M.format_for_telescope(refs)

    pickers.new({}, {
      prompt_title = "References: " .. word,
      finder = finders.new_table({
        results = telescope_entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.ordinal,
            filename = entry.filename,
            lnum = entry.lnum,
            col = entry.col,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.grep_previewer({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
            vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col - 1 })
          end
        end)
        return true
      end,
    }):find()
  else
    -- Fallback to quickfix
    local qf_entries = M.format_for_quickfix(refs)
    vim.fn.setqflist(qf_entries)
    vim.cmd("copen")
  end
end

--- Set up find-references feature
--- Creates user command and registers keymaps for TCL/RVT files
function M.setup()
  -- Create user command for find-references
  vim.api.nvim_create_user_command("TclFindReferences", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1] - 1 -- Convert to 0-indexed
    local col = pos[2]

    local word = vim.fn.expand("<cword>")
    local refs = M.handle_references(bufnr, line, col)

    if refs then
      show_references(refs, word)
    else
      vim.notify("No references found", vim.log.levels.INFO)
    end
  end, { desc = "Find TCL references" })

  -- Set up keymap for TCL files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.keymap.set("n", "gr", "<cmd>TclFindReferences<cr>", {
        buffer = args.buf,
        desc = "Find references",
      })
    end,
  })
end

return M
